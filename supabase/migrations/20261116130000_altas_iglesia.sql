-- Asistente de alta: lo que la iglesia declara al registrarse (estructura, tamano, modulos que quiere y el equipo que piensa invitar),
-- antes de elegir plan. Solo lo escribe el servidor (la funcion de borde registro-iglesia, con service_role); la iglesia lo lee.
-- Los administradores propuestos NO reciben ningun correo ni cuenta al registrarse: un formulario publico que escribiera a terceros
-- seria un canal de abuso. Quedan guardados como sugerencia y los invita el propietario cuando entra.

create table public.altas_iglesia (
  iglesia_id uuid primary key references public.iglesias (id) on delete cascade,
  estructura text not null default 'unica' check (estructura in ('unica', 'con_sedes', 'red')),
  personas integer check (personas is null or personas between 1 and 1000000),
  sedes integer not null default 0 check (sedes between 0 and 200),
  modulos text[] not null default '{}' check (cardinality(modulos) <= 30),
  administradores jsonb not null default '[]'::jsonb
    check (jsonb_typeof(administradores) = 'array' and jsonb_array_length(administradores) <= 5),
  creada_en timestamptz not null default now(),
  check (estructura <> 'unica' or sedes = 0)
);

alter table public.altas_iglesia enable row level security;
-- Solo lectura, y solo para quien configura la iglesia: lleva correos de personas que aun no son usuarias
create policy altas_ver on public.altas_iglesia for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
grant select on public.altas_iglesia to authenticated;
grant all on public.altas_iglesia to service_role;
