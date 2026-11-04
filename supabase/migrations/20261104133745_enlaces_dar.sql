-- Enlaces para dar: cada iglesia guarda la direccion web de sus propios sitios de recaudo
-- (diezmo, ofrenda, donacion). La app solo muestra un boton que lleva a ese sitio externo;
-- no procesa ni guarda pagos ni datos bancarios.

create table public.enlaces_dar (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  tipo text not null check (tipo in ('diezmo', 'ofrenda', 'donacion')),
  url text not null check (length(url) <= 500 and url ~ '^https://[^[:space:]]+$'),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (iglesia_id, tipo)
);

alter table public.enlaces_dar enable row level security;

-- Cualquier persona de la iglesia ve los enlaces para poder usar el boton
create policy enlaces_dar_ver on public.enlaces_dar for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()));

-- Solo quien configura la iglesia los crea, cambia o borra
create policy enlaces_dar_crear on public.enlaces_dar for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
create policy enlaces_dar_editar on public.enlaces_dar for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy enlaces_dar_borrar on public.enlaces_dar for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));

grant select, insert, update, delete on public.enlaces_dar to authenticated;
grant all on public.enlaces_dar to service_role;
