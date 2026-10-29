-- Corrige un hueco de T-072: un usuario podía cambiarse su propio rol.
-- Supabase da por defecto ALL sobre las tablas nuevas de public a anon y authenticated.
-- El "grant update (nombre_completo, telefono)" de roles_rls SUMA permisos, no los quita:
-- authenticated ya tenía UPDATE sobre toda la tabla, incluido rol. Hay que quitar todo
-- primero y dar solo lo necesario, como se hizo con las demás tablas.

revoke all on public.perfiles from anon, authenticated;
grant select on public.perfiles to authenticated;
grant update (nombre_completo, telefono) on public.perfiles to authenticated;

-- Funciones de trigger: nadie de la app debe poder llamarlas directamente
revoke execute on function public.crear_perfil(), public.validar_dominio_correo(),
  public.proteger_dueno_comercio() from public, anon, authenticated;