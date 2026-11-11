// Pruebas del verificador de entornos (scripts/entorno/verificar.mts) con un entorno simulado, sano y con fallos provocados. Uso: npm run test:entorno
import assert from 'node:assert/strict'
import { verificar, FUNCIONES_CON_CORS, RUTAS_LEGALES } from './entorno/verificar.mts'

const WEB = 'https://pruebas.ejemplo.dev'
const SB = 'https://proyecto.supabase.test'
const ANON = 'clave-publica-de-prueba'
const CRON = 'secreto-de-la-tarea-que-nunca-debe-aparecer-1234567890'

interface Fallos { sinCors?: string; baja401?: boolean; atrasada?: boolean; secretoMalo?: boolean; sinSalud?: boolean; sinNoindex?: boolean; sinFuncion?: string; red?: boolean; tareaAbierta?: boolean; sinJwtEnDar?: boolean }
function entorno(fallos: Fallos = {}): typeof fetch {
  const j = (o: unknown, estado = 200, cab: Record<string, string> = {}) => new Response(JSON.stringify(o), { status: estado, headers: { 'content-type': 'application/json', ...cab } })
  return (async (entrada: string | URL | Request, init: RequestInit = {}) => {
    if (fallos.red) throw new Error('ECONNREFUSED con detalles internos')
    const url = String(entrada); const m = init.method ?? 'GET'
    const h = Object.fromEntries(Object.entries((init.headers ?? {}) as Record<string, string>).map(([k, v]) => [k.toLowerCase(), v]))
    if (url.startsWith(WEB)) {
      const ruta = url.slice(WEB.length)
      if (ruta === '/') return new Response('<html></html>', { status: 200, headers: fallos.sinNoindex ? {} : { 'x-robots-tag': 'noindex, nofollow, noarchive' } })
      if (ruta === '/api/salud') return fallos.sinSalud ? j({ ok: false }, 503) : j({ ok: true })
      if ((RUTAS_LEGALES as readonly string[]).includes(ruta)) return new Response('<html></html>', { status: 200 })
      return new Response('no', { status: 404 })
    }
    const nombre = url.replace(`${SB}/functions/v1/`, '')
    if (nombre === fallos.sinFuncion) return j({ code: 'NOT_FOUND' }, 404)
    if (m === 'OPTIONS') {
      const ok = nombre !== fallos.sinCors
      return new Response('ok', { status: 200, headers: ok ? { 'access-control-allow-origin': h.origin! } : { 'access-control-allow-origin': 'https://viveadn.com' } })
    }
    // Pasarela de funciones: plataforma se despliega verificando el JWT; enviar-confirmaciones, no
    if (nombre === 'plataforma' && !h.authorization?.startsWith('Bearer ')) return j({ msg: 'Missing authorization header' }, 401)
    if (h['x-adn-cron'] !== undefined) {
      if (nombre === 'enviar-confirmaciones' || h['x-adn-cron'] !== CRON || fallos.secretoMalo) return fallos.tareaAbierta && h['x-adn-cron'] !== CRON ? j({ ok: true }) : j({ error: 'Sin permiso' }, 403)
      const { accion } = JSON.parse(String(init.body))
      if (accion === 'estado_purga') return j({ ok: true, en_borrado: 2, vencidas: fallos.atrasada ? 1 : 0, horas_mas_atrasada: fallos.atrasada ? 60 : 0, atrasada: !!fallos.atrasada })
      if (accion === 'libro_purgas') return j({ ok: true, registro: [{ iglesia: 'a', purgada_en: 'b' }] })
    }
    if (nombre === 'baja' || nombre === 'confirmar-suscripcion') return fallos.baja401 && nombre === 'baja' ? j({ msg: 'Invalid JWT' }, 401) : j({ ok: false, motivo: 'invalido' })
    if (nombre === 'dar-publico') {
      const conClave = h.apikey === ANON && h.authorization === `Bearer ${ANON}`
      return conClave || fallos.sinJwtEnDar ? j({ ok: true }) : j({ msg: 'Missing authorization header' }, 401)
    }
    return j({ ok: true })
  }) as typeof fetch
}
const por = (r: Awaited<ReturnType<typeof verificar>>, parte: string) => r.find(x => x.nombre.includes(parte))
const malos = (r: Awaited<ReturnType<typeof verificar>>) => r.filter(x => !x.ok).map(x => x.nombre)

