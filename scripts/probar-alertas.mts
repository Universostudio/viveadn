// Pruebas del color de alerta de OP72. Uso: npm run test:alertas
import assert from 'node:assert/strict'
const { alertaDe, haceHoras, conAlerta, plazoDe, metodoDe, METODO_OP72 } = await import('../src/lib/alertas.ts')

const ahora = Date.parse('2026-11-05T12:00:00Z')
const hace = (h: number) => new Date(ahora - h * 3_600_000).toISOString()
const casos: [number, string][] = [[0, 'verde'], [24, 'verde'], [24.01, 'amarillo'], [48, 'amarillo'], [48.01, 'naranja'], [72, 'naranja'], [72.01, 'rojo'], [500, 'rojo']]
for (const [h, esperado] of casos) assert.equal(alertaDe(hace(h), false, ahora), esperado, `${h} horas`)

// Un caso completado nunca alerta, por viejo que sea
assert.equal(alertaDe(hace(500), true, ahora), 'verde')
// Sin completar (null o undefined) cuenta como abierto
assert.equal(alertaDe(hace(100), null, ahora), 'rojo')
assert.equal(alertaDe(hace(100), undefined, ahora), 'rojo')

// El filtro por fecha coincide con el color: lo que esta por debajo de haceHoras(48) es naranja o rojo
assert.equal(haceHoras(48, ahora), hace(48))
for (const h of [10, 47, 49, 80]) {
  const dentro = new Date(hace(h)).getTime() < new Date(haceHoras(48, ahora)).getTime()
  assert.equal(dentro, ['naranja', 'rojo'].includes(alertaDe(hace(h), false, ahora)), `filtro y color coinciden a las ${h} horas`)
}

// Una fila con el color guardado envejecido se corrige al leerla
const vieja = conAlerta({ fecha_conversion: new Date(Date.now() - 100 * 3_600_000).toISOString(), completado: false, estado_alerta: 'verde' } as any)
assert.equal(vieja.estado_alerta, 'rojo')

// Con un método: los mismos bordes, con sus números (Seguimiento simple: 72, 120 y 168 horas)
const simple = { plazo_horas: 168, umbral_amarillo_horas: 72, umbral_naranja_horas: 120 }
const casosSimple: [number, string][] = [[0, 'verde'], [72, 'verde'], [72.01, 'amarillo'], [120, 'amarillo'], [120.01, 'naranja'], [168, 'naranja'], [168.01, 'rojo']]
for (const [h, esperado] of casosSimple) assert.equal(alertaDe(hace(h), false, ahora, simple), esperado, `simple ${h} horas`)
// Sin método (o con null) se comporta exactamente como OP72
for (const [h, esperado] of casos) assert.equal(alertaDe(hace(h), false, ahora, undefined), esperado, `sin método ${h} horas`)
assert.deepEqual(METODO_OP72, { plazo_horas: 72, umbral_amarillo_horas: 24, umbral_naranja_horas: 48 }, 'OP72 lleva los valores de siempre')
assert.equal(plazoDe({}), 72); assert.equal(plazoDe({ metodo: null }), 72); assert.equal(plazoDe({ metodo: simple }), 168)
assert.deepEqual(metodoDe({ metodo: null }), METODO_OP72)
// conAlerta usa el método de la fila
const hace100 = new Date(Date.now() - 100 * 3_600_000).toISOString()
assert.equal(conAlerta({ fecha_conversion: hace100, completado: false } as any).estado_alerta, 'rojo', 'sin método, 100 horas es rojo')
assert.equal(conAlerta({ fecha_conversion: hace100, completado: false, metodo: simple } as any).estado_alerta, 'amarillo', 'con Seguimiento simple, 100 horas es amarillo')
assert.equal(conAlerta({ fecha_conversion: hace100, completado: true, metodo: simple } as any).estado_alerta, 'verde', 'completado nunca alerta')
console.log('OK: todas las pruebas del color de alerta pasan')
