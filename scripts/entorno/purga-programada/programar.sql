-- Vive ADN: programa la purga de iglesias vencidas con pg_cron y pg_net. LO EJECUTA GERENCIA en la rama de pruebas, a mano y con orden escrita; no es una migración.
-- Una vez al día, en lotes pequeños, llama a la función `plataforma` con la cabecera x-adn-cron. La purga cubre el borrado programado que ya venció (adn_iglesias_vencidas).
-- Antes de ejecutarlo, Gerencia crea en la bóveda de secretos (Vault) tres entradas, sin escribirlas en ningún archivo:
--   adn_cron_secret   el mismo valor que el secreto ADN_CRON_SECRET de la función `plataforma` (32 caracteres o más)
--   adn_anon_key      la clave pública (anon) del proyecto: la pasarela exige un JWT válido antes de que la función mire x-adn-cron
--   adn_funciones_url la dirección base del proyecto, por ejemplo https://<proyecto>.supabase.co (sin barra final)
-- Se puede ejecutar más de una vez: sustituye las tareas por las mismas. Para quitarlas: desprogramar.sql. Para comprobar: verificar.sql.
\set ON_ERROR_STOP on
begin;
do $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then raise exception 'Falta la extension pg_cron: activala en Database > Extensions antes de seguir'; end if;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then raise exception 'Falta la extension pg_net: activala en Database > Extensions antes de seguir'; end if;
  if to_regclass('vault.decrypted_secrets') is null then raise exception 'Falta Vault (vault.decrypted_secrets)'; end if;
  if (select count(*) from vault.decrypted_secrets where name in ('adn_cron_secret', 'adn_anon_key', 'adn_funciones_url') and length(decrypted_secret) > 0) <> 3 then
    raise exception 'Faltan secretos en Vault: adn_cron_secret, adn_anon_key y adn_funciones_url deben existir y no estar vacios';
  end if;
  if (select length(decrypted_secret) from vault.decrypted_secrets where name = 'adn_cron_secret') < 32 then raise exception 'adn_cron_secret debe tener al menos 32 caracteres'; end if;
  if (select decrypted_secret from vault.decrypted_secrets where name = 'adn_funciones_url') !~ '^https://[^/]+$' then raise exception 'adn_funciones_url debe ser https://host, sin barra final ni ruta'; end if;
end $$;

-- Quita las tareas de una pasada anterior para no duplicarlas
select cron.unschedule(jobname) from cron.job where jobname in ('adn-purga-vencidas', 'adn-avisar-purga');

-- Purga diaria a las 03:15 UTC, hasta 10 iglesias por pasada. Si quedan más, lo dice la respuesta («restantes») y «Sistema» avisa si va atrasada (más de 48 horas).
select cron.schedule('adn-purga-vencidas', '15 3 * * *', $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'adn_funciones_url') || '/functions/v1/plataforma',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'adn_anon_key'),
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'adn_anon_key'),
      'x-adn-cron', (select decrypted_secret from vault.decrypted_secrets where name = 'adn_cron_secret')),
    body := '{"accion":"purgar_vencidas","max":10}'::jsonb);
$cron$);

-- Aviso de purga atrasada, a las 08:30 UTC. La función solo envía si va atrasada, como máximo uno al día, y nada mientras ADN_ENVIO_ACTIVO no valga «si» (apagado por defecto).
select cron.schedule('adn-avisar-purga', '30 8 * * *', $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'adn_funciones_url') || '/functions/v1/plataforma',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'adn_anon_key'),
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'adn_anon_key'),
      'x-adn-cron', (select decrypted_secret from vault.decrypted_secrets where name = 'adn_cron_secret')),
    body := '{"accion":"avisar_purga"}'::jsonb);
$cron$);
commit;
