// Pruebas de la ruta de salud (api/salud.ts) con un servicio de Auth simulado. Uso: npm run test:salud
import assert from 'node:assert/strict'
const { comprobarSalud, default: handler } = await import('../api/salud.ts')

const URL_OK = 'https://ejemplo.supabase.test'
const vivo = async () => ({ ok: true })
const caido = async () => ({ ok: false })
const roto = async () => { throw new Error('ECONNREFUSED con detalles internos') }

// Comprobación
assert.deepEqual(await comprobarSalud(URL_OK, 'k', vivo), { ok: true }, 'el servicio contesta: ok')
assert.deepEqual(await comprobarSalud(URL_OK + '/', 'k', vivo), { ok: true }, 'una barra final no importa')
assert.deepEqual(await comprobarSalud(URL_OK, 'k', caido), { ok: false }, 'el servicio contesta con error: no ok')
assert.deepEqual(await comprobarSalud(URL_OK, 'k', roto), { ok: false }, 'la conexión falla: no ok, y sin detalles')
assert.deepEqual(await comprobarSalud(undefined, 'k', vivo), { ok: false }, 'sin dirección configurada: no ok')
assert.deepEqual(await comprobarSalud(URL_OK, undefined, vivo), { ok: false }, 'sin clave configurada: no ok')
for (const mala of ['http://ejemplo.test', 'ftp://x.test', 'https://x.test/ruta?q=1', 'javascript:alert(1)', 'https://user@x.test']) {
  assert.deepEqual(await comprobarSalud(mala, 'k', vivo), { ok: false }, `una dirección rara no se consulta: ${mala}`)
}
// Tiempo máximo: un servicio que no contesta no cuelga la ruta
const t0 = Date.now()
const colgado = (_u: string, i: { signal: AbortSignal }) => new Promise<{ ok: boolean }>((_r, rechazar) => i.signal.addEventListener('abort', () => rechazar(new Error('abortado'))))
assert.deepEqual(await comprobarSalud(URL_OK, 'k', colgado, 50), { ok: false }, 'un servicio que no contesta da no ok')
assert.ok(Date.now() - t0 < 1000, 'y lo hace dentro del plazo')
// La clave solo viaja al servicio de Auth y no sale en la respuesta
let cabeceras: Record<string, string> = {}; let direccion = ''
await comprobarSalud(URL_OK, 'clave-secreta', async (u, i) => { direccion = u; cabeceras = i.headers; return { ok: true } })
assert.equal(direccion, `${URL_OK}/auth/v1/health`)
assert.equal(cabeceras.apikey, 'clave-secreta')

// Manejador: respuesta mínima
function simular(metodo: string, entorno: Record<string, string | undefined>, servicio: 'vivo' | 'caido' | 'roto') {
  const previo = { ...process.env }; Object.assign(process.env, entorno)
  for (const k of ['VITE_SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY']) if (entorno[k] === undefined) delete process.env[k]
  const f = globalThis.fetch
  globalThis.fetch = (async () => { if (servicio === 'roto') throw new Error('detalle interno'); return { ok: servicio === 'vivo' } }) as unknown as typeof fetch
  const salida = { estado: 0, cuerpo: undefined as string | undefined, cab: {} as Record<string, string> }
  const res = {
    setHeader(n: string, v: string) { salida.cab[n.toLowerCase()] = v },
    status(c: number) { salida.estado = c; return res },
    end(c?: string) { salida.cuerpo = c },
  }
  return handler({ method: metodo }, res).then(() => { globalThis.fetch = f; process.env = previo as NodeJS.ProcessEnv; return salida })
}
const entorno = { VITE_SUPABASE_URL: URL_OK, VITE_SUPABASE_ANON_KEY: 'clave-secreta' }
let r = await simular('GET', entorno, 'vivo')
assert.equal(r.estado, 200); assert.equal(r.cuerpo, '{"ok":true}')
assert.match(r.cab['cache-control']!, /s-maxage=30/, 'la plataforma lo guarda 30 segundos')
assert.match(r.cab['content-type']!, /application\/json/)
r = await simular('GET', entorno, 'caido')
assert.equal(r.estado, 503); assert.equal(r.cuerpo, '{"ok":false}')
r = await simular('GET', entorno, 'roto')
assert.equal(r.estado, 503); assert.equal(r.cuerpo, '{"ok":false}'); assert.ok(!/detalle|ECONN|clave/.test(r.cuerpo!), 'no filtra el motivo del fallo')
r = await simular('GET', { VITE_SUPABASE_URL: undefined, VITE_SUPABASE_ANON_KEY: undefined }, 'vivo')
assert.equal(r.estado, 503, 'sin configuración no se da por sano')
r = await simular('HEAD', entorno, 'vivo')
assert.equal(r.estado, 200); assert.equal(r.cuerpo, undefined, 'HEAD no lleva cuerpo')
for (const m of ['POST', 'PUT', 'DELETE', 'PATCH']) {
  r = await simular(m, entorno, 'vivo')
  assert.equal(r.estado, 405, `${m} no se admite`); assert.equal(r.cab['allow'], 'GET, HEAD')
}
for (const cuerpo of ['{"ok":true}', '{"ok":false}']) assert.deepEqual(Object.keys(JSON.parse(cuerpo)), ['ok'], 'solo un campo')
console.log('OK: todas las pruebas de la ruta de salud pasan')