// Entorno sano, con todo
let r = await verificar({ web: WEB, supabase: SB, anon: ANON, cron: CRON }, entorno())
assert.deepEqual(malos(r), [], 'un entorno sano pasa todas las comprobaciones')
assert.ok(r.length >= 25, `y son muchas comprobaciones (${r.length})`)
assert.equal(r.filter(x => x.nombre.startsWith('cors:')).length, FUNCIONES_CON_CORS.length, 'se comprueba el CORS de cada función')
assert.ok(por(r, 'purga: al día')!.detalle.includes('en borrado suave 2'), 'la purga informa de sus cifras')
// Sin secreto ni clave: se omiten esas comprobaciones, el resto pasa (la pasarela rechaza a plataforma con 401 y cuenta como cerrada)
r = await verificar({ web: WEB, supabase: SB }, entorno())
assert.deepEqual(malos(r), [], 'sin secretos pasan las comprobaciones públicas')
assert.ok(por(r, 'tarea: plataforma')!.detalle.includes('VITE_SUPABASE_ANON_KEY'), 'y avisa de que con la clave pública se comprueba mejor')
assert.ok(!r.some(x => x.nombre.startsWith('purga:')) && !r.some(x => x.nombre.startsWith('con JWT')), 'y no se hacen las que necesitan secreto')
// El secreto de la tarea sin la clave pública no basta: la tarea real envía las dos
r = await verificar({ web: WEB, supabase: SB, cron: CRON }, entorno())
assert.deepEqual(malos(r), ['purga: omitida'], 'con el secreto pero sin la clave pública se pide la clave y no se finge que se comprobó')
// Nunca salen claves
r = await verificar({ web: WEB, supabase: SB, anon: ANON, cron: CRON }, entorno({ secretoMalo: true, sinCors: 'baja' }))
const salida = JSON.stringify(r)
assert.ok(!salida.includes(CRON) && !salida.includes(ANON), 'los resultados no contienen ninguna clave')

// Fallos provocados: cada uno se detecta y con un mensaje que dice qué hacer
const casos: [string, Fallos, string, string][] = [
  ['falta el origen en una función', { sinCors: 'checkin-evento' }, 'cors: checkin-evento', 'ADN_ORIGENES_EXTRA'],
  ['una función pública se desplegó con JWT', { baja401: true }, 'sin JWT: baja', 'sin verificarlo'],
  ['una función no está desplegada', { sinFuncion: 'confirmar-suscripcion' }, 'sin JWT: confirmar-suscripcion', 'no está desplegada'],
  ['la purga va atrasada', { atrasada: true }, 'purga: al día', 'la más atrasada 60 h'],
  ['el secreto no coincide', { secretoMalo: true }, 'purga: la tarea puede consultar el estado', 'ADN_CRON_SECRET'],
  ['la vía de la tarea acepta cualquier clave', { tareaAbierta: true }, 'tarea: plataforma cerrada a una clave falsa', ''],
  ['la salud falla', { sinSalud: true }, 'web: ruta de salud', 'VITE_SUPABASE_URL'],
  ['la web se puede indexar', { sinNoindex: true }, 'web: no se indexa', ''],
  ['una función con JWT no lo exige', { sinJwtEnDar: true }, 'con JWT: dar-publico rechaza sin clave', ''],
]
for (const [que, fallos, nombre, texto] of casos) {
  const x = por(await verificar({ web: WEB, supabase: SB, anon: ANON, cron: CRON }, entorno(fallos)), nombre)
  assert.ok(x && !x.ok, `se detecta: ${que}`)
  assert.ok(x!.detalle.includes(texto), `y el mensaje orienta: ${que} (${x!.detalle})`)
}
// Un fallo no oculta lo demás: solo falla lo afectado
const uno = await verificar({ web: WEB, supabase: SB, anon: ANON, cron: CRON }, entorno({ sinCors: 'baja' }))
assert.deepEqual(malos(uno), ['cors: baja'], 'un fallo no arrastra a los demás')
// La red caída no lanza excepciones ni filtra detalles
r = await verificar({ web: WEB, supabase: SB, anon: ANON, cron: CRON }, entorno({ red: true }))
assert.ok(r.length > 10 && r.every(x => !x.ok), 'sin red falla todo, sin excepciones')
assert.ok(!JSON.stringify(r).includes('detalles internos'), 'y sin detalles internos')
// Direcciones rechazadas antes de hacer ninguna petición
let llamadas = 0; const contador = (async () => { llamadas++; return new Response('x') }) as typeof fetch
for (const mala of ['http://x.dev', 'https://x.dev/ruta', 'https://u@x.dev', 'javascript:1', '']) {
  assert.equal((await verificar({ web: mala, supabase: SB }, contador))[0]!.ok, false, `se rechaza la web ${mala}`)
  assert.equal((await verificar({ web: WEB, supabase: mala }, contador))[0]!.ok, false, `se rechaza el proyecto ${mala}`)
}
assert.equal(llamadas, 0, 'y no se hizo ninguna petición')
console.log('OK: verificador de entornos')
