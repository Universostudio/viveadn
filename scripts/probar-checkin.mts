// Pruebas de la validacion del registro por QR. Uso: npm run test:checkin
import assert from 'node:assert/strict'
const { validarRegistro, respuestaDe, TOKEN_RE } = await import('../supabase/functions/checkin-evento/validar.ts')

const bueno = { nombre: 'María José', apellido: 'García  López', telefono: '+34 600 111 222', email: 'MARIA@Ejemplo.com', consentimiento: true, mayor14: true, web: '' }
const r = validarRegistro(bueno)
assert.ok(r.ok)
assert.deepEqual(r.ok && r.datos, { nombre: 'María José', apellido: 'García López', telefono: '+34 600 111 222', email: 'maria@ejemplo.com' }, 'normaliza espacios y pasa el correo a minusculas')

// El correo es opcional
assert.ok(validarRegistro({ ...bueno, email: '' }).ok)
assert.ok(validarRegistro({ ...bueno, email: undefined }).ok)

// Robot: el campo trampa tiene algo
assert.deepEqual(validarRegistro({ ...bueno, web: 'http://spam' }), { ok: false, error: 'bot' })
assert.ok(validarRegistro({ ...bueno, web: '   ' }).ok, 'un espacio en blanco no es un robot')

// Consentimiento y mayoria de edad, estrictamente true
for (const c of [{ consentimiento: false }, { consentimiento: 'true' }, { consentimiento: undefined }, { mayor14: false }, { mayor14: 1 }]) {
  assert.deepEqual(validarRegistro({ ...bueno, ...c }), { ok: false, error: 'consentimiento' }, JSON.stringify(c))
}

// Datos invalidos
const malos: Record<string, unknown>[] = [
  { nombre: '' }, { nombre: '   ' }, { nombre: 'x'.repeat(101) }, { apellido: 'x'.repeat(101) },
  { nombre: 'Ana\u0000' }, { nombre: 'Ana‮' }, { nombre: 'A​na' }, { apellido: 'Lo\npez\u0007' },
  { telefono: '' }, { telefono: 'abc' }, { telefono: '12345' }, { telefono: '+34 6' }, { telefono: '1'.repeat(31) }, { telefono: '600 111 222; DROP' },
  { email: 'sin-arroba' }, { email: 'a@b' }, { email: `${'a'.repeat(250)}@x.es` },
  { nombre: 123 }, { nombre: null }, { telefono: ['600111222'] },
]
for (const m of malos) assert.deepEqual(validarRegistro({ ...bueno, ...m }), { ok: false, error: 'datos' }, JSON.stringify(m).slice(0, 60))

// El apellido es opcional aqui: en modo alias no existe, y si la iglesia lo exige lo rechaza la base de datos
const sinApellido = validarRegistro({ ...bueno, nombre: 'Roble-01', apellido: '' })
assert.ok(sinApellido.ok && sinApellido.datos.apellido === '' && sinApellido.datos.nombre === 'Roble-01')
assert.ok(validarRegistro({ ...bueno, apellido: undefined }).ok)

// Los saltos de linea dentro de un nombre se tratan como espacios, no como cortes de una linea nueva
const salto = validarRegistro({ ...bueno, nombre: 'Ana\n\tMaría' })
assert.ok(salto.ok && salto.datos.nombre === 'Ana María')

// Acentos: se guardan compuestos (NFC) aunque lleguen descompuestos
const nfd = validarRegistro({ ...bueno, nombre: 'José' })
assert.ok(nfd.ok && nfd.datos.nombre === 'José')

// Token
assert.ok(TOKEN_RE.test('a'.repeat(64)))
for (const t of ['', 'a'.repeat(63), 'a'.repeat(65), 'A'.repeat(64), 'g'.repeat(64), '../'.repeat(20), 'a'.repeat(64) + '\n']) assert.ok(!TOKEN_RE.test(t), JSON.stringify(t).slice(0, 30))

// Respuestas: nuevo y existente son indistinguibles
assert.deepEqual(respuestaDe('ok_nuevo'), respuestaDe('ok_existente'))
assert.deepEqual(respuestaDe('ok_nuevo'), { status: 200, cuerpo: { ok: true } })
assert.deepEqual(respuestaDe('cerrado'), { status: 409, cuerpo: { error: 'cerrado' } })
assert.deepEqual(respuestaDe('lleno'), { status: 409, cuerpo: { error: 'lleno' } })
assert.deepEqual(respuestaDe('limite'), { status: 429, cuerpo: { error: 'limite' } })
assert.deepEqual(respuestaDe('datos'), { status: 400, cuerpo: { error: 'datos' } })
assert.equal(respuestaDe('no_valido').status, 404)
assert.equal(respuestaDe('cualquier cosa rara').status, 404, 'un estado desconocido nunca se toma por exito')
console.log('OK: todas las pruebas del registro por QR pasan')
