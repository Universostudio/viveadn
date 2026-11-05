-- Almacenamiento de archivos con aislamiento por iglesia.
-- Dos cubos; en ambos la primera carpeta de la ruta es el id de la iglesia: {iglesia_id}/...
--   iglesia-marca     publico para leer (logos que ven las paginas publicas). SVG excluido: puede llevar scripts.
--   iglesia-archivos  privado (documentos, certificados, fotos). Se lee con URL firmada.
-- Escribir exige el permiso iglesia.configurar. Leer en el cubo privado exige que la iglesia este operativa.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('iglesia-marca', 'iglesia-marca', true, 2097152, array['image/png', 'image/jpeg', 'image/webp']),
  ('iglesia-archivos', 'iglesia-archivos', false, 10485760, array['application/pdf', 'image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- La carpeta raiz de la ruta debe ser la iglesia de quien pregunta
create or replace function private.ruta_de_mi_iglesia(p_ruta text)
returns boolean language sql stable security definer set search_path to '' as $$
  select (storage.foldername(p_ruta))[1] = (select private.get_iglesia_id())::text
$$;
revoke all on function private.ruta_de_mi_iglesia(text) from public, anon, authenticated, service_role;
grant execute on function private.ruta_de_mi_iglesia(text) to authenticated;

create policy archivos_marca_leer on storage.objects for select to authenticated
  using (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)));
create policy archivos_marca_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));
create policy archivos_marca_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')))
  with check (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));
create policy archivos_marca_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));

create policy archivos_privado_leer on storage.objects for select to authenticated
  using (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_modulo('iglesia')));
create policy archivos_privado_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));
create policy archivos_privado_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')))
  with check (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));
create policy archivos_privado_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));
