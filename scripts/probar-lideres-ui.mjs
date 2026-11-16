// Prueba de las pantallas de zonas y casas (líderes y asignación de personas) en un navegador real, con la red simulada.
// Uso: npm run test:lideres-ui   (levanta Vite en el puerto 5196 con una dirección de Supabase inventada y la intercepta)
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5196
const SB = 'https://fake.supabase.test'
const IG = '11111111-1111-1111-1111-111111111111'
const USR = '22222222-2222-2222-2222-222222222222'
const LZ = '33333333-3333-3333-3333-333333333333'
const LC = '44444444-4444-4444-4444-444444444444'
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

const PERMISOS = {
  administrador: ['zonas.ver', 'zonas.gestionar', 'casas.ver', 'casas.crear', 'casas.editar', 'miembros.ver', 'miembros.editar', 'usuarios.ver'],
  lider_zona: ['zonas.ver', 'casas.ver_zona', 'miembros.ver_zona'],
  lider_casa: ['casas.ver_propia', 'miembros.ver_asignados', 'zonas.ver'],
}
const catalogo = [...new Set(Object.values(PERMISOS).flat())]
const modulo = c => c.split('.')[0]

async function escenario(rol, { sinCandidatos = false, patchFalla = false } = {}) {
  const e = { patches: [], posts: [] }
  e.zonas = [{ id: 'z1', codigo: 'NORTE', nombre: 'Zona Norte', lider_id: null, activa: true }]
  e.casas = [
    { id: 'c1', nombre: 'Casa Uno', codigo_zona: 'ZN-000001', zona_id: 'z1', lider_id: LC, ciudad: 'Sevilla', pais: 'ES', direccion: 'Calle 1', activa: true, count_miembros: [{ count: 1 }], lider_perfil: { nombre: 'Casa', apellido: 'Lider' } },
    { id: 'c2', nombre: 'Casa Dos', codigo_zona: 'ZN-000002', zona_id: null, lider_id: null, ciudad: 'Sevilla', pais: 'ES', direccion: 'Calle 2', activa: true, count_miembros: [{ count: 0 }], lider_perfil: null },
  ]
  e.miembros = [
    { id: 'm1', nombre: 'Ana', apellido: 'Uno', crm_id: 'ADN-001', casa_oracion_id: 'c1', activo: true },
    { id: 'm2', nombre: 'Beto', apellido: 'Dos', crm_id: 'ADN-002', casa_oracion_id: null, activo: true },
    { id: 'm3', nombre: 'Cleo', apellido: 'Tres', crm_id: 'ADN-003', casa_oracion_id: null, activo: true },
  ]
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ locale: 'es-ES', viewport: { width: 1280, height: 900 } })
  const sesion = { access_token: 'x.y.z', refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: USR, aud: 'authenticated', email: 'p@prueba.test', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } }
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  const perfilesTodos = [
    { id: USR, iglesia_id: IG, nombre: 'Yo', apellido: 'Mismo', email: 'p@prueba.test', rol, activo: true },
    ...(sinCandidatos ? [] : [{ id: LZ, iglesia_id: IG, nombre: 'Zona', apellido: 'Lider', rol: 'lider_zona', activo: true }]),
    ...(sinCandidatos ? [] : [{ id: LC, iglesia_id: IG, nombre: 'Casa', apellido: 'Lider', rol: 'lider_casa', activo: true }]),
    { id: '55555555-5555-5555-5555-555555555555', iglesia_id: IG, nombre: 'Solo', apellido: 'Miembro', rol: 'miembro', activo: true },
  ]
  const rolesTodos = [rol, ...['lider_zona', 'lider_casa', 'miembro'].filter(c => c !== rol)].map(clave => ({ clave, nombre: clave, es_propietario: false, rol_permisos: (PERMISOS[clave] ?? ['eventos.ver']).map(permiso => ({ permiso })) }))
  const tablas = () => ({
    perfiles: perfilesTodos, iglesias: [{ id: IG, nombre: 'Iglesia de Prueba', slug: 'prueba', activa: true, plan: 'premium', etapa: 'activa', pais: 'España' }],
    roles: rolesTodos, plan_modulos: [{ modulo: 'zonas' }, { modulo: 'casas' }, { modulo: 'miembros' }, { modulo: 'usuarios' }], iglesia_modulos: [],
    permisos: catalogo.map(clave => ({ clave, modulo: modulo(clave) })), plataforma_admins: [],
    zonas: e.zonas, casas_oracion: e.casas, miembros: e.miembros, consolidaciones: [],
  })
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const url = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
    if (!url.pathname.startsWith('/rest/v1/')) return json(200, [])
    const tabla = url.pathname.split('/').pop()
    const id = (url.searchParams.get('id') ?? '').replace('eq.', '')
    if (req.method() === 'PATCH') {
      const cuerpo = req.postDataJSON(); e.patches.push({ tabla, id, cuerpo })
      if (patchFalla) return json(403, { message: 'sin permiso' })
      const fila = (tablas()[tabla] ?? []).find(f => f.id === id); if (fila) Object.assign(fila, cuerpo)
      return ruta.fulfill({ status: 204, headers: cors })
    }
    if (req.method() === 'POST') {
      const cuerpo = req.postDataJSON(); e.posts.push({ tabla, cuerpo })
      if (tabla === 'zonas') e.zonas.push({ id: 'z' + (e.zonas.length + 1), lider_id: null, activa: true, ...cuerpo })
      return ruta.fulfill({ status: 201, headers: cors })
    }
    let filas = tablas()[tabla] ?? []
    for (const [k, v] of url.searchParams) {
      if (v.startsWith('eq.') && filas.some(f => k in f)) filas = filas.filter(f => String(f[k]) === v.slice(3))
      if (v === 'is.null') filas = filas.filter(f => f[k] === null || f[k] === undefined)
    }
    const objeto = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object')
    return json(200, objeto ? (filas[0] ?? null) : filas)
  })
  const page = await ctx.newPage()
  const errores = []
  page.on('pageerror', x => errores.push(x.message))
  return { browser, page, e, errores }
}
const url = r => `http://localhost:${PUERTO}${r}`
let fallos = 0
const prueba = async (n, fn) => { try { await fn(); console.log(`✓ ${n}`) } catch (x) { fallos++; console.error(`✗ ${n}\n   ${x.message}`) } }

