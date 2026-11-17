// Invariantes de seguridad de las funciones de borde, comprobadas sobre el codigo. Uso: npm run test:funciones
import assert from 'node:assert/strict'
import { readdirSync, readFileSync, existsSync } from 'node:fs'

const RAIZ = process.env.FUNCIONES_DIR ?? 'supabase/functions'
type Politica = { verify_jwt: boolean; acceso: string; motivo: string; autenticacion_sin_jwt?: string[]; sin_navegador?: boolean }
const AUTENTICACIONES = ['token_en_enlace', 'sesion_dentro', 'secreto_de_servidor']
const politicas = JSON.parse(readFileSync(`${RAIZ}/politicas.json`, 'utf8')) as Record<string, Politica>
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
  // Salvo una funcion que solo llama otro servidor (sin_navegador), debe tener lista de origenes propios
  if (p.sin_navegador !== true) assert.ok(/ORIGENES_[A-Z_]+/.test(sinComentarios), `${f}: debe usar una lista de origenes permitidos`)

  // Nada de req.json() sin tope: se lee el texto, se mide y se interpreta
  if (/req(\.clone\(\))?\.json\(\)/.test(sinComentarios)) {
    assert.ok(SIN_TOPE_DE_CUERPO[f], `${f}: lee el cuerpo con req.json() (o req.clone().json()) sin tope de tamano. Usa req.text() con MAX_CUERPO, o justifica la excepcion en esta prueba`)
  } else {
    assert.ok(/MAX_CUERPO/.test(sinComentarios) && /req\.text\(\)/.test(sinComentarios), `${f}: debe leer el cuerpo con req.text() y un MAX_CUERPO`)
  }

  // Una funcion sin verificacion de JWT es publica de verdad: debe decir como se identifica quien llama, y el codigo debe hacerlo
  if (!p.verify_jwt) {
    assert.ok(!SIN_TOPE_DE_CUERPO[f], `${f}: sin verify_jwt no puede tener la excepcion de cuerpo sin tope`)
    assert.ok(p.motivo.length > 80, `${f}: una funcion sin verify_jwt necesita un motivo detallado`)
    const a = p.autenticacion_sin_jwt
    assert.ok(Array.isArray(a) && a.length > 0 && a.every(x => AUTENTICACIONES.includes(x)), `${f}: sin verify_jwt debe declarar autenticacion_sin_jwt con valores de ${AUTENTICACIONES.join(', ')}`)
    if (a.includes('sesion_dentro')) assert.ok(/auth\.getUser\(/.test(sinComentarios), `${f}: declara sesion_dentro pero no valida la sesion con auth.getUser`)
    if (a.includes('secreto_de_servidor')) {
      assert.ok(/Deno\.env\.get\(\s*['"][A-Z0-9_]*(SECRET|CRON|TOKEN)[A-Z0-9_]*['"]/.test(sinComentarios), `${f}: declara secreto_de_servidor pero no lee un secreto del entorno (nombre con SECRET, CRON o TOKEN)`)
      assert.ok(/timingSafeEqual|constantTimeEqual|iguales_en_tiempo_constante/.test(sinComentarios), `${f}: debe comparar el secreto en tiempo constante`)
    }
    if (a.includes('token_en_enlace')) assert.ok(/[a-f0-9]\{(32|64)\}|\{\s*(32|64)\s*\}|TOKEN_RE|token/i.test(sinComentarios), `${f}: declara token_en_enlace pero no valida ningun token`)
  } else {
    assert.ok(p.autenticacion_sin_jwt === undefined, `${f}: con verify_jwt true no se declara autenticacion_sin_jwt`)
  }

  // Nunca se devuelve al cliente el mensaje interno de un error (va al registro con console.error)
  assert.ok(!/json\(\s*\{[^}]*error:\s*(?:\w+\??\.)+message\s*[,}]/.test(sinComentarios), `${f}: devuelve un mensaje interno al cliente`)
  assert.ok(!/json\(\s*\{[^}]*\$\{[^}]*message[^}]*\}/.test(sinComentarios), `${f}: interpola un mensaje interno en la respuesta`)

  // Las URLs de redireccion salen de una lista, nunca del origen que manda el cliente
  for (const m of sinComentarios.matchAll(/redirectTo:\s*`?([^,\n}]*)/g)) {
    assert.ok(!/req\.headers/.test(m[1] ?? ''), `${f}: redirectTo construido directamente con una cabecera del cliente`)
  }
}

console.log(`OK: ${carpetas.length} funciones de borde cumplen las invariantes de seguridad`)
