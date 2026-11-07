# Modelo de cobro de ViveADN

Estado: diseño aprobado por la gerencia el 7 de noviembre de 2026; nada de esto está aplicado en producción y todo se construye en modo de prueba, sin claves reales. Lo marcado [H, abogado] necesita revisión humana antes de salir de prueba. Este documento es la referencia del cobro; si algo cambia, se cambia aquí en el mismo PR.

## 1. Principio

Visualiza cobra solo su software, por suscripción o mantenimiento. El dinero de terceros nunca pasa por Visualiza ni por su libro. ViveADN debe poder vender, cobrar, emitir recibos y exportar sus libros sin depender de Visualiza Finance ni de ningún negocio vecino: Finance es la gerencia, publica políticas y consolida, y nunca es camino obligatorio del cobro. Primero se cobra, después se emite el evento.

## 2. Dos flujos separados

| Flujo | Quién paga | A quién | Pasarela y credenciales | Dónde se registra |
| --- | --- | --- | --- | --- |
| 1. Plan de ViveADN | La iglesia | Visualiza | Las de la entidad: Stripe y PayPal | En ViveADN y, después, en Finance |
| 2. Dinero de la iglesia (ofrendas, cuotas, pagos de miembros) | Miembros y visitantes | La iglesia | Las de la propia iglesia, conectadas desde su panel | Solo en el sistema de la iglesia |

Las seis cuentas de pasarela de Finance son de Visualiza y sirven únicamente al flujo 1. No son un catálogo para las iglesias.

## 3. Lo que nunca se construye

Comisión descontada en origen, reparto (split), saldos, monederos, retiros ni custodia. Una prueba automática rechaza `application_fee`, transferencias y cualquier campo de comisión en los adaptadores.

## 4. Pasarelas de la iglesia

- Stripe y PayPal vienen activas por defecto. El cliente puede elegir otras del listado.
- Si falta una, el cliente la pide y Visualiza la habilita por código con un adaptador nuevo; después el cliente introduce sus credenciales en privado.
- El modo de prueba o vivo de cada pasarela es el de la cuenta del cliente.
- El pago ocurre siempre en la página alojada de la pasarela (redirección). Ningún dato de tarjeta toca nuestros servidores.
- Se prefieren claves restringidas de Stripe y credenciales de aplicación REST de PayPal, pegadas por el cliente, antes que claves maestras. OAuth de Connect solo si se verifica que es imprescindible, y antes se avisa a la gerencia porque exigiría registrar a Visualiza como plataforma.

## 5. Credenciales del cliente

Cifrado de sobre, por inquilino:

1. Cada iglesia tiene su propia clave de datos, generada al conectar la primera pasarela.
2. La clave de datos se guarda cifrada con una clave maestra que vive solo en los secretos de la función de pagos, nunca en la base ni en el repositorio.
3. Cada credencial se cifra con la clave de datos de su iglesia (AES-GCM, con su propio vector de inicialización) y la base guarda solo el texto cifrado, la versión de la clave y los últimos caracteres.
4. Solo la función de pagos descifra, en memoria, para una llamada concreta. El navegador nunca recibe una credencial: la pantalla muestra los últimos caracteres y permite reemplazar o borrar.
5. Nada de esto aparece en registros, auditoría ni exportaciones. La columna se nombra de modo que la exportación de la iglesia la excluya, y una prueba lo comprueba.
6. Rotación de la clave maestra documentada: se envuelven de nuevo las claves de datos con la clave nueva sin tocar las credenciales. Rotación de la credencial del cliente a petición suya.
7. Al cancelar la iglesia se revocan y borran sus credenciales y su clave de datos; el borrado de la iglesia debe hacerlo también.
8. Cada cliente tiene su webhook propio con su secreto de firma. Se verifica la firma, se rechazan repeticiones y se procesa de forma idempotente.
9. Una fuga de credenciales es un incidente de nivel 3.

## 6. Cobro del plan (flujo 1) sin depender de Finance

- Catálogo de precios en la base: planes fijos por tramos (recomendación de la gerencia, pendiente de Harold) y módulos como complementos. Los tres precios son una propuesta marcada hasta que Harold los fije.
- La iglesia paga con Stripe o PayPal de la entidad. ViveADN guarda la suscripción, el cobro y un recibo numerado sin saltos.
- Cada cobro escribe un evento en una cola de salida (`eventos_salida`) en la misma transacción. Un proceso aparte lo entrega a Finance con reintentos y se reconcilia al reconectar. Si Finance está apagado, el cobro no se detiene.
- ViveADN no comparte tablas ni funciones con otros negocios.
- Los términos dicen que Visualiza es proveedor de software y que reembolsos y disputas se gestionan en la pasarela del cliente [H, abogado].

## 7. Modelo de datos (propuesta)

| Tabla | Para qué | Notas |
| --- | --- | --- |
| `precios_plan`, `precios_modulo` | Precio por plan y por complemento, moneda y periodo | Global, solo lectura para clientes |
| `suscripciones` | Plan contratado, estado, fin del periodo, pasarela | Lleva `iglesia_id` |
| `cobros_plataforma` | Cada pago del plan, con referencia externa única | Lleva `iglesia_id`; idempotente |
| `recibos` | Recibo numerado por serie, sin saltos, uno por cobro | Contador con cerrojo |
| `eventos_salida` | Cola hacia Finance | Solo servidor |
| `pasarelas_catalogo` | Pasarelas disponibles y si vienen activas | Global |
| `iglesia_pasarelas` | Pasarela de cada iglesia: estado, modo, últimos caracteres, credencial cifrada, webhook | Lleva `iglesia_id`; la credencial no sale al navegador |

## 8. Prueba de separación

Criterio de terminado: con Finance y los vecinos apagados siete días, ViveADN puede vender, cobrar, emitir recibos y exportar sus libros, y se reconcilia al reconectar.

| Capacidad | Hoy | Falta |
| --- | --- | --- |
| Vender (precios, cotización, contratar) | No | Precios en el catálogo, cotizador, asistente de alta antes del plan |
| Cobrar el plan | No | Suscripción y cobro con Stripe y PayPal en modo de prueba |
| Emitir recibos | No | Recibos numerados sin saltos |
| Exportar los libros | Parcial: se exportan los datos de cada iglesia | Exportar cobros y recibos |
| No depender de vecinos | Sí, no hay integraciones | Mantenerlo: cola de salida con reintentos |
| Reconciliar al reconectar | No | Entrega de la cola y comprobación contra Finance |

## 9. Orden de construcción

1. Credenciales como módulo del catálogo (PR #31, listo, esperando su migración).
2. Este documento.
3. Precios en el catálogo, candado en los módulos bloqueados y calculadora que solo estima.
4. Asistente de alta antes de elegir plan.
5. Suscripción, cobro y recibos del plan en modo de prueba, con la cola de salida.
6. Panel de pasarelas de la iglesia con credenciales cifradas.
7. Paquete legal y informe de separación.

## 10. Pendiente

- Harold: precios, moneda base, si los impuestos van incluidos, y cómo gana más Visualiza cuando el cliente vende más.
- Verificar en la documentación oficial que las claves restringidas de Stripe y las credenciales REST de PayPal cubren el caso.
- Revisión de un abogado humano de términos, privacidad, reembolsos e impuestos [H, abogado].
