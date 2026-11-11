// Pruebas del estado de error de la aplicación. Uso: npm run test:error
import assert from 'node:assert/strict'
const { errorApp, marcarError, esErrorDeCarga } = await import('../src/lib/errorApp.ts')

for (const m of [
  'Failed to fetch dynamically imported module: https://x.test/assets/Vista-abc123.js',   // Chrome y Edge
  'error loading dynamically imported module: https://x.test/assets/Vista-abc123.js',     // Firefox
  'Importing a module script failed.',                                                     // Safari
  'Unable to preload CSS for /assets/index-1.css',
  'Loading chunk 12 failed.',
  'Loading CSS chunk vendor failed',
]) assert.equal(esErrorDeCarga(new Error(m)), true, m)
assert.equal(esErrorDeCarga('Failed to fetch dynamically imported module'), true, 'tambien como texto')
const tipoRaro = new TypeError('Failed to fetch dynamically imported module'); assert.equal(esErrorDeCarga(tipoRaro), true)
for (const e of [new Error('Cannot read properties of undefined'), new Error('NetworkError when attempting to fetch resource.'), new Error('Failed to fetch'), null, undefined, 42, {}, new Error('')])
  assert.equal(esErrorDeCarga(e), false, `no es un error de carga: ${String(e)}`)

assert.equal(errorApp.value, null, 'sin error al empezar')
marcarError('carga'); assert.equal(errorApp.value, 'carga')
marcarError('inesperado'); assert.equal(errorApp.value, 'carga', 'el primer error manda')
errorApp.value = null; marcarError('inicio'); assert.equal(errorApp.value, 'inicio')
console.log('OK: todas las pruebas del estado de error pasan')
