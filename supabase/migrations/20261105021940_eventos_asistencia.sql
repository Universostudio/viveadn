-- Eventos y asistencia por evento.
-- Modulo nuevo "eventos" (calendario) y permisos eventos.ver / eventos.gestionar. La asistencia de
-- cada evento reutiliza los permisos del modulo asistencia (ver, registrar, registrar_propia).
-- Una serie semanal son varias filas de eventos con el mismo serie_id.

-- 1. Modulo, planes y permisos
insert into public.modulos (clave, nombre, descripcion, tipo, orden) values
  ('eventos', 'Eventos y calendario', 'Calendario de eventos, series semanales y asistencia por evento', 'incluido', 45)
on conflict (clave) do nothing;

insert into public.plan_modulos (plan, modulo) values
  ('semilla', 'eventos'), ('basico', 'eventos'), ('premium', 'eventos')
on conflict do nothing;

insert into public.permisos (clave, modulo, descripcion, sensible) values
  ('eventos.ver', 'eventos', 'Ver el calendario de eventos', false),
  ('eventos.gestionar', 'eventos', 'Crear, editar y cancelar eventos', false)
on conflict (clave) do nothing;

-- 2. Tablas
create table public.eventos (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  titulo text not null check (length(btrim(titulo)) between 1 and 150),
  descripcion text check (length(descripcion) <= 2000),
  tipo text not null default 'culto' check (tipo in ('culto', 'casa_oracion', 'formacion', 'especial', 'otro')),
  inicia_en timestamptz not null,
  termina_en timestamptz,
  lugar text check (length(lugar) <= 200),
  casa_oracion_id uuid,
  serie_id uuid,
  cancelado boolean not null default false,
  creado_por uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (termina_en is null or termina_en > inicia_en),
  unique (iglesia_id, id),
  constraint eventos_casa_fk foreign key (iglesia_id, casa_oracion_id) references public.casas_oracion (iglesia_id, id)
);
create index eventos_iglesia_inicio_idx on public.eventos (iglesia_id, inicia_en);
create index eventos_serie_idx on public.eventos (serie_id) where serie_id is not null;

create table public.asistencia_evento (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  evento_id uuid not null,
  miembro_id uuid not null,
  presente boolean not null default true,
  registrado_por uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (evento_id, miembro_id),
  constraint asistencia_evento_evento_fk foreign key (iglesia_id, evento_id) references public.eventos (iglesia_id, id) on delete cascade,
  constraint asistencia_evento_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete cascade
);
create index asistencia_evento_miembro_idx on public.asistencia_evento (miembro_id);

-- 3. Ayuda para las politicas: la casa a la que pertenece un evento, limitada a la iglesia de quien consulta
create or replace function private.casa_del_evento(p_evento uuid)
 returns uuid
 language sql
 stable security definer
 set search_path to ''
as $function$
  select e.casa_oracion_id from public.eventos e
  where e.id = p_evento and e.iglesia_id = (select private.get_iglesia_id())
$function$;
revoke execute on function private.casa_del_evento(uuid) from public, anon;
grant execute on function private.casa_del_evento(uuid) to authenticated, service_role;

-- 4. Seguridad por filas
alter table public.eventos enable row level security;
alter table public.asistencia_evento enable row level security;

create policy eventos_ver on public.eventos for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.ver')));
create policy eventos_crear on public.eventos for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));
create policy eventos_editar on public.eventos for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy eventos_borrar on public.eventos for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));

-- Quien registra una casa solo ve y registra a los miembros de su casa en los eventos de esa casa
create policy asistencia_evento_ver on public.asistencia_evento for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.ver'))
      or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(private.casa_del_evento(evento_id)))));
create policy asistencia_evento_crear on public.asistencia_evento for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.registrar'))
      or ((select private.tiene_permiso('asistencia.registrar_propia'))
          and private.es_lider_de_casa(private.casa_del_evento(evento_id))
          and private.miembro_de_casa(miembro_id, private.casa_del_evento(evento_id)))));
create policy asistencia_evento_editar on public.asistencia_evento for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.registrar'))
      or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(private.casa_del_evento(evento_id)))))
  with check (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.registrar'))
      or ((select private.tiene_permiso('asistencia.registrar_propia'))
          and private.es_lider_de_casa(private.casa_del_evento(evento_id))
          and private.miembro_de_casa(miembro_id, private.casa_del_evento(evento_id)))));
create policy asistencia_evento_borrar on public.asistencia_evento for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('asistencia.registrar')));

grant select, insert, update, delete on public.eventos, public.asistencia_evento to authenticated;
grant all on public.eventos, public.asistencia_evento to service_role;

-- 5. Permisos de eventos para los roles de sistema, tambien en las iglesias que ya existen
create or replace function private.sembrar_eventos(p_iglesia uuid)
 returns void language plpgsql security definer set search_path to ''
as $$
begin
  insert into public.rol_permisos (rol_id, permiso)
    select r.id, p.permiso
    from public.roles r
    cross join (values ('eventos.ver'), ('eventos.gestionar')) as p(permiso)
    where r.iglesia_id = p_iglesia and r.clave in ('administrador', 'coadministrador')
  on conflict do nothing;
  insert into public.rol_permisos (rol_id, permiso)
    select r.id, 'eventos.ver'
    from public.roles r
    where r.iglesia_id = p_iglesia
      and r.clave in ('lider_casa', 'lider_escuela', 'consolidador', 'miembro', 'lider_zona', 'colaborador')
  on conflict do nothing;
end;
$$;
revoke execute on function private.sembrar_eventos(uuid) from public, anon, authenticated;
grant execute on function private.sembrar_eventos(uuid) to service_role;

create or replace function private.trg_sembrar_roles()
 returns trigger language plpgsql security definer set search_path to ''
as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  perform private.sembrar_eventos(new.id);
  return new;
end;
$$;

select private.sembrar_eventos(id) from public.iglesias;
