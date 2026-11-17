-- Vive ADN, traspaso al proyecto real, archivo 1 de 19: comprobación previa (solo lee, no cambia nada). Si falla, NO se sigue.
set search_path = public, extensions;
do $$
begin
  if current_user <> 'postgres' then raise exception 'El rol es %, no postgres: las migraciones fijan permisos por defecto para postgres.', current_user; end if;
  if to_regclass('auth.users') is null then raise exception 'No existe auth.users: esto no parece una base de Supabase.'; end if;
  if to_regclass('public.iglesias') is null or to_regclass('public.certificados') is null or to_regprocedure('public.registrar_checkin(text, text, text, text, text, text)') is null then
    raise exception 'Esta base no está en el estado esperado del real (hasta 20261106011008): faltan objetos base. No se sigue.'; end if;
  if to_regclass('public.adn_mensajes') is not null or to_regclass('public.adn_seguimiento_metodos') is not null then
    raise exception 'Esta base ya tiene objetos del traspaso: no se vuelve a aplicar.'; end if;
  if (select count(*) from pg_tables where schemaname = 'public') <> 33 then
    raise exception 'El real debía tener 33 tablas públicas y tiene %: revisar antes de seguir.', (select count(*) from pg_tables where schemaname = 'public'); end if;
end $$;
select 'ok: el real está en el estado esperado, listo para el traspaso' as resultado, (select count(*) from public.iglesias) as iglesias, (select count(*) from auth.users) as usuarios;
