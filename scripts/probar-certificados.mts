// Pruebas de la verificacion publica de certificados. Uso: npm run test:certificados
import assert from 'node:assert/strict'
const { CODIGO_RE, codigoDe, respuestaDe } = await import('../supabase/functions/verificar-certificado/validar.ts')

const ok = 'a'.repeat(32)
assert.equal(codigoDe({ codigo: ok }), ok)
assert.equal(codigoDe({ codigo: '0123456789abcdef0123456789abcdef' }), '0123456789abcdef0123456789abcdef')
// Cualquier otra cosa no es un codigo
for (const malo of ['', 'a'.repeat(31), 'a'.repeat(33), 'A'.repeat(32), 'g'.repeat(32), '../'.repeat(11), ok + '\n', ' ' + ok, ok.slice(0, 31) + "'"]) {
  assert.equal(codigoDe({ codigo: malo }), null, JSON.stringify(malo).slice(0, 30))
  assert.ok(!CODIGO_RE.test(malo))
}
for (const cuerpo of [null, undefined, 'texto', 42, [], [ok], {}, { codigo: 7 }, { codigo: null }, { codigo: [ok] }, { Codigo: ok }]) assert.equal(codigoDe(cuerpo), null, JSON.stringify(cuerpo))

// Respuesta: solo lo minimo, y un revocado nunca lleva al titular
const valido = { estado: 'valido', iglesia: 'Iglesia', programa: 'Bases', titular: 'Ana G.', emitido_en: '2026-11-05T10:00:00Z', miembro_id: 'secreto', codigo: ok, extra: 'x' }
assert.deepEqual(respuestaDe(valido), { status: 200, cuerpo: { estado: 'valido', iglesia: 'Iglesia', programa: 'Bases', emitido_en: '2026-11-05T10:00:00Z', titular: 'Ana G.' } })
const revocado = { estado: 'revocado', iglesia: 'Iglesia', programa: 'Bases', titular: 'Ana G.', emitido_en: '2026-11-05T10:00:00Z', revocado_en: '2026-11-06T10:00:00Z' }
const r = respuestaDe(revocado)
assert.equal(r.status, 200); assert.equal(r.cuerpo.estado, 'revocado'); assert.ok(!('titular' in r.cuerpo), 'un revocado no muestra al titular'); assert.ok(!('revocado_en' in r.cuerpo))
for (const nada of [null, undefined, 'x', 7, {}, { estado: 'otro' }, { estado: 'valido' }.estado]) assert.equal(respuestaDe(nada).status, 404, JSON.stringify(nada))
console.log('OK: todas las pruebas de la verificacion de certificados pasan')
