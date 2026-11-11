# Análisis de coste del envío de correo (para aprobación de Gerencia)

Estado a 11 de noviembre de 2026. Regla de Harold, transmitida por Gerencia: ningún servicio de pago nuevo ni gasto recurrente se integra sin un análisis previo de coste por unidad y tope técnico, aprobado por Gerencia. **Este documento es el análisis. No se ha implementado ningún envío nuevo.**

Etiquetas: **[E]** leído de una fuente oficial hoy o medido, **[H]** deducido, **[NV]** no verificable desde aquí.

## 1. Qué correos se enviarían

| Correo | Quién lo recibe | Cuándo | Datos de personas |
| --- | --- | --- | --- |
| Alerta de purga atrasada (trabajo c) | La persona que opera la plataforma | Como máximo una vez al día, solo si la tarjeta «Purga programada» marca retraso | Ninguno: solo cifras |
| Aviso de baja pedida o cancelada | El propietario de la iglesia | Una vez por cada baja pedida y una por cada cancelación | El correo del propietario |
| Ya existentes, sin cambios | Invitaciones de acceso y doble confirmación del check-in (apagada por defecto) | Por cada invitación o alta con correo | El correo de la persona |

Mensajes masivos de Comunicación (`docs/COMUNICACION.md`) quedan fuera: hoy no envían nada real y exigirán su propio análisis.

## 2. Precios leídos hoy

Fuentes oficiales, leídas el 11 de noviembre de 2026 con una herramienta de lectura de páginas web (el resumen lo extrajo un modelo, así que Gerencia debe abrir las dos direcciones antes de aprobar): `https://bird.com/pricing/email.md` y `https://resend.com/pricing`. Dólares estadounidenses.

| | Bird (el proveedor que ya usa `invitaciones`) | Resend |
| --- | --- | --- |
| Plan gratuito | 1.000 correos al mes, **50 al día**, 1 dominio | 3.000 al mes, **100 al día**, 3 dominios |
| Primer plan de pago | Startup: depósito de 15 $ al mes (saldo gastable, sin envíos incluidos), 0,40 $ por cada 1.000 (unos 37.500 con el depósito) | Pro: 20 $ al mes con 50.000 incluidos (0,40 $ por 1.000), o 35 $ con 100.000 |
| Más volumen | Growth: 250 $ de depósito, 0,45 $ por 1.000. Scale: de 0,35 a 0,20 $ por 1.000 | Exceso a 0,90 $ por 1.000 en Pro; Scale desde 90 $ con 100.000 y exceso de 0,90 a 0,46 $ |
| Tope diario en los planes de pago | Sin tope | Sin tope |
| IP dedicada | Complemento de pago, precio no publicado en la página [NV] | 30 $ al mes, solo en Scale |
| Límite de peticiones | Gratuito 10 por minuto; Startup 30 por minuto | Igual para todos los planes, sin cifra publicada [NV] |
| Exceso sobre el depósito | La página no dice el precio del exceso [NV] | Explícito |

Notas: el depósito de Bird es saldo que se arrastra y puede pagar otros productos de Bird; no es una cuota perdida. En ninguno de los dos hay pago por correo ni por dominio en el plan gratuito.

## 3. Volumen esperado por iglesia

[H] Supuestos míos, a revisar con datos reales: por iglesia y mes, unas 5 invitaciones, hasta 30 confirmaciones de check-in con correo (solo si Gerencia enciende la doble confirmación), 0,1 alertas y 0,02 avisos de baja: **unos 40 correos al mes por iglesia**. Sin Comunicación masiva.

| Iglesias | Correos al mes | Bird | Resend |
| --- | --- | --- | --- |
| 50 | 2.000 | Gratuito no alcanza (1.000): Startup, 15 $ de depósito, gasto real 0,80 $ | Gratuito: 0 $ |
| 500 | 20.000 | Startup: 15 $ de depósito, gasto real 8 $ | Pro: 20 $ |
| 5.000 | 200.000 | Growth: 250 $ de depósito, gasto real 90 $ | Scale de 200.000: 160 $ |

Coste por unidad con volumen: **0,40 $ por 1.000 correos en ambos** en el tramo bajo (Bird 0,40 $; Resend 20 $ por 50.000). Con 200.000 al mes, Resend sale a unos 0,80 $ por 1.000 y Bird a 0,45 $ por 1.000 más su depósito. [H]

Solo las alertas de purga (máximo 31 al mes) y los avisos de baja (unas decenas al mes) caben en cualquiera de los dos planes gratuitos: **coste 0 $**.

## 4. Peor caso de abuso y tope técnico

Los envíos que alguien puede provocar desde fuera son los de la doble confirmación del check-in público: cualquiera puede escribir un correo ajeno y hacer que Vive ADN le escriba. Los demás los dispara una cuenta autenticada o el servidor.

