// Pruebas de la doble confirmación: el correo (contenido, enlaces, cabeceras), la lectura de la baja de un clic y la clave de
// la tarea programada. No envía nada. Uso: npm run test:confirmacion
import assert from 'node:assert/strict'
const { construirCorreo, claveCronValida, limpiar } = await import('../supabase/functions/enviar-confirmaciones/correo.ts')
const { leerPeticion } = await import('../supabase/functions/baja/entrada.ts')

const T = 'a'.repeat(64), B = 'b'.repeat(64)
const base = { destino: 'ana@ejemplo.test', nombre: 'Ana', iglesia: 'Iglesia Prueba', idioma: 'es', token: T, bajaToken: B, web: 'https://viveadn.com', funciones: 'https://proyecto.supabase.test', dias: 3 }

// Contenido, enlaces y cabeceras
const c = construirCorreo(base)
assert.equal(c.enlaces.confirmar, `https://viveadn.com/confirmar/${T}`)
assert.equal(c.enlaces.baja, `https://viveadn.com/baja/${B}`)
assert.equal(c.enlaces.bajaUnClic, `https://proyecto.supabase.test/functions/v1/baja?t=${B}`)
assert.equal(c.cabeceras['List-Unsubscribe'], `<${c.enlaces.bajaUnClic}>`, 'List-Unsubscribe con una sola dirección https')
assert.equal(c.cabeceras['List-Unsubscribe-Post'], 'List-Unsubscribe=One-Click', 'baja de un clic (RFC 8058)')
assert.ok(!/mailto:/i.test(c.cabeceras['List-Unsubscribe']!), 'no promete un buzón que nadie lee')
assert.equal(Object.keys(c.cabeceras).length, 2)
assert.ok(c.texto.includes(c.enlaces.confirmar) && c.texto.includes(c.enlaces.baja), 'el texto lleva la confirmación y la baja')
assert.ok(c.html.includes(`href="${c.enlaces.confirmar}"`) && c.html.includes(c.enlaces.baja), 'el HTML también')
assert.ok(!c.texto.includes(c.enlaces.bajaUnClic) && !c.html.includes(c.enlaces.bajaUnClic), 'la dirección de un clic solo va en la cabecera')
assert.match(c.asunto, /Iglesia Prueba/)
for (const [idioma, palabra] of [['es', 'Confirma'], ['en', 'Confirm'], ['fr', 'Confirmez'], ['pt-BR', 'Confirme']] as const) {
  assert.match(construirCorreo({ ...base, idioma }).asunto, new RegExp(palabra), `asunto en ${idioma}`)
  assert.ok(construirCorreo({ ...base, idioma }).texto.includes('3'), `la caducidad aparece en ${idioma}`)
}
assert.match(construirCorreo({ ...base, idioma: 'de' }).asunto, /Confirma/, 'un idioma desconocido cae a español')
assert.match(construirCorreo({ ...base, idioma: null }).asunto, /Confirma/, 'sin idioma, español')

// Inyección: nada que venga de una persona rompe una cabecera ni el HTML
const sucio = construirCorreo({ ...base, iglesia: 'Iglesia\r\nBcc: victima@x.test‮', nombre: '<script>alert(1)</script>"\'&' })
assert.ok(!/[\r\n]/.test(sucio.asunto), 'el asunto no lleva saltos de línea')
assert.ok(!/[‮]/.test(sucio.asunto), 'ni caracteres de dirección de texto')
assert.ok(!sucio.html.includes('<script>'), 'el nombre se escapa en el HTML')
assert.ok(sucio.html.includes('&lt;script&gt;'), 'y queda visible como texto')
assert.equal(limpiar('a\u0000b\tc'), 'a b c')
assert.ok(limpiar('x'.repeat(500)).length <= 120)

