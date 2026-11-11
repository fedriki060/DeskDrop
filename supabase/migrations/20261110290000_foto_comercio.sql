-- ==============================================================================
-- DESKDROP: FOTO DEL COMERCIO
-- ==============================================================================
--   * comercios.imagen_url: URL pública de la foto que se muestra en la lista de tiendas
--     (si es null, la app muestra la letra inicial). La edita el dueño del comercio con la
--     política que ya tiene (dueno_o_admin_edita_comercio); no hace falta una función nueva.
--   * Bucket de Storage `comercios` (público, solo imágenes, máx. 2 MB). Cada comercio guarda su
--     foto en la carpeta con su id: `<comercio_id>/foto.jpg`. Solo el dueño del comercio (o un
--     admin) puede subir, reemplazar o borrar archivos de esa carpeta; leer es libre porque el
--     bucket es público.
--   Las políticas de Storage solo se crean si el esquema `storage` existe (Supabase); en la base
--   de pruebas local de pgTAP no existe y se omiten.
--
-- Uso desde la app:
--   supabase.storage.from('comercios').upload(`${comercioId}/foto.jpg`, archivo, { upsert: true })
--   supabase.from('comercios').update({ imagen_url }).eq('id', comercioId)
-- ==============================================================================

alter table public.comercios add column if not exists imagen_url text;

comment on column public.comercios.imagen_url is
  'URL pública de la foto del comercio (bucket comercios). null = la app muestra la letra inicial.';

do $$
begin
  if to_regclass('storage.objects') is null or to_regclass('storage.buckets') is null then
    raise notice 'Esquema storage no disponible: se omite el bucket de fotos de comercios.';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('comercios', 'comercios', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

  -- Leer: cualquiera con sesión (upsert necesita poder ver el archivo anterior)
  drop policy if exists "comercios_fotos_leer" on storage.objects;
  create policy "comercios_fotos_leer" on storage.objects
    for select to authenticated
    using (bucket_id = 'comercios');

  -- Escribir: solo el dueño del comercio de esa carpeta (o un admin)
  drop policy if exists "comercios_fotos_subir" on storage.objects;
  create policy "comercios_fotos_subir" on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'comercios'
      and exists (
        select 1 from public.comercios c
        where c.id::text = split_part(name, '/', 1)
          and (public.es_dueno_comercio(c.id) or (select public.es_admin()))
      )
    );

  drop policy if exists "comercios_fotos_cambiar" on storage.objects;
  create policy "comercios_fotos_cambiar" on storage.objects
    for update to authenticated
    using (
      bucket_id = 'comercios'
      and exists (
        select 1 from public.comercios c
        where c.id::text = split_part(name, '/', 1)
          and (public.es_dueno_comercio(c.id) or (select public.es_admin()))
      )
    )
    with check (
      bucket_id = 'comercios'
      and exists (
        select 1 from public.comercios c
        where c.id::text = split_part(name, '/', 1)
          and (public.es_dueno_comercio(c.id) or (select public.es_admin()))
      )
    );

  drop policy if exists "comercios_fotos_borrar" on storage.objects;
  create policy "comercios_fotos_borrar" on storage.objects
    for delete to authenticated
    using (
      bucket_id = 'comercios'
      and exists (
        select 1 from public.comercios c
        where c.id::text = split_part(name, '/', 1)
          and (public.es_dueno_comercio(c.id) or (select public.es_admin()))
      )
    );
end $$;
