// Pruebas de la validacion del registro por QR. Uso: npm run test:checkin
import assert from 'node:assert/strict'
const { validarRegistro, respuestaDe, TOKEN_RE } = await import('../supabase/functions/checkin-evento/validar.ts')

const bueno = { nombre: 'María José', apellido: 'García  López', telefono: '+34 600 111 222', email: 'MARIA@Ejemplo.com', consentimiento: true, mayor14: true, web: '' }
const r = validarRegistro(bueno)
assert.ok(r.ok)
assert.deepEqual(r.ok && r.datos, { nombre: 'María José', apellido: 'García López', telefono: '+34 600 111 222', email: 'maria@ejemplo.com', textoVersion: '', idioma: '', canales: [] }, 'normaliza espacios y pasa el correo a minusculas')

// Casillas de canal: solo cuentan las que llegan exactamente como true, y el correo exige un correo
const marcadas = validarRegistro({ ...bueno, canales: { email: true, whatsapp: true, sms: false } })
assert.ok(marcadas.ok && marcadas.datos.canales.join() === 'email,whatsapp', 'las casillas marcadas pasan, en orden fijo')
for (const c of [{ email: 'true' }, { email: 1 }, { whatsapp: 'si' }, { telegram: true }, null, [], 'email', ['email']]) {
  const x = validarRegistro({ ...bueno, canales: c })
  assert.ok(x.ok && x.datos.canales.length === 0, 'no cuenta como casilla marcada: ' + JSON.stringify(c))
}
assert.ok(validarRegistro({ ...bueno }).ok && (validarRegistro({ ...bueno }) as { datos: { canales: string[] } }).datos.canales.length === 0, 'sin casillas el registro es válido')
assert.deepEqual(validarRegistro({ ...bueno, email: '', canales: { email: true } }), { ok: false, error: 'datos' }, 'correo marcado sin correo: datos incompletos')
assert.ok(validarRegistro({ ...bueno, email: '', canales: { whatsapp: true, sms: true } }).ok, 'WhatsApp y SMS no necesitan correo')

// Versión del texto aceptado e idioma: solo pasan si tienen forma válida; si no, quedan vacíos y no impiden el registro
const conVersion = validarRegistro({ ...bueno, texto_version: 'v1', idioma: 'pt-BR' })
assert.ok(conVersion.ok && conVersion.datos.textoVersion === 'v1' && conVersion.datos.idioma === 'pt-BR', 'conserva versión e idioma válidos')
for (const malo of [{ texto_version: 'V1' }, { texto_version: 'v1; drop table' }, { texto_version: 'x'.repeat(21) }, { texto_version: 1 }, { idioma: 'de' }, { idioma: 'es; x' }, { idioma: ['es'] }]) {
  const x = validarRegistro({ ...bueno, ...malo })
  assert.ok(x.ok, 'una versión o idioma inválidos no rechazan el registro: ' + JSON.stringify(malo))
  assert.ok(x.ok && x.datos.textoVersion === '' && (malo.idioma === undefined || x.datos.idioma === ''), 'se descartan: ' + JSON.stringify(malo))
}

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
