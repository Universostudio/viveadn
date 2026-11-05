// Pruebas del color de alerta de OP72. Uso: npm run test:alertas
import assert from 'node:assert/strict'
const { alertaDe, haceHoras, conAlerta } = await import('../src/lib/alertas.ts')

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
console.log('OK: todas las pruebas del color de alerta pasan')
