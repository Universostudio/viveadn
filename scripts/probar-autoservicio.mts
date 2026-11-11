// Pruebas de las piezas puras del autoservicio del propietario. Uso: npm run test:autoservicio
import assert from 'node:assert/strict'
const { errorDeAutoservicio, validarPagina, validarBaja } = await import('../supabase/functions/datos-iglesia/autoservicio.ts')

// Errores de la base
for (const [m, estado] of [['ADN_NO_PROPIETARIO', 403], ['ADN_LIMITE_DESCARGAS', 429], ['ADN_YA_BORRADA', 409], ['ADN_NO_BORRADA', 409],
  ['ADN_BAJA_DE_PLATAFORMA', 403], ['ADN_PLAZO_VENCIDO', 409], ['algo inesperado', 500], [undefined, 500]] as const) {
  assert.equal(errorDeAutoservicio(m).estado, estado, `estado de ${String(m)}`)
}
assert.match(errorDeAutoservicio('ADN_LIMITE_DESCARGAS').mensaje, /6 descargas/)
assert.match(errorDeAutoservicio('ADN_PLAZO_VENCIDO').mensaje, /30 días/)
assert.doesNotMatch(errorDeAutoservicio('error: relation public.perfiles violates').mensaje, /perfiles|relation/, 'un error interno no filtra detalles')

// Página
const ok = validarPagina({ tabla: 'miembros', formato: 'json' })
assert.ok(ok.ok && ok.pagina.limite === 1000 && ok.pagina.despues === null, 'valores por defecto')
assert.equal((validarPagina({ tabla: 'miembros', formato: 'csv', limite: 99999 }) as { pagina: { limite: number } }).pagina.limite, 5000, 'el límite se recorta a 5000')
assert.equal((validarPagina({ tabla: 'miembros', formato: 'csv', limite: 0 }) as { pagina: { limite: number } }).pagina.limite, 1, 'y a 1 por abajo')
assert.equal((validarPagina({ tabla: 'miembros', formato: 'csv', limite: 2.5 }) as { pagina: { limite: number } }).pagina.limite, 1000, 'un límite no entero vuelve al defecto')
assert.deepEqual((validarPagina({ tabla: 'a_b1', formato: 'json', despues: ['x', 'y'] }) as { pagina: { despues: string[] } }).pagina.despues, ['x', 'y'], 'cursor compuesto')
for (const tabla of [undefined, '', 'Miembros', '1abc', 'a-b', 'a b', 'a;drop', 'x'.repeat(64), 'public.miembros', 5]) {
  assert.equal(validarPagina({ tabla, formato: 'json' }).ok, false, `tabla no válida ${String(tabla)}`)
}
for (const formato of [undefined, 'xml', 'JSON', '']) assert.equal(validarPagina({ tabla: 'miembros', formato }).ok, false, `formato no válido ${String(formato)}`)
for (const despues of ['x', [], [1], ['a'.repeat(201)], Array(9).fill('a'), {}, [null]]) {
  assert.equal(validarPagina({ tabla: 'miembros', formato: 'json', despues }).ok, false, `cursor no válido ${JSON.stringify(despues)?.slice(0, 20)}`)
}
assert.equal(validarPagina({ tabla: 'miembros', formato: 'json', despues: Array(8).fill('a'.repeat(200)) }).ok, true, 'el máximo permitido pasa')

// Baja: hay que escribir la dirección exacta
assert.equal(validarBaja({ confirmar: 'mi-iglesia' }, 'mi-iglesia').ok, true)
assert.equal(validarBaja({ confirmar: '  mi-iglesia ' }, 'mi-iglesia').ok, true, 'los espacios de los extremos no cuentan')
for (const confirmar of [undefined, '', 'Mi-Iglesia', 'mi-iglesia2', 'otra', 5, null]) {
  assert.equal(validarBaja({ confirmar }, 'mi-iglesia').ok, false, `confirmación no válida ${String(confirmar)}`)
}
const conMotivo = validarBaja({ confirmar: 'x', motivo: ' ' + 'm'.repeat(600) }, 'x') as { ok: true; motivo: string }
assert.equal(conMotivo.motivo.length, 500, 'el motivo se recorta a 500')
assert.equal((validarBaja({ confirmar: 'x', motivo: '   ' }, 'x') as { motivo: unknown }).motivo, null, 'un motivo en blanco es nulo')
assert.equal((validarBaja({ confirmar: 'x' }, 'x') as { motivo: unknown }).motivo, null, 'sin motivo es nulo')
console.log('Autoservicio: todas las pruebas pasan')
