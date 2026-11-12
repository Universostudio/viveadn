-- Vive ADN, paquete de aplicación 00: comprobación de base vacía. No cambia nada. Si falla, NO se sigue.
set search_path = public, extensions;
do $$
begin
  if current_user <> 'postgres' then
    raise exception 'El rol es %, no postgres: los permisos por defecto de las migraciones se fijan para el rol postgres y los objetos saldrían con otros permisos. Avisar a Desarrollo.', current_user;
  end if;
  if to_regclass('public.iglesias') is not null then
    raise exception 'La base ya tiene el esquema de Vive ADN: no se toca. Usa un proyecto vacío.';
  end if;
  if to_regclass('auth.users') is null then
    raise exception 'No existe auth.users: esto no parece una base de Supabase.';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'extensions') then
    raise exception 'No existe el esquema extensions: esto no parece una base de Supabase.';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'private') then
    raise exception 'Ya existe el esquema private: la base no está vacía.';
  end if;
end $$;
select 'ok: base vacía de Supabase, rol postgres' as resultado;
