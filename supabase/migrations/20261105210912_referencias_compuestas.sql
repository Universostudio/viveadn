-- Las dos ultimas claves foraneas simples entre tablas de iglesia pasan a compuestas (iglesia_id, id).
-- Con la clave simple, zonas.lider_id e invitaciones.creada_por podian apuntar a un perfil de otra iglesia.
-- Al borrar el perfil solo se anula la columna de la persona, nunca iglesia_id (ON DELETE SET NULL con lista de columnas).

alter table public.zonas drop constraint zonas_lider_id_fkey;
alter table public.zonas add constraint zonas_lider_fk
  foreign key (iglesia_id, lider_id) references public.perfiles (iglesia_id, id) on delete set null (lider_id);

alter table public.invitaciones drop constraint invitaciones_creada_por_fkey;
alter table public.invitaciones add constraint invitaciones_creada_por_fk
  foreign key (iglesia_id, creada_por) references public.perfiles (iglesia_id, id) on delete set null (creada_por);
