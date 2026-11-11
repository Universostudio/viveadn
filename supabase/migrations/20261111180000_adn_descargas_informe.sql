-- Registro de descargas del informe de miembros: quien, cuando, que informe y cuantas filas. Nunca guarda contenido.
-- Solo altas: ninguna persona autenticada puede insertar, modificar ni borrar; el registro lo escribe el servidor al
-- servir el informe, de modo que no depende de que el navegador lo avise.
-- Reversion: supabase/reversiones/20261111180000_adn_descargas_informe.down.sql

create table public.adn_informe_descargas (
  id bigint generated always as identity primary key,
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  usuario_id uuid not null,
  informe text not null check (informe in ('miembros', 'asistencia', 'crecimiento')),
  filas integer not null check (filas >= 0),
  created_at timestamptz not null default now()
);
create index adn_informe_descargas_iglesia_idx on public.adn_informe_descargas (iglesia_id, created_at desc);

alter table public.adn_informe_descargas enable row level security;
-- Lo lee quien gestiona usuarios en su propia iglesia. No hay politicas de escritura.
create policy adn_informe_descargas_ver on public.adn_informe_descargas for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('usuarios.gestionar')));
revoke all on public.adn_informe_descargas from public, anon, authenticated;
grant select on public.adn_informe_descargas to authenticated;
grant all on public.adn_informe_descargas to service_role;

-- Un registro es inmutable: no se modifica nunca (el borrado queda para la purga de la iglesia, que corre como servicio)
create or replace function private.trg_descarga_inmutable() returns trigger language plpgsql set search_path to '' as $$
begin
  raise exception 'ADN_REGISTRO_INMUTABLE';
end $$;
create trigger adn_informe_descargas_inmutable before update on public.adn_informe_descargas
  for each row execute function private.trg_descarga_inmutable();

-- El informe pagina con .range(): la funcion se ejecuta una vez por pagina. Para que una descarga deje una sola fila,
-- una descarga del mismo informe por la misma persona dentro de dos minutos no se registra otra vez.
create or replace function private.adn_registrar_descarga(p_informe text, p_filas integer)
returns void language plpgsql security definer set search_path to '' as $$
declare ig uuid := private.get_iglesia_id(); u uuid := (select auth.uid());
begin
  if ig is null or u is null or p_informe not in ('miembros', 'asistencia', 'crecimiento') or p_filas is null or p_filas < 0 then return; end if;
  if exists (select 1 from public.adn_informe_descargas d
             where d.iglesia_id = ig and d.usuario_id = u and d.informe = p_informe and d.created_at > now() - interval '2 minutes') then
    return;
  end if;
  insert into public.adn_informe_descargas (iglesia_id, usuario_id, informe, filas) values (ig, u, p_informe, p_filas);
end $$;
revoke execute on function private.adn_registrar_descarga(text, integer) from public, anon;
grant execute on function private.adn_registrar_descarga(text, integer) to authenticated, service_role;

-- El informe de miembros pasa de stable a volatile porque ahora registra la descarga
create or replace function public.adn_informe_miembros()
returns table (crm_id text, nombre text, apellido text, email text, telefono text, fecha_nacimiento date, genero text, casa text,
               nivel_compromiso text, bautizado boolean, fecha_conversion date, activo boolean, registrado date)
language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare n integer;
begin
  if not (select private.tiene_permiso('miembros.exportar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  select count(*)::integer into n from public.miembros;
  perform private.adn_registrar_descarga('miembros', n);
  return query
  select m.crm_id, m.nombre, m.apellido, m.email, m.telefono, m.fecha_nacimiento, m.genero, h.nombre,
         m.nivel_compromiso, coalesce(m.bautizado, false), m.fecha_conversion, coalesce(m.activo, false), m.created_at::date
  from public.miembros m left join public.casas_oracion h on h.id = m.casa_oracion_id and h.iglesia_id = m.iglesia_id
  order by m.crm_id;
end $$;
