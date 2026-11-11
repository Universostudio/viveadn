// Pruebas de las piezas puras del ciclo de vida de la iglesia. Uso: npm run test:ciclo
import assert from 'node:assert/strict'
const { claveCronValida, tamanoLote, errorDeCiclo, PURGA_LOTE_MAX, PURGA_LOTE_DEFECTO, PLAZO_GRACIA_DIAS } =
  await import('../supabase/functions/plataforma/ciclo.ts')

assert.equal(PLAZO_GRACIA_DIAS, 30)

// Clave de la tarea programada
const clave = 'a'.repeat(32)
assert.equal(await claveCronValida(clave, clave), true, 'la clave correcta pasa')
assert.equal(await claveCronValida('b'.repeat(32), clave), false, 'otra clave no pasa')
assert.equal(await claveCronValida(clave + 'x', clave), false, 'una clave mas larga no pasa')
assert.equal(await claveCronValida(clave.slice(1), clave), false, 'una clave mas corta no pasa')
assert.equal(await claveCronValida('', clave), false, 'una clave vacia no pasa')
assert.equal(await claveCronValida(null, clave), false, 'sin cabecera no pasa')
assert.equal(await claveCronValida(clave, undefined), false, 'sin secreto configurado la via queda cerrada')
assert.equal(await claveCronValida('', ''), false, 'dos cadenas vacias no abren la via')
assert.equal(await claveCronValida('corta', 'corta'), false, 'un secreto corto se rechaza aunque coincida')

// Tamano del lote
for (const [pedido, esperado] of [[undefined, PURGA_LOTE_DEFECTO], [null, PURGA_LOTE_DEFECTO], ['x', PURGA_LOTE_DEFECTO], [0, PURGA_LOTE_DEFECTO], [-3, PURGA_LOTE_DEFECTO], [2.5, PURGA_LOTE_DEFECTO],
  [1, 1], [7, 7], ['7', 7], [PURGA_LOTE_MAX, PURGA_LOTE_MAX], [PURGA_LOTE_MAX + 1, PURGA_LOTE_MAX], [100000, PURGA_LOTE_MAX]] as const) {
  assert.equal(tamanoLote(pedido), esperado, `lote ${String(pedido)}`)
}

// Errores de la base
assert.deepEqual(errorDeCiclo('ADN_YA_BORRADA').estado, 409)
assert.deepEqual(errorDeCiclo('ADN_NO_BORRADA').estado, 409)
assert.match(errorDeCiclo('ADN_PLAZO_VENCIDO').mensaje, /30 dias/)
assert.equal(errorDeCiclo('BORRADO_NO_VENCIDO').estado, 409)
assert.equal(errorDeCiclo('La iglesia no existe').estado, 404)
assert.equal(errorDeCiclo('connection reset by peer').estado, 500)
assert.equal(errorDeCiclo(undefined).estado, 500)
assert.ok(!/connection|peer|sql/i.test(errorDeCiclo('connection reset by peer').mensaje), 'un error desconocido no filtra detalles internos')

console.log('Ciclo de vida: todas las pruebas pasan')
