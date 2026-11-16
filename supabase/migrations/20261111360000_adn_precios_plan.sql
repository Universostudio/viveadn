-- Precios por plan (modo de prueba). Solo añade tres columnas opcionales a planes: precio mensual y anual en céntimos y la moneda.
-- Quedan VACÍAS: los valores los fija quien opera la plataforma cuando estén validados (hoy son una propuesta pendiente), y mientras estén vacías el panel
-- lo dice en vez de inventar un precio. No cobra nada ni conecta ninguna pasarela. Reversión: reversiones/20261111360000_adn_precios_plan.down.sql.
alter table public.planes add column if not exists precio_mensual_centimos integer;
alter table public.planes add column if not exists precio_anual_centimos integer;
alter table public.planes add column if not exists moneda text;
alter table public.planes drop constraint if exists adn_planes_precio_coherente;
alter table public.planes add constraint adn_planes_precio_coherente check (
  (precio_mensual_centimos is null or precio_mensual_centimos between 0 and 10000000)
  and (precio_anual_centimos is null or precio_anual_centimos between 0 and 100000000)
  and (moneda is null or moneda ~ '^[A-Z]{3}$')
  and ((precio_mensual_centimos is null and precio_anual_centimos is null) or moneda is not null));
