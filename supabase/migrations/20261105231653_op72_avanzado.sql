-- OP72 gratuito y de pago.
--   Gratuito (modulo consolidacion, en todos los planes): registro, asignacion, tres contactos, resultado y las 72 horas con su color.
--   De pago (modulo op72_avanzado, en Basico y Premium, o como complemento en Semilla): metricas avanzadas del seguimiento.
--   Las alertas automaticas por correo o WhatsApp quedan para cuando exista el canal de envio.
-- El modulo se activa con la maquinaria de planes y complementos que ya existe: no hay logica nueva de licencias.

insert into public.modulos (clave, nombre, descripcion, tipo, orden) values
  ('op72_avanzado', 'OP72 avanzado', 'Metricas avanzadas del seguimiento de 72 horas por consolidador y por casa', 'especial', 215)
on conflict (clave) do nothing;
insert into public.plan_modulos (plan, modulo) values ('basico', 'op72_avanzado'), ('premium', 'op72_avanzado')
on conflict do nothing;

-- Metricas del periodo. Exige ver toda la consolidacion de la iglesia (consolidacion.ver) y se ejecuta con los permisos de
-- quien llama, asi que solo cuenta las consolidaciones que su rol puede ver. Viven en Consolidacion y no en Reportes porque
-- Consolidacion esta en todos los planes y Reportes no.
create or replace function public.metricas_op72(p_desde timestamptz default (now() - interval '30 days'))
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare r jsonb;
begin
  if not (select private.tiene_modulo('op72_avanzado')) then
    raise exception 'MODULO_NO_CONTRATADO' using errcode = '42501';
  end if;
  if not (select private.tiene_permiso('consolidacion.ver')) then
    raise exception 'SIN_PERMISO' using errcode = '42501';
  end if;
  with c as (
    select co.consolidador_id, co.casa_oracion_id, co.completado, co.completado_at, co.fecha_conversion, co.primer_contacto_fecha,
           (co.completado is not true and now() - co.fecha_conversion > interval '72 hours') as vencido,
           extract(epoch from (co.primer_contacto_fecha - co.fecha_conversion)) / 3600 as h_primer
      from public.consolidaciones co
     where co.fecha_conversion >= p_desde
  )
  select jsonb_build_object(
    'desde', p_desde,
    'total', count(*),
    'completados', count(*) filter (where completado),
    'abiertos', count(*) filter (where completado is not true),
    'vencidos', count(*) filter (where vencido),
    'con_primer_contacto', count(*) filter (where primer_contacto_fecha is not null),
    'primer_contacto_24h', count(*) filter (where h_primer <= 24),
    'horas_primer_contacto', round((avg(h_primer) filter (where h_primer >= 0))::numeric, 1),
    'completados_72h', count(*) filter (where completado and completado_at <= fecha_conversion + interval '72 hours'),
    'por_consolidador', coalesce((
      select jsonb_agg(t order by t.total desc, t.nombre)
        from (select x.consolidador_id, coalesce(btrim(p.nombre || ' ' || p.apellido), '') as nombre, count(*) as total,
                     count(*) filter (where x.h_primer <= 24) as contacto_24h, count(*) filter (where x.vencido) as vencidos
                from c x left join public.perfiles p on p.id = x.consolidador_id
               group by x.consolidador_id, p.nombre, p.apellido
               order by count(*) desc limit 10) t), '[]'::jsonb),
    'por_casa', coalesce((
      select jsonb_agg(t order by t.total desc, t.nombre)
        from (select x.casa_oracion_id, coalesce(ca.nombre, '') as nombre, count(*) as total, count(*) filter (where x.vencido) as vencidos
                from c x left join public.casas_oracion ca on ca.id = x.casa_oracion_id
               group by x.casa_oracion_id, ca.nombre
               order by count(*) desc limit 10) t), '[]'::jsonb)
  ) into r from c;
  return r;
end;
$$;
revoke all on function public.metricas_op72(timestamptz) from public, anon;
grant execute on function public.metricas_op72(timestamptz) to authenticated;
