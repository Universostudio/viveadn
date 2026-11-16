// Prueba de la normalización de la dirección web de una iglesia. Uso: npm run test:slug
import assert from 'node:assert/strict'
import { normalizarSlug, slugValido, SLUG_MAX } from '../src/lib/slug.ts'

assert.equal(normalizarSlug('casa-reino'), 'casa-reino')
assert.equal(normalizarSlug('Casa Reino'), 'casa-reino')
assert.equal(normalizarSlug('Calle Pegaso 9, Piso 1, derecha'), 'calle-pegaso-9-piso-1-derecha', 'una dirección postal escrita por error se convierte en algo usable y visible')
assert.equal(normalizarSlug('  Iglesia   Ñandú_Fe  '), 'iglesia-nandu-fe')
assert.equal(normalizarSlug('Él Señor — Ñ'), 'el-senor-n')
assert.equal(normalizarSlug('--a--b--'), 'a-b')
assert.equal(normalizarSlug('!!!'), '')
assert.equal(normalizarSlug(''), '')
assert.equal(normalizarSlug('a'.repeat(60)).length, SLUG_MAX)
const largo = normalizarSlug('abcdefghi-'.repeat(6))
assert.ok(largo.length <= SLUG_MAX && !largo.endsWith('-'), 'el corte no deja un guion final')
assert.equal(normalizarSlug('Ya-normalizado-123'), 'ya-normalizado-123')
for (const bueno of ['casa-reino', 'abc', 'a1-b2']) assert.equal(slugValido(bueno), true, bueno)
for (const malo of ['ab', 'Casa', 'casa--reino', '-casa', 'casa-', 'casa reino', 'a'.repeat(41)]) assert.equal(slugValido(malo), false, malo)
for (const t of ['Calle Pegaso 9, Piso 1, derecha', 'Iglesia Ñandú', 'x y z']) { const n = normalizarSlug(t); assert.ok(n === '' || slugValido(n) || n.length < 3, t) }
console.log('Slug: todo correcto')
