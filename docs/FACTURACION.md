# Facturación en modo de prueba

Estado: lo que existe hoy es **una tabla de precios por plan y una simulación del ingreso mensual esperado**, con la etiqueta «Datos de prueba». No hay cobros, no hay pasarela conectada y no hay claves. Lo demás de este documento es el **diseño** de la conexión con Stripe en modo de prueba, para aprobarlo antes de construirla. Complementa `docs/COBRO.md` (modelo de cobro aprobado el 7 de noviembre); si algo choca, manda `COBRO.md`.

## 1. Lo que ya existe [E]

- **Precios.** `planes` gana tres columnas opcionales: `precio_mensual_centimos`, `precio_anual_centimos` y `moneda` (migración `20261111360000_adn_precios_plan`, con reversión). Nacen **vacías**: ningún plan trae un precio inventado. Los valores los fija quien opera la plataforma desde «Facturación» (acción `plan_precio_fijar`, queda en la auditoría) cuando estén validados. Reglas de la base: importes enteros en céntimos, no negativos, moneda de tres letras, y no hay precio sin moneda. Las iglesias pueden leer los precios (son del catálogo) pero no cambiarlos.
- **Simulación** (`facturacion_simulacion`, módulo puro `supabase/functions/plataforma/facturacion.ts`). Cuenta, por plan, las iglesias en estado **activa**, sin demostraciones y sin borrar, y multiplica por el precio mensual. Quedan fuera, cada una con su motivo visible: demostraciones, altas sin terminar, en prueba, en receso, suspendidas y dadas de baja.
- **Ceros honestos.** Un cero solo sale con su causa («ninguna iglesia en este plan»). Si hay iglesias que pagan un plan sin precio, ese plan dice «No calculable: falta el precio» (no se pone cero) y el total se marca como parcial. Monedas distintas no se suman entre sí. Iglesias con un plan que ya no está en el catálogo se cuentan aparte.
- **Límites de la simulación.** Supone cobro mensual (aún no se guarda si una iglesia paga al año), no aplica impuestos ni descuentos y no sabe quién ha pagado de verdad: es una estimación, no contabilidad. El indicador «Facturación recurrente mensual» de la portada sigue **sin conectar** a propósito, porque solo debe mostrar cobros reales.

## 2. Diseño de la conexión con Stripe en modo de prueba [H, para aprobar]

Principios de `COBRO.md` que se mantienen: Visualiza cobra solo su software; el pago ocurre en la página alojada de Stripe (ningún dato de tarjeta toca nuestros servidores); sin comisión en origen, reparto ni custodia; primero se cobra, después se emite el evento.

### 2.1 Qué se guarda

Solo identificadores y estados, nunca tarjetas.

| Dato | Dónde | Notas |
| --- | --- | --- |
| Cliente de Stripe de cada iglesia (`cus_...`) | `suscripciones` | Una iglesia, un cliente. Lleva `iglesia_id` |
| Suscripción de Stripe (`sub_...`), precio (`price_...`), estado, fin del periodo, si se cancela al final | `suscripciones` | El estado se copia tal cual de Stripe y se traduce a etapa (2.3) |
| Cada pago: id de factura, importe, moneda, fecha, resultado | `cobros_plataforma` | Referencia externa única: repetir un evento no duplica |
| Eventos de webhook ya procesados (`evt_...`) | `stripe_eventos` | Clave primaria = id del evento; es el cerrojo de idempotencia |
| Recibo numerado sin saltos | `recibos` | Según `COBRO.md`; fuera de este primer paso |

Las tablas con `iglesia_id` siguen las reglas de siempre (seguridad por filas, exportación de la iglesia sin secretos). `stripe_eventos` es global y solo la lee el servidor. Los productos y precios de Stripe se crean **por script** desde la tabla `planes` (un producto por plan, un precio mensual y otro anual), no a mano, y su id se anota para no duplicar.

### 2.2 Flujo

1. El propietario de la iglesia pulsa «Contratar» en su panel. Una función de borde crea o reutiliza su cliente y una sesión de **Stripe Checkout** (página alojada) para el precio del plan elegido, con `client_reference_id` = id de la iglesia y la prueba gratuita que corresponda.
2. Stripe devuelve a la iglesia a Vive ADN. **Esa vuelta no confirma nada**: la confirmación llega solo por webhook.
3. Para cambiar tarjeta, plan o cancelar se usa el **portal de cliente** de Stripe, abierto desde otra función de borde.
4. Cada cambio de estado escribe una fila en la auditoría de la plataforma y, cuando haya cola de salida, un evento (`COBRO.md`, apartado 6).

