-- ==============================================================================
-- DESKDROP: VALIDACIÓN DEL CARRITO
-- ==============================================================================
-- El carrito vive en el estado local de la app (ver docs/adr/003-carrito-estado-local.md).
-- La base nunca confía en él: precio, existencia e inventario se vuelven a leer aquí.
--
-- Contrato de entrada (p_items): arreglo JSON de {"producto_id": uuid, "cantidad": entero > 0}
--   [{"producto_id": "0b5c...", "cantidad": 2}, {"producto_id": "9f1a...", "cantidad": 1}]
--
-- Reglas que comprueba:
--   * Inventario: cada producto tiene unidades suficientes (suma las líneas repetidas).
--   * Un solo comercio: todos los productos pertenecen al mismo comercio.
--   * Vigencia: el producto y su comercio existen y están activos.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Tarifa de domicilio del piloto (docs/reglas_negocio_piloto.md: $2.000 COP fijos)
-- ------------------------------------------------------------------------------
-- Un único punto de cambio para la tarifa. No se expone por la Data API.
create or replace function public.tarifa_domicilio_piloto()
returns numeric
language sql
immutable
parallel safe
set search_path = ''
as $$ select 2000.00::numeric $$;

revoke all on function public.tarifa_domicilio_piloto() from public, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 2. Núcleo de evaluación (interno, lo reutiliza crear_pedido)
-- ------------------------------------------------------------------------------
-- Devuelve siempre un jsonb con esta forma:
--   {
--     "valido": true|false,
--     "comercio_id": uuid | null,
--     "items": [{"producto_id","nombre","cantidad","precio_unitario","subtotal"}],
--     "subtotal": n | null, "tarifa_domicilio": n | null, "total": n | null,   -- null si no es válido
--     "errores": [{"codigo","mensaje","producto_id"?,"solicitado"?,"disponible"?}]
--   }
-- Códigos de error: CARRITO_VACIO, FORMATO_INVALIDO, CARRITO_DEMASIADO_GRANDE, ITEM_INVALIDO,
--                   PRODUCTO_NO_DISPONIBLE, INVENTARIO_INSUFICIENTE, COMERCIOS_DISTINTOS.
--
-- p_bloquear = true: bloquea las filas de productos (FOR UPDATE, en orden de id para
-- evitar interbloqueos) hasta que termine la transacción. Así el inventario que se
-- valida es el mismo que luego se descuenta, aunque haya pedidos simultáneos.
create or replace function public._evaluar_carrito(p_items jsonb, p_bloquear boolean default false)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  c_max_lineas constant int := 50;
  v_uuid_re    constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  v_errores    jsonb := '[]'::jsonb;
  v_elem       jsonb;
  v_id         text;
  v_cantidad   int;
  v_pedido     jsonb := '{}'::jsonb;   -- { producto_id: cantidad_total }
  v_items      jsonb := '[]'::jsonb;
  v_comercios  uuid[] := '{}';
  v_subtotal   numeric := 0;
  r            record;
