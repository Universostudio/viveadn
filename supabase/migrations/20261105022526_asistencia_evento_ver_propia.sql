-- Correccion de asistencia_evento_ver: el rol colaborador registra asistencia con asistencia.registrar
-- y solo ve lo que el mismo registra (asistencia.ver_propia), igual que en la asistencia de casas.
-- Sin esta rama, al insertar y pedir la fila de vuelta la politica de lectura la rechazaba y el
-- colaborador no podia marcar asistencia.
drop policy asistencia_evento_ver on public.asistencia_evento;
create policy asistencia_evento_ver on public.asistencia_evento for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.ver'))
      or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(private.casa_del_evento(evento_id)))
      or ((select private.tiene_permiso('asistencia.ver_propia')) and registrado_por = (select auth.uid()))));
