// Prueba del panel de inicio honesto en un navegador real, con la red simulada: tarjetas por rol, alertas contadas sobre el total y datos que no cargan.
// Uso: npm run test:inicio-ui   (levanta Vite en el puerto 5192 con una dirección de Supabase inventada y la intercepta)
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5192
const SB = 'https://fake.supabase.test'
const IG = '11111111-1111-1111-1111-111111111111'
const USR = '22222222-2222-2222-2222-222222222222'
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

const PERMISOS = {
  administrador: ['miembros.ver', 'miembros.crear', 'casas.ver', 'consolidacion.ver', 'eventos.ver'],
  lider_casa: ['casas.ver_propia', 'miembros.ver_asignados', 'consolidacion.ver_casa', 'eventos.ver'],
  miembro: ['eventos.ver'],
}
const catalogo = [...new Set(Object.values(PERMISOS).flat())]
const modulo = c => c.split('.')[0]
const horas = h => new Date(Date.now() - h * 3_600_000).toISOString()

const METODOS = [
  { id: '5e000000-0000-4000-8000-000000000072', plazo_horas: 72, umbral_amarillo_horas: 24, umbral_naranja_horas: 48 },
  { id: '5e000000-0000-4000-8000-000000000001', plazo_horas: 168, umbral_amarillo_horas: 72, umbral_naranja_horas: 120 },
]
const OP72 = METODOS[0].id
const colorDe = (c) => { const m = METODOS.find(x => x.id === (c.metodo_id ?? OP72)); const h = (Date.now() - Date.parse(c.fecha_conversion)) / 3_600_000; return c.completado ? 'verde' : h <= m.umbral_amarillo_horas ? 'verde' : h <= m.umbral_naranja_horas ? 'amarillo' : h <= m.plazo_horas ? 'naranja' : 'rojo' }

// conMetodos: la base ya tiene los métodos (migración aplicada); sin ellos la tabla no existe y la interfaz debe seguir como siempre.
// extraSimple: dos procesos más con el método Seguimiento simple (a 100 horas es amarillo y a 200 es rojo).
async function escenario(rol, { consolidacionesFalla = false, conMetodos = true, extraSimple = false } = {}) {
  const e = { falla: consolidacionesFalla, consultas: [] }
  // 8 rojas (más de 72 h), 3 naranjas (entre 48 y 72 h), 2 verdes: 13 en seguimiento, 8 críticas, 11 en alerta
  const consolidaciones = [
    ...Array.from({ length: 8 }, (_, i) => ({ id: 'r' + i, completado: false, fecha_conversion: horas(100 + i), miembros: { nombre: 'Roja' + i, apellido: 'X' } })),
    ...Array.from({ length: 3 }, (_, i) => ({ id: 'n' + i, completado: false, fecha_conversion: horas(55 + i), miembros: { nombre: 'Naranja' + i, apellido: 'X' } })),
    ...Array.from({ length: 2 }, (_, i) => ({ id: 'v' + i, completado: false, fecha_conversion: horas(5 + i), miembros: { nombre: 'Verde' + i, apellido: 'X' } })),
  ]
  if (extraSimple) consolidaciones.push(
    { id: 's1', completado: false, fecha_conversion: horas(100), metodo_id: METODOS[1].id, miembros: { nombre: 'SimpleAmarilla', apellido: 'X' } },
    { id: 's2', completado: false, fecha_conversion: horas(200), metodo_id: METODOS[1].id, miembros: { nombre: 'SimpleRoja', apellido: 'X' } })
  const miembros = Array.from({ length: 7 }, (_, i) => ({ id: 'm' + i, nombre: 'Persona' + i, apellido: 'Y', crm_id: 'ADN-00' + i, nivel_compromiso: 'nuevo', activo: true, created_at: horas(i) }))
  const casas = [{ id: 'c1', activa: true }, { id: 'c2', activa: true }]
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ locale: 'es-ES', viewport: { width: 1280, height: 1100 } })
  const sesion = { access_token: 'x.y.z', refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: USR, aud: 'authenticated', email: 'p@prueba.test', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } }
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  const tablas = () => ({
    perfiles: [{ id: USR, iglesia_id: IG, nombre: 'Yo', apellido: 'Mismo', email: 'p@prueba.test', rol, activo: true }],
    iglesias: [{ id: IG, nombre: 'Iglesia de Prueba', slug: 'prueba', activa: true, plan: 'premium', etapa: 'activa', pais: 'España', modo_alias: false }],
    roles: Object.keys(PERMISOS).map(clave => ({ clave, nombre: clave, es_propietario: false, rol_permisos: PERMISOS[clave].map(permiso => ({ permiso })) })),
    plan_modulos: [...new Set(catalogo.map(modulo))].map(m => ({ modulo: m })), iglesia_modulos: [],
    permisos: catalogo.map(clave => ({ clave, modulo: modulo(clave) })), plataforma_admins: [],
    miembros, casas_oracion: casas, consolidaciones,
    adn_seguimiento_metodos: METODOS,
    adn_seguimiento_estado: consolidaciones.map(c => ({ id: c.id, completado: c.completado, fecha_conversion: c.fecha_conversion, metodo_id: c.metodo_id ?? OP72, estado: colorDe(c) })),
  })
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*', 'access-control-expose-headers': '*' }
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const url = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body, extra = {}) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json', ...extra }, body: JSON.stringify(body) })
    if (!url.pathname.startsWith('/rest/v1/')) return json(200, [])
    if (url.pathname.includes('/rpc/')) return json(200, null)
    const tabla = url.pathname.split('/').pop()
    e.consultas.push(tabla)
    if (tabla === 'adn_seguimiento_metodos' && !conMetodos) return json(404, { message: 'relation does not exist', code: '42P01' })
    if ((tabla === 'consolidaciones' || tabla === 'adn_seguimiento_estado') && e.falla) return json(500, { message: 'caído', code: 'XX000' })
    let filas = tablas()[tabla] ?? []
    for (const [k, v] of url.searchParams) {
      if (v.startsWith('eq.') && filas.some(f => k in f)) filas = filas.filter(f => String(f[k]) === v.slice(3))
      if (v.startsWith('lt.')) filas = filas.filter(f => String(f[k]) < v.slice(3))
      if (v.startsWith('in.(')) { const lista = v.slice(4, -1).split(','); filas = filas.filter(f => lista.includes(String(f[k]))) }
    }
    const limite = Number(url.searchParams.get('limit') ?? 0)
    const total = filas.length
    if (req.method() === 'HEAD') return ruta.fulfill({ status: 200, headers: { ...cors, 'content-range': `*/${total}` } })
    if (limite) filas = filas.slice(0, limite)
    const orden = url.searchParams.get('order') ?? ''
    if (orden.startsWith('fecha_conversion.asc')) filas = [...filas].sort((a, b) => a.fecha_conversion.localeCompare(b.fecha_conversion))
    if ((req.headers()['accept'] ?? '').includes('vnd.pgrst.object')) return json(200, filas[0] ?? null)
    return json(200, filas, { 'content-range': `0-${Math.max(0, filas.length - 1)}/${total}` })
  })
  const page = await ctx.newPage()
  const errores = []
  page.on('pageerror', x => errores.push(x.message))
  return { browser, page, e, errores }
}
const url = r => `http://localhost:${PUERTO}${r}`
const texto = (page, s) => page.locator(s).first().innerText()
let fallos = 0
const prueba = async (n, fn) => { try { await fn(); console.log(`✓ ${n}`) } catch (x) { fallos++; console.error(`✗ ${n}\n   ${x.message}`) } }

