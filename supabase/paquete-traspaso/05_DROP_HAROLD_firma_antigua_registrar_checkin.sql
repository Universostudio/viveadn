-- Vive ADN, traspaso al proyecto real, archivo 6 de 8: DROP_HAROLD: lo único destructivo. Se aplica a mano, DESPUÉS de todos los de aplicación y ANTES de la verificación.
set search_path = public, extensions;
-- Quita la firma antigua de public.registrar_checkin (6 parámetros) que el real tiene desde la migración del check-in QR y que la migración nueva sustituye por la de 10 parámetros.
-- No toca datos: es solo la definición de una función. Mientras no se aplique, conviven las dos firmas y una llamada con exactamente 6 argumentos sería ambigua;
-- por eso hay que aplicarlo antes de redesplegar checkin-evento.

-- (20261111210000_adn_consentimiento_evidencia: firma que el real ya tiene)
-- Registro por QR: dos parámetros opcionales (versión del texto aceptado e idioma) y la anotación de la evidencia
drop function public.registrar_checkin(text, text, text, text, text, text);