begin
  -- ---- Forma del arreglo -------------------------------------------------------
  if p_items is null
     or (jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) = 0) then
    v_errores := jsonb_build_array(jsonb_build_object(
      'codigo', 'CARRITO_VACIO', 'mensaje', 'El carrito está vacío.'));
  elsif jsonb_typeof(p_items) <> 'array' then
    v_errores := jsonb_build_array(jsonb_build_object(
      'codigo', 'FORMATO_INVALIDO', 'mensaje', 'El carrito debe ser un arreglo de productos.'));
  elsif jsonb_array_length(p_items) > c_max_lineas then
    v_errores := jsonb_build_array(jsonb_build_object(
      'codigo', 'CARRITO_DEMASIADO_GRANDE',
      'mensaje', format('El carrito admite máximo %s productos distintos.', c_max_lineas)));
  end if;

  -- ---- Forma de cada línea (sin tocar tablas; acumula cantidades por producto) --
  if jsonb_array_length(v_errores) = 0 then
    for v_elem in select * from jsonb_array_elements(p_items) loop
      if jsonb_typeof(v_elem) = 'object'
         and jsonb_typeof(v_elem -> 'producto_id') = 'string'
         and lower(v_elem ->> 'producto_id') ~ v_uuid_re
         and jsonb_typeof(v_elem -> 'cantidad') = 'number'
         and (v_elem ->> 'cantidad') ~ '^[1-9][0-9]{0,5}$' then
        v_id       := lower(v_elem ->> 'producto_id');
        v_cantidad := (v_elem ->> 'cantidad')::int;
        v_pedido   := jsonb_set(
                        v_pedido, array[v_id],
                        to_jsonb(coalesce((v_pedido ->> v_id)::int, 0) + v_cantidad));
      else
        v_errores := v_errores || jsonb_build_object(
          'codigo', 'ITEM_INVALIDO',
          'mensaje', 'Cada producto debe traer un producto_id válido y una cantidad entera mayor a 0.');
      end if;
    end loop;
  end if;

  if jsonb_array_length(v_errores) > 0 then
    return jsonb_build_object(
      'valido', false, 'comercio_id', null, 'items', '[]'::jsonb,
      'subtotal', null, 'tarifa_domicilio', null, 'total', null, 'errores', v_errores);
  end if;

  -- ---- Bloqueo de inventario (solo al crear el pedido) --------------------------
  if p_bloquear then
    perform 1
    from public.productos
    where id in (select key::uuid from jsonb_each_text(v_pedido))
    order by id
    for update;
  end if;

  -- ---- Existencia, vigencia e inventario ---------------------------------------
  -- Una fila por producto pedido; LEFT JOIN para detectar ids que no existen.
  for r in
    select k.key::uuid                              as producto_id,
           k.value::int                             as cantidad,
           p.id                                     as encontrado,
           p.comercio_id,
           p.nombre,
           p.precio,
           p.inventario_disponible,
           (p.activo is true and c.activo is true)  as vigente
    from jsonb_each_text(v_pedido) k
    left join public.productos p on p.id = k.key::uuid
    left join public.comercios c on c.id = p.comercio_id
    order by k.key::uuid
  loop
    if r.encontrado is null or not r.vigente then
      v_errores := v_errores || jsonb_build_object(
        'codigo', 'PRODUCTO_NO_DISPONIBLE',
        'mensaje', 'El producto no existe o ya no está disponible.',
        'producto_id', r.producto_id);
      continue;
    end if;

    if not (r.comercio_id = any (v_comercios)) then
      v_comercios := v_comercios || r.comercio_id;
    end if;

    if r.inventario_disponible < r.cantidad then
      v_errores := v_errores || jsonb_build_object(
        'codigo', 'INVENTARIO_INSUFICIENTE',
        'mensaje', format('No hay unidades suficientes de "%s".', r.nombre),
        'producto_id', r.producto_id,
        'solicitado', r.cantidad,
        'disponible', r.inventario_disponible);
    end if;

    v_subtotal := v_subtotal + r.precio * r.cantidad;
    v_items := v_items || jsonb_build_object(
      'producto_id', r.producto_id,
      'nombre', r.nombre,
      'cantidad', r.cantidad,
      'precio_unitario', r.precio,
      'subtotal', r.precio * r.cantidad);
  end loop;

  -- ---- Un solo comercio ---------------------------------------------------------
  if coalesce(array_length(v_comercios, 1), 0) > 1 then
    v_errores := v_errores || jsonb_build_object(
      'codigo', 'COMERCIOS_DISTINTOS',
      'mensaje', 'Solo puedes pedir productos de un comercio a la vez.',
      'comercios', to_jsonb(v_comercios));
  end if;

  if jsonb_array_length(v_errores) > 0 then
    return jsonb_build_object(
      'valido', false, 'comercio_id', null, 'items', v_items,
      'subtotal', null, 'tarifa_domicilio', null, 'total', null, 'errores', v_errores);
  end if;

  return jsonb_build_object(
    'valido', true,
    'comercio_id', v_comercios[1],
    'items', v_items,
    'subtotal', v_subtotal,
    'tarifa_domicilio', public.tarifa_domicilio_piloto(),
    'total', v_subtotal + public.tarifa_domicilio_piloto(),
    'errores', '[]'::jsonb);
end;
$$;

revoke all on function public._evaluar_carrito(jsonb, boolean) from public, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 3. validar_carrito (API para la app)
-- ------------------------------------------------------------------------------
-- Solo lectura: no bloquea ni modifica nada. Es una comprobación "al momento"; la
-- garantía real la da crear_pedido, que vuelve a validar con bloqueo.
-- SECURITY DEFINER para leer inventario con las mismas reglas de vigencia que el
-- catálogo, sin depender de las políticas RLS de quien llama.
create or replace function public.validar_carrito(p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  return public._evaluar_carrito(p_items, false);
end;
$$;

comment on function public.validar_carrito(jsonb) is
  'Valida inventario y un solo comercio para un carrito [{producto_id, cantidad}]. Devuelve {valido, comercio_id, items, subtotal, tarifa_domicilio, total, errores}.';

revoke all on function public.validar_carrito(jsonb) from public, anon;
grant execute on function public.validar_carrito(jsonb) to authenticated;