try {
  await prueba('administrador: las cifras salen del total (13 en seguimiento, 8 críticas), no de las 5 filas de la lista', async () => {
    const { browser, page, errores } = await escenario('administrador')
    await page.goto(url('/')); await page.waitForSelector('[data-test=alertas-72h]')
    await page.waitForFunction(() => document.querySelector('[data-test=stat-criticas]')?.textContent?.match(/\d/))
    assert.match(await texto(page, '[data-test=stat-personas]'), /^7\b/)
    assert.match(await texto(page, '[data-test=stat-casas]'), /^2\b/)
    assert.match(await texto(page, '[data-test=stat-seguimiento]'), /^13\b/)
    assert.match(await texto(page, '[data-test=stat-criticas]'), /^8\b/, 'críticas contadas sobre las 13, no sobre las 5 mostradas')
    assert.match(await texto(page, '[data-test=stat-seguimiento]'), /En consolidaci/i)
    assert.equal(await page.locator('[data-test=alertas-72h] [class*=alerta-]').count() <= 5, true, 'la lista muestra a lo sumo 5')
    assert.match(await texto(page, '[data-test=mostrando-alertas]'), /Mostrando 5 de 11 en alerta/)
    assert.equal(await page.locator('[data-test=nueva-persona]').count(), 1)
    assert.equal(await page.locator('[data-test=errores-carga]').count(), 0)
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('líder de casa: las tarjetas dicen que son lo suyo («a mi cargo», «Mis casas») y no hay botón de crear', async () => {
    const { browser, page } = await escenario('lider_casa')
    await page.goto(url('/mi-panel')); await page.goto(url('/')); await page.waitForSelector('[data-test=stat-personas]')
    assert.match(await texto(page, '[data-test=stat-personas]'), /Personas a mi cargo/)
    assert.match(await texto(page, '[data-test=stat-casas]'), /Mis casas/)
    assert.match(await texto(page, '[data-test=stat-seguimiento]'), /En seguimiento a mi cargo/)
    assert.match(await texto(page, '[data-test=stat-criticas]'), /Alertas críticas a mi cargo/)
    assert.equal(await page.locator('[data-test=nueva-persona]').count(), 0, 'sin permiso de crear no hay botón')
    await browser.close()
  })

  await prueba('miembro (solo eventos): no recibe estadísticas con ceros, ni alertas, ni personas recientes', async () => {
    const { browser, page, e } = await escenario('miembro')
    await page.goto(url('/')); await page.waitForSelector('h1')
    await page.waitForTimeout(800)
    for (const s of ['estadisticas', 'alertas-72h', 'recientes', 'nueva-persona']) assert.equal(await page.locator(`[data-test=${s}]`).count(), 0, s)
    assert.ok(!e.consultas.includes('consolidaciones') && !e.consultas.includes('miembros') && !e.consultas.includes('casas_oracion'), 'ni siquiera consulta lo que no va a mostrar: ' + e.consultas.join())
    await browser.close()
  })

  await prueba('si una lectura falla, la cifra es «—» (no 0), se avisa con un botón de reintentar y reintentar la recupera', async () => {
    const { browser, page, e } = await escenario('administrador', { consolidacionesFalla: true })
    await page.goto(url('/')); await page.waitForSelector('[data-test=errores-carga]')
    assert.match(await texto(page, '[data-test=errores-carga]'), /seguimiento/)
    for (const s of ['stat-seguimiento', 'stat-criticas']) assert.match(await texto(page, `[data-test=${s}]`), /^—/, s)
    assert.match(await texto(page, '[data-test=stat-personas]'), /^7\b/, 'lo que sí cargó se ve')
    assert.equal(await page.locator('[data-test=alertas-fallo]').count(), 1, 'la lista de alertas dice que falló, no «no hay alertas»')
    assert.equal(await page.locator('text=Todo al día').count() + await page.locator('text=No hay alertas').count(), 0)
    e.falla = false
    await page.click('[data-test=reintentar]')
    await page.waitForFunction(() => !document.querySelector('[data-test=errores-carga]'))
    assert.match(await texto(page, '[data-test=stat-criticas]'), /^8\b/)
    await browser.close()
  })

  // Con métodos de seguimiento en la base el panel cuenta con el color de cada proceso según su método; sin ellos, como siempre
  await prueba('con métodos en la base: críticas y en alerta salen del método de cada proceso (un Seguimiento simple a 100 horas es amarillo, no alerta)', async () => {
    const { browser, page, e, errores } = await escenario('administrador', { extraSimple: true })
    await page.goto(url('/')); await page.waitForSelector('[data-test=alertas-72h]')
    await page.waitForFunction(() => document.querySelector('[data-test=stat-criticas]')?.textContent?.match(/\d/))
    assert.match(await texto(page, '[data-test=stat-seguimiento]'), /^15\b/)
    assert.match(await texto(page, '[data-test=stat-criticas]'), /^9\b/, '8 de OP72 más la de Seguimiento simple a 200 h; la de 100 h no cuenta')
    assert.match(await texto(page, '[data-test=mostrando-alertas]'), /Mostrando 5 de 12 en alerta/, '11 de OP72 más la roja de Seguimiento simple (la amarilla no)')
    assert.ok(e.consultas.includes('adn_seguimiento_estado'), 'usa la vista de estado')
    assert.equal(await page.locator('text=SimpleAmarilla').count(), 0, 'la amarilla de Seguimiento simple no sale en la lista de alertas')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('sin métodos en la base (migración sin aplicar): el panel cuenta como siempre y no pide la vista de estado ni falla', async () => {
    const { browser, page, e, errores } = await escenario('administrador', { conMetodos: false })
    await page.goto(url('/')); await page.waitForSelector('[data-test=alertas-72h]')
    await page.waitForFunction(() => document.querySelector('[data-test=stat-criticas]')?.textContent?.match(/\d/))
    assert.match(await texto(page, '[data-test=stat-seguimiento]'), /^13\b/)
    assert.match(await texto(page, '[data-test=stat-criticas]'), /^8\b/)
    assert.match(await texto(page, '[data-test=mostrando-alertas]'), /Mostrando 5 de 11 en alerta/)
    assert.ok(!e.consultas.includes('adn_seguimiento_estado'), 'no pide una vista que no existe')
    assert.equal(await page.locator('[data-test=errores-carga]').count(), 0, 'sin avisos de error')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('con métodos y una lectura que falla: «—», aviso y reintentar también por la vista de estado', async () => {
    const { browser, page, e } = await escenario('administrador', { consolidacionesFalla: true })
    await page.goto(url('/')); await page.waitForSelector('[data-test=errores-carga]')
    for (const s of ['stat-seguimiento', 'stat-criticas']) assert.match(await texto(page, `[data-test=${s}]`), /^—/, s)
    e.falla = false
    await page.click('[data-test=reintentar]')
    await page.waitForFunction(() => !document.querySelector('[data-test=errores-carga]'))
    assert.match(await texto(page, '[data-test=stat-criticas]'), /^8\b/)
    await browser.close()
  })
} finally { parar() }

if (fallos) { console.error(`\n${fallos} prueba(s) fallida(s)`); process.exit(1) }
console.log('\nInicio: todas las pruebas de interfaz pasan')
