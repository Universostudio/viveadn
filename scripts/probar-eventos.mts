// Pruebas del cálculo de series semanales de eventos. Uso: npm run test:eventos
process.env.TZ = 'Europe/Madrid'
import assert from 'node:assert/strict'
const { fechasDeSerie, MAX_SERIE, TIPOS_EVENTO } = await import('../src/lib/eventos.ts')

// La serie cruza el cambio de horario del 25 de octubre de 2026 (a las 03:00 se retrasa una hora)
const inicio = new Date(2026, 9, 18, 20, 0)
const fin = new Date(2026, 9, 18, 22, 0)
const serie = fechasDeSerie(inicio, fin, 4)
assert.equal(serie.length, 4)
for (const s of serie) {
  assert.equal(s.inicio.getHours(), 20, 'la hora de inicio local no cambia')
  assert.equal(s.fin?.getHours(), 22, 'la hora de fin local no cambia')
}
assert.deepEqual(serie.map(s => s.inicio.getDate()), [18, 25, 1, 8])
assert.equal(serie[1]!.inicio.getTime() - serie[0]!.inicio.getTime(), 7 * 24 * 3600_000 + 3600_000, 'una semana sobre el cambio de horario dura 169 horas')

// Sin hora de fin, y sin modificar las fechas de entrada
const sinFin = fechasDeSerie(inicio, null, 2)
assert.equal(sinFin[1]!.fin, null)
assert.equal(inicio.getDate(), 18, 'no modifica la fecha original')

// Una sola reunión y el límite
assert.equal(fechasDeSerie(inicio, null, 1).length, 1)
assert.equal(fechasDeSerie(inicio, null, MAX_SERIE).length, 52)
assert.deepEqual([...TIPOS_EVENTO], ['culto', 'casa_oracion', 'formacion', 'especial', 'otro'])
console.log('OK: todas las pruebas de eventos pasan')