try {
  await prueba('el administrador crea zonas (código normalizado y validado) y nombra al líder entre los candidatos', async () => {
    const { browser, page, e, errores } = await escenario('administrador')
    await page.goto(url('/zonas')); await page.waitForSelector('[data-zona=z1]')
    // código inválido: no llama al servidor
    await page.fill('[data-test=zona-codigo]', 'N'); await page.fill('[data-test=zona-nombre]', 'Zona Sur'); await page.click('[data-test=zona-crear]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('2 a 10'))
    assert.equal(e.posts.length, 0)
    // código válido, escrito en minúsculas y con símbolos
    await page.fill('[data-test=zona-codigo]', ' zona-sur '); await page.click('[data-test=zona-crear]')
    await page.waitForSelector('[data-zona=z2]')
    assert.deepEqual(e.posts[0].cuerpo, { codigo: 'ZONASUR', nombre: 'Zona Sur' })
    // candidatos: líder de zona sí; líder de casa y miembro, no
    const opciones = await page.locator('[data-zona=z1] [data-test=zona-lider] option').allTextContents()
    assert.ok(opciones.some(o => /Zona Lider/.test(o))); assert.ok(!opciones.some(o => /Casa Lider|Solo Miembro/.test(o)))
    await page.selectOption('[data-zona=z1] [data-test=zona-lider]', LZ)
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Líder de zona actualizado'))
    assert.deepEqual({ id: e.patches[0].id, c: e.patches[0].cuerpo }, { id: 'z1', c: { lider_id: LZ } })
    assert.match(await page.textContent('[data-zona=z1]'), /1 casa/, 'cuenta las casas de la zona')
    assert.match(await page.textContent('[data-test=casas-sin-zona]'), /1 casa sin zona/)
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('sin nadie con el rol de líder de zona, la pantalla lo explica; y se puede desactivar una zona', async () => {
    const { browser, page, e } = await escenario('administrador', { sinCandidatos: true })
    await page.goto(url('/zonas')); await page.waitForSelector('[data-test=sin-candidatos]')
    await page.click('[data-zona=z1] [data-test=zona-activa]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Zona desactivada'))
    assert.deepEqual(e.patches[0].cuerpo, { activa: false })
    await browser.close()
  })

  await prueba('un líder de zona ve las zonas pero no puede crear ni cambiar nada', async () => {
    const { browser, page } = await escenario('lider_zona')
    await page.goto(url('/zonas')); await page.waitForSelector('[data-zona=z1]')
    for (const sel of ['[data-test=form-zona]', '[data-test=zona-lider]', '[data-test=zona-activa]']) assert.equal(await page.locator(sel).count(), 0, sel)
    await browser.close()
  })

  await prueba('en la casa: zona, líder candidato y personas (añadir y quitar), con los cambios exactos', async () => {
    const { browser, page, e, errores } = await escenario('administrador')
    await page.goto(url('/casas')); await page.waitForSelector('[data-casa=c2]')
    assert.equal(await page.locator('[data-casa=c2] [data-test=sin-lider]').count(), 1)
    assert.equal(await page.locator('[data-casa=c2] [data-test=sin-zona]').count(), 1)
    assert.equal(await page.locator('[data-casa=c1] [data-test=sin-zona]').count(), 0)
    await page.click('[data-casa=c2]'); await page.waitForSelector('[data-test=liderazgo]')
    assert.equal(await page.evaluate(() => document.activeElement?.getAttribute('data-test')), 'detalle-casa', 'el foco entra en el diálogo')
    await page.selectOption('[data-test=casa-zona]', 'z1')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Zona de la casa actualizada'))
    const opciones = await page.locator('[data-test=casa-lider] option').allTextContents()
    assert.ok(opciones.some(o => /Casa Lider/.test(o))); assert.ok(!opciones.some(o => /Zona Lider|Solo Miembro/.test(o)), 'solo roles que ven su casa')
    await page.selectOption('[data-test=casa-lider]', LC)
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Líder de la casa actualizado'))
    assert.deepEqual(e.patches.map(p => [p.tabla, p.id, p.cuerpo]), [['casas_oracion', 'c2', { zona_id: 'z1' }], ['casas_oracion', 'c2', { lider_id: LC }]])
    // añadir personas sin casa, con búsqueda
    assert.equal(await page.locator('[data-test=sin-casa-fila]').count(), 2)
    await page.fill('[data-test=buscar-persona]', 'beto')
    assert.equal(await page.locator('[data-test=sin-casa-fila]').count(), 1)
    await page.click('[data-test=sin-casa-fila] [data-test=anadir]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Beto Dos ya está en esta casa'))
    assert.deepEqual(e.patches.at(-1), { tabla: 'miembros', id: 'm2', cuerpo: { casa_oracion_id: 'c2' } })
    // quitar
    await page.click('[data-test=quitar-persona]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Beto Dos ya no está en esta casa'))
    assert.deepEqual(e.patches.at(-1), { tabla: 'miembros', id: 'm2', cuerpo: { casa_oracion_id: null } })
    await page.press('[data-test=detalle-casa]', 'Escape')
    await page.waitForFunction(() => !document.querySelector('[data-test=detalle-casa]'))
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('si el servidor rechaza el cambio, se ve el error y no se da por hecho', async () => {
    const { browser, page } = await escenario('administrador', { patchFalla: true })
    await page.goto(url('/casas')); await page.waitForSelector('[data-casa=c2]')
    await page.click('[data-casa=c2]'); await page.waitForSelector('[data-test=casa-zona]')
    await page.selectOption('[data-test=casa-zona]', 'z1')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('No se pudo guardar'))
    assert.equal(await page.locator('[data-test=aviso]').first().getAttribute('class').then(c => /red/.test(c)), true)
    await browser.close()
  })

  await prueba('el líder de casa solo mira: sin editar zona ni líder, sin añadir ni quitar personas', async () => {
    const { browser, page } = await escenario('lider_casa')
    await page.goto(url('/casas')); await page.waitForSelector('[data-casa=c1]')
    assert.equal(await page.locator('[data-test=nueva-casa]').count(), 0)
    await page.click('[data-casa=c1]'); await page.waitForSelector('[data-test=detalle-casa]')
    for (const sel of ['[data-test=liderazgo]', '[data-test=anadir-persona]', '[data-test=quitar-persona]']) assert.equal(await page.locator(sel).count(), 0, sel)
    await browser.close()
  })
} finally { parar() }

if (fallos) { console.error(`\n${fallos} prueba(s) fallida(s)`); process.exit(1) }
console.log('\nLíderes: todas las pruebas de interfaz pasan')
