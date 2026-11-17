-- Vive ADN, traspaso al proyecto real, archivo 19 de 19: registro de las migraciones en supabase_migrations. PASO APARTE: solo después de que la verificación salga toda en verde.
-- Anota las 29 versiones del repositorio para que el historial del proyecto real coincida con el de la rama. Solo añade filas (created_by queda vacío) y se puede repetir.
insert into supabase_migrations.schema_migrations (version, name) values
  ('20261111120000', 'adn_ciclo_vida'),
  ('20261111130000', 'adn_exportacion'),
  ('20261111140000', 'adn_importar_contactos'),
  ('20261111150000', 'adn_informes'),
  ('20261111160000', 'adn_comunicacion'),
  ('20261111170000', 'adn_panel_inicio'),
  ('20261111180000', 'adn_descargas_informe'),
  ('20261111190000', 'adn_consentimiento'),
  ('20261111200000', 'adn_consentimiento_auditoria'),
  ('20261111210000', 'adn_consentimiento_evidencia'),
  ('20261111220000', 'adn_checkin_canales'),
  ('20261111230000', 'adn_doble_confirmacion'),
  ('20261111240000', 'adn_purga_estado'),
  ('20261111250000', 'adn_purgas_libro'),
  ('20261111260000', 'adn_exportacion_paginada'),
  ('20261111270000', 'adn_autoservicio_datos'),
  ('20261111280000', 'adn_envios_topes'),
  ('20261111290000', 'adn_plataforma_resumen'),
  ('20261111300000', 'adn_checkin_nuevo_creyente'),
  ('20261111310000', 'adn_asistencias_unico'),
  ('20261111320000', 'adn_seguimiento_metodos'),
  ('20261111330000', 'adn_seguimiento_metricas'),
  ('20261111340000', 'adn_seguimiento_propio'),
  ('20261111350000', 'adn_soporte'),
  ('20261111360000', 'adn_precios_plan'),
  ('20261111370000', 'adn_prueba_vencida_lectura'),
  ('20261111380000', 'adn_purga_tarea_estado'),
  ('20261111390000', 'adn_soporte_prueba_vencida'),
  ('20261111400000', 'adn_agregados_plataforma')
on conflict (version) do nothing;
select count(*) as migraciones_registradas from supabase_migrations.schema_migrations;