### 2.3 Webhooks y estados

Una función pública (`stripe-webhook`) que **verifica la firma** con el secreto del endpoint, rechaza marcas de tiempo viejas y procesa cada `evt_...` una sola vez (insertar en `stripe_eventos`; si ya está, responde 200 y no hace nada). Eventos que se escuchan: `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid` e `invoice.payment_failed`. Cualquier otro se registra y se ignora.

| Estado de la suscripción en Stripe | Etapa de la iglesia en Vive ADN |
| --- | --- |
| `trialing` | `prueba` |
| `active` | `activa` |
| `past_due` (cobro fallido, Stripe reintenta) | sigue `activa`, con aviso (2.4) |
| `unpaid` o `canceled` | `receso` o `suspendida` según la política de `docs/CICLO-DE-VIDA.md` |
| `incomplete`, `incomplete_expired` | no cambia la etapa: el alta de pago no llegó a completarse |
| `paused` | `receso` |

La etapa solo la cambia el procesador de webhooks, nunca la pantalla. Un evento fuera de orden no puede retroceder el estado: se compara con la fecha del evento y con el estado actual consultado a Stripe cuando haya duda.

### 2.4 Impago

1. Stripe reintenta el cobro según su configuración; la iglesia sigue funcionando en `past_due`.
2. En cada fallo: aviso dentro de la aplicación al propietario (usa los avisos del soporte, apartado 3.3 de `PANEL-MAESTRO.md`) con un enlace al portal para cambiar la tarjeta. El correo solo si `ADN_ENVIO_ACTIVO` se enciende por orden escrita.
3. Si los reintentos se agotan, Stripe pasa a `unpaid` o `canceled` y la iglesia entra en el estado que fije la política de ciclo de vida, **con el mismo plazo de gracia y copia de datos antes de cualquier baja**. Un impago no borra datos: la purga solo corre por el camino de baja ya existente (`docs/PURGA.md`).
4. Un pago posterior reactiva la iglesia por el mismo webhook, sin intervención.

### 2.5 Secretos y entorno

Solo en los secretos de la función de borde (`STRIPE_SECRET_KEY` de **modo de prueba**, claves restringidas con los mínimos permisos, y `STRIPE_WEBHOOK_SECRET`), jamás en el repositorio, en variables de la web ni en la base. Para pruebas: tarjetas de prueba de Stripe, relojes de prueba para adelantar el ciclo y la CLI de Stripe para reenviar eventos a un entorno local. Producción no se toca hasta tener orden escrita, claves de producción en puerta B y revisión legal [H, abogado].

### 2.6 Qué prueba hay que escribir antes de encender nada

Firma inválida rechazada; el mismo evento dos veces no duplica cobro ni cambia dos veces la etapa; eventos fuera de orden; cada estado de la tabla 2.3 produce la etapa esperada; un impago no borra nada; ningún campo de tarjeta ni clave aparece en registros, auditoría ni exportación; y la prueba de `COBRO.md` que rechaza `application_fee`, transferencias y comisiones.

## 3. Decisiones que dependen de Harold («le diré»)

- **Precios** de los planes, **moneda base** y si los **impuestos** van incluidos (hoy los precios están vacíos).
- Si se ofrece **pago anual** y con qué descuento (la columna ya existe; la simulación todavía no la usa).
- **Coste de Stripe.** No tiene cuota fija por su uso básico, pero cobra una comisión por cada transacción; es un coste variable nuevo y, por la regla del proyecto, **no se activa nada sin un análisis previo aprobado** (tarifa exacta de la cuenta de la entidad, impuestos sobre la comisión y su efecto en el margen de cada plan) [NV: la tarifa concreta no está verificada aquí].
- Plazo de gracia ante impago y estado al que pasa la iglesia (enlaza con las decisiones comerciales de `docs/CICLO-DE-VIDA.md`).
- Revisión de términos, reembolsos e impuestos [H, abogado].

## 4. Orden de construcción propuesto

1. (hecho) Precios y simulación.
2. Tablas `suscripciones`, `cobros_plataforma` y `stripe_eventos` con reversión y pruebas.
3. Función `stripe-webhook` con firma e idempotencia, probada con eventos simulados, sin red.
4. Creación de productos y precios de Stripe por script, en una cuenta de pruebas.
5. Checkout y portal desde el panel de la iglesia.
6. Recibos numerados, exportación de cobros y cola de salida.

Cada paso con orden escrita de Gerencia, solo en pruebas, y sin cobros reales.
