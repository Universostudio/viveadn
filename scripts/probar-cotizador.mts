// Pruebas del cotizador de planes. Uso: npm run test:cotizador
import assert from 'node:assert/strict'
const { cotizar, compararPlanes, recomendado, modulosContratables, formatoImporte, preciosDeMoneda, monedaDePais } = await import('../src/lib/cotizador.ts')

const m = (clave: string, tipo: string, orden: number) => ({ clave, nombre: clave, descripcion: null, tipo, orden })
const cat = {
  planes: [
    { clave: 'semilla', nombre: 'Semilla', max_miembros: 50, max_usuarios: 3, orden: 1 },
    { clave: 'basico', nombre: 'Basico', max_miembros: 300, max_usuarios: 10, orden: 2 },
    { clave: 'premium', nombre: 'Premium', max_miembros: 5000, max_usuarios: null, orden: 3 },
  ],
  modulos: [m('miembros', 'nucleo', 10), m('formacion', 'incluido', 110), m('reportes', 'incluido', 120), m('gamificacion', 'incluido', 140),
    m('biblioteca', 'incluido', 150), m('whatsapp', 'incluido', 160), m('credenciales', 'especial', 220), m('app_marca', 'especial', 230), m('nuevo_sin_precio', 'especial', 240)],
  planModulos: {
    semilla: ['miembros'],
    basico: ['miembros', 'formacion', 'reportes'],
    premium: ['miembros', 'formacion', 'reportes', 'gamificacion', 'biblioteca', 'whatsapp', 'credenciales'],
  },
  precioPlan: { semilla: 900, basico: 2900, premium: 7900 },
  precioModulo: { formacion: 900, reportes: 900, gamificacion: 500, biblioteca: 500, whatsapp: 1900, credenciales: 900, app_marca: 2900 },
}

// Sin extras se paga solo el plan; los modulos de nucleo y los ya incluidos no suman
let c = cotizar(cat, 'basico', ['miembros', 'formacion'])
assert.equal(c.total, 2900); assert.deepEqual(c.extras, []); assert.equal(c.cabe, true)
// Un modulo fuera del plan suma su precio
c = cotizar(cat, 'basico', ['formacion', 'whatsapp'])
assert.equal(c.total, 4800); assert.deepEqual(c.extras, [{ modulo: 'whatsapp', importe: 1900 }])
// Elegir dos veces el mismo no lo cuenta dos veces
assert.equal(cotizar(cat, 'semilla', ['whatsapp', 'whatsapp']).total, 900 + 1900)
// Sin precio no se puede dar un total fiable
c = cotizar(cat, 'premium', ['nuevo_sin_precio'])
assert.deepEqual(c.sinPrecio, ['nuevo_sin_precio']); assert.equal(c.total, 7900)
// Un modulo que no existe se ignora
assert.equal(cotizar(cat, 'basico', ['inventado']).total, 2900)
// Los limites del plan
assert.equal(cotizar(cat, 'semilla', [], { personas: 51 }).cabe, false)
assert.equal(cotizar(cat, 'semilla', [], { personas: 50, usuarios: 3 }).cabe, true)
assert.equal(cotizar(cat, 'premium', [], { personas: 5000, usuarios: 9999 }).cabe, true)
assert.equal(cotizar(cat, 'inexistente', []).cabe, false)

// Basico con los cinco modulos que Premium ya incluye sale mas barato que Premium, como dice docs/PLANES.md
const cinco = ['credenciales', 'gamificacion', 'biblioteca', 'whatsapp']
assert.equal(cotizar(cat, 'basico', cinco).total, 2900 + 900 + 500 + 500 + 1900)   // 6700 con cuatro de los cinco; formacion y reportes ya vienen
assert.ok(cotizar(cat, 'basico', cinco).total < cotizar(cat, 'premium', cinco).total)

// Comparar y recomendar
let orden = compararPlanes(cat, ['whatsapp']).map(x => x.plan)
assert.deepEqual(orden, ['semilla', 'basico', 'premium'].sort((a, b) => cotizar(cat, a, ['whatsapp']).total - cotizar(cat, b, ['whatsapp']).total))
assert.equal(recomendado(cat, [])?.plan, 'semilla')
assert.equal(recomendado(cat, [], { personas: 200 })?.plan, 'basico')
// Con esta propuesta Premium no sale mas barato que Basico mas los complementos: solo compensa por el tamano
assert.equal(recomendado(cat, ['whatsapp', 'gamificacion', 'biblioteca', 'credenciales'], { personas: 200 })?.plan, 'basico')
assert.equal(recomendado(cat, ['whatsapp', 'gamificacion', 'biblioteca', 'credenciales'], { personas: 400 })?.plan, 'premium')
// Los que no cubren el tamano no se recomiendan aunque sean mas baratos
assert.equal(recomendado(cat, [], { personas: 1000 })?.plan, 'premium')
assert.equal(recomendado(cat, [], { personas: 6000 }), null)
// Un modulo sin precio impide recomendar un total falso
assert.equal(recomendado(cat, ['nuevo_sin_precio']), null)
// Los contratables son los que no son de nucleo, en orden
assert.deepEqual(modulosContratables(cat).map(x => x.clave), ['formacion', 'reportes', 'gamificacion', 'biblioteca', 'whatsapp', 'credenciales', 'app_marca', 'nuevo_sin_precio'])

// Formato: sin moneda, solo el numero; con moneda, dinero
assert.equal(formatoImporte(2900, null, 'es'), '29,00')
assert.equal(formatoImporte(2900, null, 'en'), '29.00')
assert.match(formatoImporte(2900, 'EUR', 'es'), /29,00\s?€/)
assert.match(formatoImporte(2900, 'USD', 'en'), /\$29\.00/)
console.log('OK: todas las pruebas del cotizador pasan')

// Listas por moneda: se toma la de la moneda pedida y, sin lista, no se inventa precio
const filas = [
  { plan: 'basico', moneda: 'USD', importe_centimos: 2900 }, { plan: 'basico', moneda: 'EUR', importe_centimos: 2700 },
  { plan: 'semilla', moneda: 'USD', importe_centimos: 900 },
]
assert.deepEqual(preciosDeMoneda(filas, 'plan', 'EUR'), { basico: 2700 })
assert.deepEqual(preciosDeMoneda(filas, 'plan', 'USD'), { basico: 2900, semilla: 900 })
assert.deepEqual(preciosDeMoneda(filas, 'plan', 'MXN'), {}, 'sin lista en esa moneda no hay precio inventado')
assert.equal(monedaDePais('es'), 'EUR'); assert.equal(monedaDePais(null), 'USD'); assert.equal(monedaDePais('MX'), 'USD')
console.log('OK: precios por moneda')
