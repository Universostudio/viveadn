-- Precios por moneda. La base interna es USD; cada iglesia ve y paga en la moneda de la entidad que cobra segun su pais.
-- Empezamos con EUR y USD. Todo sigue siendo una propuesta (docs/PLANES.md): los importes en EUR repiten la cifra de USD
-- hasta que Harold y el contador fijen las listas. Aqui no se cobra nada.

create table public.monedas (
  codigo text primary key check (codigo ~ '^[A-Z]{3}$'),
  nombre text not null,
  activa boolean not null default true,
  orden integer not null default 0
);
insert into public.monedas (codigo, nombre, orden) values ('USD', 'Dolar estadounidense', 1), ('EUR', 'Euro', 2);
alter table public.monedas enable row level security;
create policy monedas_ver on public.monedas for select to authenticated using (true);
grant select on public.monedas to authenticated;
grant all on public.monedas to service_role;

-- Los precios existentes pasan a ser la lista en USD y se copia la propuesta a EUR
alter table public.precios_plan add column moneda text not null default 'USD' references public.monedas (codigo);
alter table public.precios_plan alter column moneda drop default;
alter table public.precios_plan drop constraint precios_plan_pkey, add primary key (plan, moneda);
insert into public.precios_plan (plan, moneda, importe_centimos) select plan, 'EUR', importe_centimos from public.precios_plan where moneda = 'USD';

alter table public.precios_modulo add column moneda text not null default 'USD' references public.monedas (codigo);
alter table public.precios_modulo alter column moneda drop default;
alter table public.precios_modulo drop constraint precios_modulo_pkey, add primary key (modulo, moneda);
insert into public.precios_modulo (modulo, moneda, importe_centimos) select modulo, 'EUR', importe_centimos from public.precios_modulo where moneda = 'USD';

-- Moneda base interna decidida; los impuestos siguen sin decidir
update public.precios_ajustes set moneda = 'USD' where moneda is null;
alter table public.precios_ajustes add constraint precios_ajustes_moneda_fk foreign key (moneda) references public.monedas (codigo);

-- Pais (ISO 3166-1 alfa-2) y moneda que la iglesia declaro al registrarse
alter table public.altas_iglesia add column pais_iso text check (pais_iso is null or pais_iso ~ '^[A-Z]{2}$');
alter table public.altas_iglesia add column moneda text not null default 'USD' references public.monedas (codigo);
