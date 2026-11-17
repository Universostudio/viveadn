// Invariantes de seguridad de las funciones de borde, comprobadas sobre el codigo. Uso: npm run test:funciones
import assert from 'node:assert/strict'
import { readdirSync, readFileSync, existsSync } from 'node:fs'

const RAIZ = 'supabase/functions'
const politicas = JSON.parse(readFileSync(`${RAIZ}/politicas.json`, 'utf8')) as Record<string, { verify_jwt: boolean; acceso: string; motivo: string }>
delete (politicas as Record<string, unknown>)._nota

// Excepciones conocidas y razonadas. Cada una debe desaparecer cuando se corrija; una nueva exige justificarla aqui.
const SIN_TOPE_DE_CUERPO: Record<string, string> = {
  plataforma: 'solo administradores con sesion; pendiente de corregir en el proximo despliegue de esa funcion',
}

const carpetas = readdirSync(RAIZ, { withFileTypes: true }).filter(d => d.isDirectory() && existsSync(`${RAIZ}/${d.name}/index.ts`)).map(d => d.name).sort()
assert.deepEqual(carpetas, Object.keys(politicas).sort(), 'cada funcion de borde tiene su entrada en politicas.json y viceversa')

for (const f of carpetas) {
  const p = politicas[f]!
  const codigo = readFileSync(`${RAIZ}/${f}/index.ts`, 'utf8')
  const sinComentarios = codigo.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1')

  assert.equal(typeof p.verify_jwt, 'boolean', `${f}: verify_jwt debe estar declarado`)
  assert.ok(p.acceso.length > 5 && p.motivo.length > 20, `${f}: acceso y motivo deben estar explicados`)

  // Sin CORS comodin: solo origenes propios
  assert.ok(!/Access-Control-Allow-Origin['"]?\s*:\s*['"]\*['"]/.test(sinComentarios), `${f}: CORS con comodin`)
  assert.ok(/ORIGENES_[A-Z_]+/.test(sinComentarios), `${f}: debe usar una lista de origenes permitidos`)

  // Nada de req.json() sin tope: se lee el texto, se mide y se interpreta
  if (/req(\.clone\(\))?\.json\(\)/.test(sinComentarios)) {
    assert.ok(SIN_TOPE_DE_CUERPO[f], `${f}: lee el cuerpo con req.json() (o req.clone().json()) sin tope de tamano. Usa req.text() con MAX_CUERPO, o justifica la excepcion en esta prueba`)
  } else {
    assert.ok(/MAX_CUERPO/.test(sinComentarios) && /req\.text\(\)/.test(sinComentarios), `${f}: debe leer el cuerpo con req.text() y un MAX_CUERPO`)
  }

  // Una funcion sin verificacion de JWT es publica de verdad: exige tope de cuerpo, lista de origenes y motivo propio
  if (!p.verify_jwt) {
    assert.ok(!SIN_TOPE_DE_CUERPO[f], `${f}: sin verify_jwt no puede tener la excepcion de cuerpo sin tope`)
    assert.ok(p.motivo.length > 80, `${f}: una funcion sin verify_jwt necesita un motivo detallado`)
  }

  // Nunca se devuelve al cliente el mensaje interno de un error (va al registro con console.error)
  assert.ok(!/json\(\s*\{[^}]*error:\s*(?:\w+\??\.)+message\s*[,}]/.test(sinComentarios), `${f}: devuelve un mensaje interno al cliente`)
  assert.ok(!/json\(\s*\{[^}]*\$\{[^}]*message[^}]*\}/.test(sinComentarios), `${f}: interpola un mensaje interno en la respuesta`)

  // Las URLs de redireccion salen de una lista, nunca del origen que manda el cliente
  for (const m of sinComentarios.matchAll(/redirectTo:\s*`?([^,\n}]*)/g)) {
    assert.ok(!/req\.headers/.test(m[1] ?? ''), `${f}: redirectTo construido directamente con una cabecera del cliente`)
  }
}

// Solo invitaciones puede ir sin verify_jwt, y asi esta decidido
assert.deepEqual(carpetas.filter(f => !politicas[f]!.verify_jwt), ['invitaciones'], 'solo invitaciones va sin verify_jwt')
console.log(`OK: ${carpetas.length} funciones de borde cumplen las invariantes de seguridad`)