- **Sin tope**: un script que repita altas de check-in con correos distintos podría enviar decenas de miles al día. Con 100.000 al día, a 0,40 $ por 1.000 son 40 $ al día en Bird y 90 $ al día en el exceso de Resend; el mayor daño real no es el dinero sino la reputación del dominio y el bloqueo del proveedor. [H]
- **Con tope por tipo y por día**: propongo un contador en la base (`adn_envios_dia`: tipo, fecha, cuenta) que la función consulta antes de enviar, con topes distintos y configurables por variable: alerta de purga 1 al día; aviso de baja 2 por iglesia y día; doble confirmación 200 por iglesia y día, 2.000 en toda la plataforma. Si se alcanza el tope, no se envía y se anota. Con 2.000 al día el peor caso son 0,80 $ al día en Bird. Un tope global total de 5.000 al día cubre todos los tipos.
- Los planes gratuitos tienen su propio tope diario (50 en Bird, 100 en Resend): sirven de red de seguridad en pruebas, pero conviene que el tope de la función sea menor para que una avalancha de un tipo no bloquee las alertas importantes. Por eso el tope de alertas es independiente.
- Además: un mismo destinatario no recibe más de un correo del mismo tipo por hora, y los correos de baja y de purga solo salen a direcciones ya registradas (propietario o dirección de la plataforma), nunca a un correo escrito en un formulario público.

## 5. Recomendación

1. **Alertas y avisos de baja: usar Bird, que ya está integrado** en `invitaciones` (clave, región y cabecera de baja verificadas en la documentación oficial). Con el plan gratuito el coste es 0 $ y no se añade un segundo proveedor ni una segunda integración, secreto y subencargado en los textos legales. Si el volumen llega a superar 1.000 al mes, pasar a Startup (15 $ de depósito, gasto real mucho menor).
2. **Resend solo si Gerencia prefiere su plan gratuito más amplio** (3.000 al mes y 3 dominios) y su dominio ya configurado [NV: no lo he podido comprobar]. Exigiría escribir y probar una segunda integración, y añadir un proveedor a la lista de subencargados.
3. En cualquiera de los dos, **antes de producción**: dominio de envío verificado con SPF, DKIM y DMARC, y decidir la región (la clave de Bird indica su región `eu1` [H]; en Resend no he leído sus regiones [NV]).
4. **Nada de esto se enciende sin aprobación**: el envío quedaría detrás de una variable apagada por defecto y del contador de topes.

## 6. Decisiones aprobadas por Gerencia (11 de noviembre de 2026)

Proveedor: **Bird**. Topes: alerta de purga 1 al día; aviso de baja 2 por iglesia y día; doble confirmación 200 por iglesia y día y 2.000 en la plataforma; global 5.000 al día en un plan de pago y **40 al día mientras se use el plan gratuito de 50**, para que el servicio falle de forma limpia. La doble confirmación del check-in sigue **apagada** y solo se enciende con orden escrita de Gerencia. Los envíos solo salen a direcciones ya registradas. SPF, DKIM y DMARC del dominio quedan en pendientes de producción.

## 7. Implementación (apagada en todos los entornos)

- `supabase/migrations/20261111280000_adn_envios_topes.sql` (reversión escrita antes): tabla `adn_envios_dia` (día, tipo, iglesia, número; solo cuentas) y `adn_envio_reservar` / `adn_envio_liberar`. La reserva es atómica, comprueba primero el tope global, después el del tipo y después el de la iglesia, y solo suma si todos pasan.
- `supabase/functions/*/envio.ts` (idéntico en `plataforma` y `datos-iglesia`): apagado salvo `ADN_ENVIO_ACTIVO=si`; solo a una dirección registrada (el correo del perfil de quien pide o cancela la baja; `ADN_EMAIL_ALERTAS` para la alerta); reserva el cupo antes de enviar y lo devuelve si Bird no acepta el correo; sin contador no envía; nunca lanza: un fallo se devuelve como resultado y **no rompe la baja**. La variable `ADN_ENVIO_TOPE_GLOBAL` solo puede bajar el tope.
- Correos: aviso de baja pedida o cancelada al propietario, en cuatro idiomas, sin enlaces ni secretos; alerta de purga con solo cifras. La respuesta de la baja lleva el campo `aviso` (`enviado`, `apagado`, `tope`, `destino_no_valido`, `sin_clave` o `fallo`).
- La alerta de purga la lanza la acción `avisar_purga` de `plataforma` desde una tarea diaria (`docs/PURGA.md`).
- Pruebas: `supabase/tests/adn_envios_topes.sql` (29 comprobaciones, 6 mutaciones detectadas) y `npm run test:envio` (apagado, dirección no registrada o mal formada, tope por iglesia, por tipo y global, 40 al día en el plan gratuito, proveedor caído o en error sin romper nada, base caída sin envío; 12 mutaciones detectadas). [NV] No se ha enviado ningún correo real ni se ha probado contra Bird.

## 8. Qué queda pendiente

- Encender el envío en un entorno (`ADN_ENVIO_ACTIVO=si`) con una clave de pruebas de Bird: solo con orden de Gerencia.
- Elegir el buzón de `ADN_EMAIL_ALERTAS`.
- SPF, DKIM y DMARC del dominio de envío: pendientes de producción.
- Cuándo se hace el análisis de la Comunicación masiva, con su propio coste y su propio tope.
