// Pruebas de la validacion del registro de iglesias. Uso: npm run test:registro
import assert from 'node:assert/strict'
const { validarRegistro, respuestaDeError, normalizarCodigo, CODIGO_RE } = await import('../supabase/functions/registro-iglesia/validar.ts')

const bueno = {
  iglesia: { nombre: '  Casa   Reino ', slug: 'Casa-Reino', pais: 'España', ciudad: 'Sevilla' },
  propietario: { nombre: 'María José', apellido: 'García  López', email: 'MARIA@Ejemplo.com' },
  codigo: ' adn-abcd-2345 ', consentimiento: true,
}
const r = validarRegistro(bueno, true)
assert.ok(r.ok)
assert.deepEqual(r.ok && r.datos, {
  iglesia: { nombre: 'Casa Reino', slug: 'casa-reino', pais: 'España', ciudad: 'Sevilla' },
  propietario: { nombre: 'María José', apellido: 'García López', email: 'maria@ejemplo.com' },
  codigo: 'ADN-ABCD-2345',
})

const error = (b: Record<string, unknown>, req = true) => { const x = validarRegistro(b, req); return x.ok ? 'ok' : x.error }
const con = (cambio: Record<string, unknown>) => ({ ...bueno, ...cambio })
const conIg = (cambio: Record<string, unknown>) => ({ ...bueno, iglesia: { ...bueno.iglesia, ...cambio } })
const conPr = (cambio: Record<string, unknown>) => ({ ...bueno, propietario: { ...bueno.propietario, ...cambio } })

// Robot, consentimiento
assert.equal(error(con({ web: 'http://spam' })), 'bot')
assert.equal(error(con({ web: '   ' })), 'ok', 'un campo trampa en blanco no cuenta')
assert.equal(error(con({ consentimiento: false })), 'consentimiento')
assert.equal(error(con({ consentimiento: 'true' })), 'consentimiento')
assert.equal(error({ ...bueno, consentimiento: undefined }), 'consentimiento')

// Iglesia
assert.equal(error(conIg({ nombre: 'A' })), 'datos')
assert.equal(error(conIg({ nombre: 'x'.repeat(81) })), 'datos')
assert.equal(error(conIg({ slug: 'ab' })), 'datos')
assert.equal(error(conIg({ slug: 'con espacio' })), 'datos')
assert.equal(error(conIg({ slug: '-inicio' })), 'datos')
assert.equal(error(conIg({ slug: 'doble--guion' })), 'datos')
assert.equal(error(conIg({ slug: 'a'.repeat(41) })), 'datos')
assert.equal(error(conIg({ pais: '' })), 'datos')
assert.equal(error(conIg({ ciudad: '' })), 'datos')
assert.equal(error(conIg({ nombre: 'Casa​Reino' })), 'datos', 'caracteres invisibles')
assert.equal(error(con({ iglesia: 'texto' })), 'datos')
assert.equal(error(con({ iglesia: null })), 'datos')

// Propietario
assert.equal(error(conPr({ nombre: '' })), 'datos')
assert.equal(error(conPr({ apellido: '' })), 'datos')
assert.equal(error(conPr({ email: 'no-es-correo' })), 'datos')
assert.equal(error(conPr({ email: '' })), 'datos', 'el correo es obligatorio: de el sale el acceso')
assert.equal(error(conPr({ nombre: 'n'.repeat(61) })), 'datos')
assert.equal(error(conPr({ nombre: 'Ana‮X' })), 'datos', 'direccion de texto invertida')

// Codigo: obligatorio solo si el ajuste lo pide
assert.equal(error(con({ codigo: 'ADN-ABCD-234' })), 'codigo_formato')
assert.equal(error(con({ codigo: 'ADN-ABCD-0O1I' })), 'codigo_formato', 'sin letras ambiguas')
assert.equal(error(con({ codigo: '' })), 'codigo_formato')
assert.equal(error(con({ codigo: 12345 })), 'codigo_formato')
assert.equal(error(con({ codigo: undefined }), false), 'ok', 'sin exigencia de codigo, no hace falta')
assert.equal(error(con({ codigo: 'basura' }), false), 'ok', 'sin exigencia, un codigo mal escrito se ignora')
assert.equal(normalizarCodigo(' adn-abcd-2345\n'), 'ADN-ABCD-2345')
assert.ok(CODIGO_RE.test('ADN-ABCD-2345'))
assert.ok(!CODIGO_RE.test('adn-abcd-2345'))

// Respuestas
assert.deepEqual(respuestaDeError('codigo'), { status: 403, cuerpo: { error: 'codigo' } })
assert.deepEqual(respuestaDeError('codigo_formato'), { status: 403, cuerpo: { error: 'codigo' } }, 'un codigo mal escrito y uno falso se responden igual')
assert.equal(respuestaDeError('limite').status, 429)
assert.equal(respuestaDeError('slug').status, 409)
assert.equal(respuestaDeError('cerrado').status, 403)
assert.equal(respuestaDeError('lo-que-sea').status, 400)

console.log('OK: todas las pruebas del registro de iglesias pasan')