// Entradas inválidas
for (const [campo, valor, texto] of [
  ['destino', 'sin-arroba', 'destino'], ['destino', `${'a'.repeat(250)}@x.es`, 'destino'],
  ['token', 'corto', 'secreto'], ['token', 'A'.repeat(64), 'secreto'], ['bajaToken', 'g'.repeat(64), 'secreto'], ['bajaToken', T, 'secreto'],
  ['web', 'http://viveadn.com', 'direccion'], ['web', 'https://viveadn.com/ruta', 'direccion'], ['web', 'https://u:p@viveadn.com', 'direccion'], ['web', 'https://viveadn.com?x=1', 'direccion'], ['web', 'javascript:alert(1)', 'direccion'],
  ['funciones', 'http://p.test', 'direccion'], ['funciones', 'no-es-una-url', 'direccion'],
  ['dias', 0, 'dias'], ['dias', 15, 'dias'], ['dias', 1.5, 'dias'],
] as const) assert.throws(() => construirCorreo({ ...base, [campo]: valor }), new RegExp(texto), `${campo} = ${String(valor).slice(0, 20)}`)

// Lectura de la baja
const URL_F = 'https://proyecto.supabase.test/functions/v1/baja'
const form = 'application/x-www-form-urlencoded'
assert.deepEqual(leerPeticion(URL_F, 'application/json', JSON.stringify({ token: B })), { modo: 'json', token: B }, 'la página envía JSON')
assert.deepEqual(leerPeticion(URL_F, null, JSON.stringify({ token: B.toUpperCase() })), { modo: 'json', token: B }, 'el secreto se normaliza')
assert.deepEqual(leerPeticion(`${URL_F}?t=${B}`, form, 'List-Unsubscribe=One-Click'), { modo: 'una_clic', token: B }, 'baja de un clic del programa de correo')
assert.deepEqual(leerPeticion(`${URL_F}?t=${B}`, `${form}; charset=UTF-8`, 'List-Unsubscribe=One-Click\r\n'), { modo: 'una_clic', token: B }, 'con charset y salto final')
for (const [url, tipo, cuerpo, motivo] of [
  [`${URL_F}?t=${B}`, form, '', 'sin cuerpo: no es una baja de un clic'],
  [`${URL_F}?t=${B}`, form, 'List-Unsubscribe=otra-cosa', 'cuerpo distinto'],
  [`${URL_F}?t=${B}`, 'application/json', 'List-Unsubscribe=One-Click', 'tipo de contenido distinto'],
  [`${URL_F}?t=${B}`, 'text/plain', 'List-Unsubscribe=One-Click', 'texto plano'],
  [`${URL_F}?t=corto`, form, 'List-Unsubscribe=One-Click', 'secreto mal formado en la dirección'],
  [`${URL_F}?t=`, form, 'List-Unsubscribe=One-Click', 'secreto vacío en la dirección'],
  [URL_F, 'application/json', '{"token": "x"}', 'secreto mal formado en JSON'],
  [URL_F, 'application/json', 'no es json', 'JSON roto'],
  [URL_F, 'application/json', '', 'sin cuerpo'],
  [URL_F, form, 'List-Unsubscribe=One-Click', 'baja de un clic sin secreto'],
  ['no-es-una-url', 'application/json', JSON.stringify({ token: B }), null],
] as const) {
  const r = leerPeticion(url, tipo, cuerpo)
  if (motivo === null) assert.equal(r?.modo, 'json', 'una dirección rara no impide leer el JSON')
  else assert.equal(r, null, motivo)
}
assert.equal(leerPeticion(`${URL_F}?t=${B}`, 'application/json', JSON.stringify({ token: T })), null, 'el secreto de la dirección manda: con tipo JSON no se mezclan')

// Clave de la tarea programada
const K = 'k'.repeat(40)
assert.equal(await claveCronValida(K, K), true)
for (const [r, e] of [[null, K], ['', K], [K, undefined], [K, ''], ['corta', 'corta'], [K, K + 'x'], ['otra' + 'k'.repeat(40), K]] as const) assert.equal(await claveCronValida(r as string | null, e as string | undefined), false, `${String(r).slice(0, 8)}/${String(e).slice(0, 8)}`)
console.log('OK: todas las pruebas de la doble confirmación pasan')
