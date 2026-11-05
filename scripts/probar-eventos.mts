// Pruebas del cálculo de series semanales de eventos. Uso: npm run test:eventos
process.env.TZ = 'Europe/Madrid'
import assert from 'node:assert/strict'
const { fechasDeSerie, MAX_SERIE, TIPOS_EVENTO, DURACION_POR_DEFECTO_MS } = await import('../src/lib/eventos.ts')
const { leerTodo } = await import('../src/lib/paginar.ts')

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
assert.equal(DURACION_POR_DEFECTO_MS, 3 * 3600_000)

// Lector paginado: recorre todas las páginas, no pierde filas y no da por bueno un resultado cortado
const falso = (total: number, falla?: number) => {
  const llamadas: [number, number][] = []
  const pedir = async (d: number, h: number) => {
    llamadas.push([d, h])
    if (falla !== undefined && llamadas.length === falla) return { data: null, error: new Error('red') }
    return { data: Array.from({ length: Math.max(0, Math.min(h + 1, total) - d) }, (_, i) => d + i), error: null }
  }
  return { pedir, llamadas }
}
let f = falso(2500)
const todas = await leerTodo(f.pedir)
assert.equal(todas?.length, 2500)
assert.deepEqual(f.llamadas, [[0, 999], [1000, 1999], [2000, 2999]])
assert.deepEqual(todas?.slice(998, 1002), [998, 999, 1000, 1001], 'sin huecos ni repetidos entre páginas')
f = falso(2000)
assert.equal((await leerTodo(f.pedir))?.length, 2000, 'un múltiplo exacto del tamaño de página no pierde ni duplica filas')
assert.equal(f.llamadas.length, 3)
assert.equal((await leerTodo(falso(0).pedir))?.length, 0)
assert.equal(await leerTodo(falso(2500, 2).pedir), null, 'si una página falla, devuelve null y no datos parciales')
console.log('OK: todas las pruebas de eventos pasan')
