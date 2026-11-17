// Pruebas de la validacion del registro de iglesias. Uso: npm run test:registro
import assert from 'node:assert/strict'
const { validarRegistro, respuestaDeError, normalizarCodigo, CODIGO_RE, decidirAlta } = await import('../supabase/functions/registro-iglesia/validar.ts')

const bueno = {
  iglesia: { nombre: '  Casa   Reino ', slug: 'Casa-Reino', pais: 'España', ciudad: 'Sevilla' },
  propietario: { nombre: 'María José', apellido: 'García  López', email: 'MARIA@Ejemplo.com' },
  codigo: ' adn-abcd-2345 ', consentimiento: true,
}
const r = validarRegistro(bueno, true)
assert.ok(r.ok)
assert.deepEqual(r.ok && r.datos, {
  iglesia: { nombre: 'Casa Reino', slug: 'casa-reino', pais: 'España', ciudad: 'Sevilla' },
  paisIso: null, moneda: 'USD',
  propietario: { nombre: 'María José', apellido: 'García López', email: 'maria@ejemplo.com' },
  codigo: 'ADN-ABCD-2345',
  plan: 'semilla', estructura: { tipo: 'unica', personas: null, sedes: 0 }, modulos: [], administradores: [],
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

// ---- Asistente de alta: plan, estructura, modulos y administradores propuestos ----
const asistente = {
  ...bueno,
  plan: 'basico',
  estructura: { tipo: 'con_sedes', personas: 250, sedes: 3 },
  modulos: ['whatsapp', 'credenciales', 'whatsapp'],
  administradores: [{ nombre: ' Ana ', apellido: 'Gil', email: 'ANA@Ejemplo.com' }, { nombre: 'Luis', apellido: 'Perez', email: 'luis@ejemplo.com' }],
}
const ra = validarRegistro(asistente, true)
assert.ok(ra.ok)
assert.equal(ra.ok && ra.datos.plan, 'basico')
assert.deepEqual(ra.ok && ra.datos.estructura, { tipo: 'con_sedes', personas: 250, sedes: 3 })
assert.deepEqual(ra.ok && ra.datos.modulos, ['whatsapp', 'credenciales'], 'sin repetidos')
assert.deepEqual(ra.ok && ra.datos.administradores.map(a => a.email), ['ana@ejemplo.com', 'luis@ejemplo.com'], 'correos normalizados')
assert.equal(ra.ok && ra.datos.administradores[0]?.nombre, 'Ana')
const asis = (cambio: Record<string, unknown>) => ({ ...asistente, ...cambio })
const estr = (cambio: Record<string, unknown>) => asis({ estructura: { ...asistente.estructura, ...cambio } })

// Plan
for (const mal of ['', 'Basico', 'con espacio', '../x', 'a'.repeat(31), 7, null, ['basico'], { clave: 'basico' }]) assert.equal(error(asis({ plan: mal })), 'datos', 'plan ' + JSON.stringify(mal))
// Estructura
assert.equal(error(asis({ estructura: 'unica' })), 'datos')
assert.equal(error(asis({ estructura: null })), 'datos')
assert.equal(error(asis({ estructura: [] })), 'datos')
assert.equal(error(estr({ tipo: 'megaiglesia' })), 'datos', 'una megaiglesia es un tamano, no una estructura')
assert.equal(error(estr({ tipo: 7 })), 'datos')
for (const mal of [0, -1, 1.5, '250', null, undefined, 1_000_001, NaN, Infinity]) assert.equal(error(estr({ personas: mal })), 'datos', 'personas ' + String(mal))
assert.equal(error(estr({ personas: 1 })), 'ok'); assert.equal(error(estr({ personas: 1_000_000 })), 'ok')
for (const mal of [-1, 201, 1.5, '3']) assert.equal(error(estr({ sedes: mal })), 'datos', 'sedes ' + String(mal))
assert.equal(error(estr({ tipo: 'unica', sedes: 2 })), 'datos', 'una iglesia unica no tiene sedes')
assert.equal(error(estr({ tipo: 'unica', sedes: 0 })), 'ok')
assert.equal(error(estr({ tipo: 'red', sedes: undefined })), 'ok', 'las sedes son opcionales')
// Modulos
for (const mal of ['whatsapp', {}, [7], [null], ['Whatsapp'], ['con espacio'], ['a'.repeat(41)], Array.from({ length: 31 }, (_, i) => 'm' + i)]) assert.equal(error(asis({ modulos: mal })), 'datos', 'modulos ' + JSON.stringify(mal).slice(0, 30))
assert.equal(error(asis({ modulos: [] })), 'ok')
assert.equal(error(asis({ modulos: Array.from({ length: 30 }, (_, i) => 'm' + i) })), 'ok')
// Administradores propuestos
const adm = (n: string, e: string) => ({ nombre: n, apellido: 'X', email: e })
assert.equal(error(asis({ administradores: 'ana@x.com' })), 'datos')
assert.equal(error(asis({ administradores: [adm('A', 'no-correo')] })), 'datos')
assert.equal(error(asis({ administradores: [adm('', 'a@x.com')] })), 'datos')
assert.equal(error(asis({ administradores: [adm('Ana', 'a@x.com'), adm('Otra', 'A@X.com')] })), 'datos', 'sin correos repetidos')
assert.equal(error(asis({ administradores: [adm('Ana', 'maria@ejemplo.com')] })), 'datos', 'ni el del propietario')
assert.equal(error(asis({ administradores: [adm('Ana‮', 'a@x.com')] })), 'datos', 'caracteres invisibles')
assert.equal(error(asis({ administradores: [null] })), 'datos')
assert.equal(error(asis({ administradores: Array.from({ length: 6 }, (_, i) => adm('N' + i, `n${i}@x.com`)) })), 'datos', 'como mucho cinco')
assert.equal(error(asis({ administradores: Array.from({ length: 5 }, (_, i) => adm('N' + i, `n${i}@x.com`)) })), 'ok')
// El formato antiguo sigue valiendo (una pagina en cache durante un despliegue)
assert.equal(error(bueno), 'ok')

// Decision con el catalogo real: el navegador solo propone
const mods = [{ clave: 'miembros', tipo: 'nucleo' }, { clave: 'formacion', tipo: 'incluido' }, { clave: 'whatsapp', tipo: 'incluido' }, { clave: 'credenciales', tipo: 'especial' }]
const basico = { clave: 'basico', max_miembros: 300 }
const d1 = decidirAlta({ estructura: { tipo: 'unica', personas: 250, sedes: 0 }, modulos: ['formacion', 'whatsapp'] }, basico, mods, ['miembros', 'formacion'])
assert.deepEqual(d1, { ok: true, extras: ['whatsapp'] }, 'lo que el plan ya incluye no es un extra')
assert.deepEqual(decidirAlta({ estructura: { tipo: 'unica', personas: 250, sedes: 0 }, modulos: [] }, basico, mods, []), { ok: true, extras: [] })
assert.deepEqual(decidirAlta({ estructura: { tipo: 'unica', personas: 301, sedes: 0 }, modulos: [] }, basico, mods, []), { ok: false, error: 'plan' }, 'el plan debe cubrir el tamano')
assert.deepEqual(decidirAlta({ estructura: { tipo: 'unica', personas: 300, sedes: 0 }, modulos: [] }, basico, mods, []), { ok: true, extras: [] }, 'justo en el limite cabe')
assert.deepEqual(decidirAlta({ estructura: { tipo: 'unica', personas: 9999999, sedes: 0 }, modulos: [] }, { clave: 'premium', max_miembros: null }, mods, []), { ok: true, extras: [] }, 'sin limite')
assert.deepEqual(decidirAlta({ estructura: { tipo: 'unica', personas: null, sedes: 0 }, modulos: [] }, basico, mods, []), { ok: true, extras: [] }, 'formato antiguo, sin tamano')
assert.deepEqual(decidirAlta({ estructura: { tipo: 'unica', personas: 1, sedes: 0 }, modulos: [] }, null, mods, []), { ok: false, error: 'plan' }, 'un plan que no existe')
assert.deepEqual(decidirAlta({ estructura: { tipo: 'unica', personas: 1, sedes: 0 }, modulos: ['inventado'] }, basico, mods, []), { ok: false, error: 'modulos' }, 'un modulo que no existe')
assert.deepEqual(decidirAlta({ estructura: { tipo: 'unica', personas: 1, sedes: 0 }, modulos: ['miembros'] }, basico, mods, []), { ok: false, error: 'modulos' }, 'el nucleo no se contrata ni se regala')
assert.equal(respuestaDeError('plan').status, 400); assert.equal(respuestaDeError('modulos').status, 400)

console.log('OK: todas las pruebas del registro de iglesias pasan')

// Pais y moneda: sin codigo se paga en USD; con codigo de la zona euro, en EUR; un codigo mal formado se rechaza
const conPais = (iso: unknown) => validarRegistro({ ...bueno, iglesia: { ...bueno.iglesia, pais_iso: iso } }, true)
const rEs = conPais('ES'); assert.ok(rEs.ok && rEs.datos.moneda === 'EUR' && rEs.datos.paisIso === 'ES')
const rMx = conPais('MX'); assert.ok(rMx.ok && rMx.datos.moneda === 'USD')
for (const malo of ['es', 'ESP', 'E', '1A', 5, {}, ['ES']]) assert.equal(conPais(malo).ok, false, `pais_iso ${JSON.stringify(malo)} se rechaza`)
// La lista de paises con euro del servidor coincide con la del navegador
const { PAISES_EURO: a1, monedaDePais: m1 } = await import('../supabase/functions/registro-iglesia/validar.ts')
const { PAISES_EURO: a2, monedaDePais: m2 } = await import('../src/lib/cotizador.ts')
assert.deepEqual([...a1], [...a2], 'PAISES_EURO igual en servidor y navegador')
for (const c of ['ES', 'DE', 'US', 'MX', 'BR', 'FR']) assert.equal(m1(c), m2(c))
console.log('OK: pais y moneda')
