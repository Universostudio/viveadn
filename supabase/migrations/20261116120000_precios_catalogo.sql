-- Catalogo de precios de ViveADN. TODO ES UNA PROPUESTA (ver docs/PLANES.md): ni los importes ni la moneda estan fijados
-- ni validados por un contador. La moneda y los impuestos quedan sin decidir (null) hasta que Harold los fije; mientras tanto
-- la web muestra los importes como unidades sin simbolo y avisa de que son una estimacion.
-- Son tablas globales de solo lectura para las iglesias: el catalogo lo cambia la plataforma. Aqui no se cobra nada.

create table public.precios_ajustes (
  id boolean primary key default true check (id),
  moneda text check (moneda is null or moneda ~ '^[A-Z]{3}$'),
  impuestos_incluidos boolean,
  propuesta boolean not null default true,
  actualizado_en timestamptz not null default now()
);
insert into public.precios_ajustes default values;

create table public.precios_plan (
  plan text primary key references public.planes (clave) on delete cascade,
  importe_centimos integer not null check (importe_centimos >= 0),
  actualizado_en timestamptz not null default now()
);

create table public.precios_modulo (
  modulo text primary key references public.modulos (clave) on delete cascade,
  importe_centimos integer not null check (importe_centimos >= 0),
  actualizado_en timestamptz not null default now()
);

alter table public.precios_ajustes enable row level security;
alter table public.precios_plan enable row level security;
alter table public.precios_modulo enable row level security;
create policy precios_ajustes_ver on public.precios_ajustes for select to authenticated using (true);
create policy precios_plan_ver on public.precios_plan for select to authenticated using (true);
create policy precios_modulo_ver on public.precios_modulo for select to authenticated using (true);
grant select on public.precios_ajustes, public.precios_plan, public.precios_modulo to authenticated;
grant all on public.precios_ajustes, public.precios_plan, public.precios_modulo to service_role;

-- Propuesta inicial, en centimos de la moneda base (por decidir)
insert into public.precios_plan (plan, importe_centimos) values
  ('semilla', 900), ('basico', 2900), ('premium', 7900);
insert into public.precios_modulo (modulo, importe_centimos) values
  ('formacion', 900), ('reportes', 900), ('comunicacion', 900), ('consolidacion_etapas', 900),
  ('credenciales', 900), ('op72_avanzado', 900), ('gamificacion', 500), ('biblioteca', 500),
  ('whatsapp', 1900), ('app_marca', 2900);
