# Planes, precios y supuestos de costo de ViveADN

Estado: **propuesta para discusión**, redactada el 16 de noviembre de 2026. Ningún precio está fijado ni validado. Toda cifra fiscal necesita la validación de un contador [contador] y los términos comerciales la de un abogado humano [H, abogado]. Los precios y la lógica de este documento se usan en modo de prueba; nada está en producción. Reglas que se respetan: la política de cobro de [`docs/COBRO.md`](COBRO.md) y que Visualiza solo cobra su software.

## 1. Cómo se cobra

- Cada iglesia, o cada sede, es un cliente con su propio plan. La iglesia madre solo recibe cifras agregadas de sus sedes, de modo que cada sede paga su plan. Un descuento por red queda pendiente de decisión.
- El plan fija los límites (personas y usuarios) y los módulos incluidos. Los módulos que no vienen en el plan se contratan como complementos, cada uno con su precio mensual.
- Los miembros no se cobran por persona: los limita el plan, y más de 5.000 personas es un plan a medida.
- El cliente paga a Visualiza con las pasarelas de la entidad. Lo que la iglesia cobra a sus miembros va directo a su cuenta y no entra en estos números.

## 2. Costos de proveedor verificados

Fuente: páginas de precios de cada proveedor, consultadas el 16 de noviembre de 2026. Vuelven a verificarse antes de fijar precios.

| Concepto | Costo | Qué incluye o cómo se cobra |
| --- | --- | --- |
| Supabase, plan Pro | 25 USD al mes | 8 GB de base de datos, 100 GB de archivos, 250 GB de salida de datos, 100.000 usuarios activos, 2 millones de invocaciones de funciones y 10 USD de crédito de cómputo |
| Supabase, excesos | 0,125 USD por GB de base; 0,0213 USD por GB de archivos; 0,09 USD por GB de salida; 0,00325 USD por usuario activo | Solo si se superan los incluidos |
| Vercel, plan Pro | 20 USD al mes por asiento de desarrollador | 100 GB de transferencia y 1 millón de invocaciones; los excesos empiezan en 0,06 USD por GB y 0,60 USD por millón de invocaciones |
| Stripe España, tarjetas europeas estándar | 1,5 % más 0,25 EUR por cobro | Las premium del EEE, 2,8 % más 0,25 EUR; las internacionales, 3,15 % más 0,25 EUR; un 2 % más si hay conversión de divisa |
| Stripe México | 3,6 % más 3,00 MXN por cobro | Un 0,5 % más en tarjetas internacionales y un 2 % más si hay conversión de divisa |
| Stripe Billing (suscripciones) | 0,7 % del volumen | Pago por uso, sin contrato |
| PayPal, correo transaccional, WhatsApp, dominio | **Sin verificar** | Pendiente antes de fijar el precio de los módulos que dependen de ellos |

Costo fijo de infraestructura con un asiento de Vercel: unos **45 USD al mes** (25 de Supabase y 20 de Vercel). Se supone que el proyecto está en el plan Pro de Supabase; si no es así, hay que corregirlo.

Costo variable por iglesia: bajo. Los usuarios del sistema son el equipo de la iglesia (3 a 10 en los planes pequeños), muy por debajo de los 100.000 incluidos, y los datos de una iglesia pequeña ocupan poco frente a los 8 GB.

## 3. Comisión por cobrar el plan

Es un costo de Visualiza, no del cliente. Para un cobro de 29 EUR con tarjeta europea estándar: 1,5 % son 0,435 EUR, más 0,25 EUR fijos, más 0,7 % de Billing (0,203 EUR). Total 0,888 EUR, es decir un 3,1 % del cobro. En México la misma cuenta ronda el 4,3 % más 3 MXN fijos. Una tarjeta internacional o una conversión de divisa lo encarecen.

## 4. Propuesta de precios

Importes mensuales en la moneda base, que Harold aún no fijó (la propuesta usa unidades neutras, a convertir). Sin impuestos [contador].

| Plan | Propuesta | Personas | Usuarios | Módulos |
| --- | --- | --- | --- | --- |
| Semilla | 9 | 50 | 3 | Núcleo |
| Básico | 29 | 300 | 10 | Núcleo, formación, reportes y comunicación por correo |
| Premium | 79 | 5.000 | Sin límite | Todo lo disponible |

| Complemento | Propuesta | Costo de servirlo que hay que verificar |
| --- | --- | --- |
| Credenciales con foto y QR | 9 | Casi nulo; el QR se dibuja en el navegador |
| Consolidación por etapas | 9 | Casi nulo |
| Biblioteca de recursos | 5 | Almacenamiento de archivos |
| Gamificación | 5 | Casi nulo |
| WhatsApp Business | 19 | Mensajes del proveedor y credenciales del cliente; sin verificar |
| App con marca propia | 29 | Publicación y mantenimiento de la app; sin verificar |

El cotizador compara los planes para los módulos que el cliente elige y recomienda el más barato. Con estos números, Básico con todos los complementos sale en 76, por debajo de Premium (79), pero Premium además sube el límite a 5.000 personas.

## 5. Margen

Con el costo fijo de unos 45 al mes y un cobro de 29 con una comisión de alrededor del 3 % a 4,3 %, cada iglesia Básico deja cerca de 27,7 después de comisiones. **Dos iglesias Básico cubren la infraestructura.** Esto es el margen sobre infraestructura y comisiones y nada más.

No incluye: desarrollo, soporte, tiempo de gestión, legal, contador, marketing, impuestos ni los costos sin verificar de la sección 2. El margen real depende de ellos y no se puede afirmar hasta estimarlos.

Fórmula para fijar un precio: el precio mínimo es (costo variable por cliente más comisión) dividido entre (1 menos el margen objetivo), y se verifica que el cliente más pequeño no pierda dinero.

## 6. Pendientes

- **Harold:** moneda base, si los impuestos van incluidos, si Semilla es de pago o gratuito, y el descuento por red de sedes.
- **Verificar:** costos de PayPal, correo transaccional, WhatsApp, dominio y de la app con marca propia.
- **Mercado:** comparar con otros sistemas de gestión de iglesias. No se verificó ningún precio de la competencia y no se afirma nada de ella.
- **Contador:** impuestos por país, facturación electrónica y cualquier cifra fiscal [contador].
- **Abogado humano:** términos comerciales, reembolsos y disputas [H, abogado].
