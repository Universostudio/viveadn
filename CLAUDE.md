# ViveADN: reglas para quien trabaje en este repositorio

## Contexto

ViveADN es una línea de negocio de Visualiza Studio: gestión de iglesias con CRM, miembros, asistencia, QR propio, formación y certificados. Cada línea de Visualiza es soberana: cobra, factura y guarda sus datos sin depender de otra. Finance es la gerencia contable y es intercambiable; ninguna base lee a otra y la integración es por eventos firmados, opcional y con degradación. Las ofrendas y cuotas de una iglesia van a la pasarela de la propia iglesia.

## Gobierno

- Cada línea se habla en la sesión de gerencia. Esta sesión escribe solo en los repositorios de ViveADN.
- Finance supervisa los repositorios y vigila que nada contrario a esta política entre en ejecución. Sus avisos se corrigen antes de desplegar.

## Política de cobro (obligatoria)

Visualiza solo cobra su software. El dinero de terceros nunca pasa por Visualiza: sin comisión en origen, split, saldos, monederos, retiros ni custodia. El cliente conecta sus propias credenciales de pasarela; Stripe y PayPal vienen por defecto y otras se habilitan por código bajo solicitud. El diseño completo está en [`docs/COBRO.md`](docs/COBRO.md).

## Planes y precios

Cada negocio define sus planes y precios evaluando costos de proveedores, conexiones, plugins y código, inversión y riesgo, con márgenes sanos y competitivos. Condiciones: respetar la política de cobro, documentar los supuestos de costo y margen en `docs/PLANES.md` y que un contador valide toda cifra fiscal. Mientras no esté validado, los precios son una propuesta marcada.

## Siempre

- Modo de prueba hasta el interruptor de Harold.
- Nada en producción sin su orden directa y con una reversión probada en una base temporal. Esto incluye aplicar migraciones, desplegar funciones y fusionar a `main`, que despliega la web.
- Sin secretos ni datos personales en el repositorio. Los datos de demostración son ficticios.

## Cómo se trabaja

- Migraciones en `supabase/migrations`, con su reversión en `supabase/reversiones`. Toda tabla de iglesia lleva `iglesia_id`, y ninguna función `SECURITY DEFINER` vive en `public`.
- Pruebas de la base: `supabase/tests/ejecutar.sh` sobre una base temporal, nunca contra producción.
- Pruebas de la web: `npm run type-check`, `npm run check:idiomas`, `npm run build-only` y los `npm run test:*`. Idiomas: es, en, fr y pt-BR.
- La referencia técnica del modelo multi-iglesia está en [`docs/MULTITENANT.md`](docs/MULTITENANT.md).
