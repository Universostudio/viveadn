// Prueba del menú por permisos, la pantalla de «sin acceso», el aterrizaje por rol y «Mi panel» del líder de casa, en un navegador real con la red simulada.
// Uso: npm run test:acceso-ui   (levanta Vite en el puerto 5195 con una dirección de Supabase inventada y la intercepta)
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5195
const SB = 'https://fake.supabase.test'
const IG = '11111111-1111-1111-1111-111111111111'
const USR = '22222222-2222-2222-2222-222222222222'
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

const PERMISOS = {
  administrador: ['miembros.ver', 'casas.ver', 'zonas.gestionar', 'consolidacion.ver', 'reportes.ver', 'usuarios.gestionar', 'gamificacion.gestionar', 'eventos.ver'],
  lider_zona: ['zonas.ver', 'casas.ver_zona', 'miembros.ver_zona', 'consolidacion.ver_zona'],
  lider_casa: ['casas.ver_propia', 'miembros.ver_asignados', 'consolidacion.ver_casa', 'asistencia.registrar_propia'],
  miembro: ['eventos.ver'],
}
const catalogo = [...new Set(Object.values(PERMISOS).flat())]
const modulo = c => c.split('.')[0]
const hoy = (() => { const d = new Date(); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10) })()

async function escenario(rol, { postFalla = false, asistenciasHoy = [], vencida = false } = {}) {
  const e = { patches: [], posts: [] }
  const casas = [{ id: 'c1', nombre: 'Casa Uno', codigo_zona: 'ZN-000001', direccion: 'Calle 1', ciudad: 'Sevilla', activa: true }]
  const miembros = [
    { id: 'm1', nombre: 'Ana', apellido: 'Uno', telefono: '+34600111222', casa_oracion_id: 'c1', activo: true },
    { id: 'm2', nombre: 'Beto', apellido: 'Dos', telefono: null, casa_oracion_id: 'c1', activo: true },
  ]
  const asistencias = asistenciasHoy.map(a => ({ casa_oracion_id: 'c1', fecha: hoy, ...a }))
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ locale: 'es-ES', viewport: { width: 1280, height: 900 } })
  const sesion = { access_token: 'x.y.z', refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: USR, aud: 'authenticated', email: 'p@prueba.test', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } }
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  const tablas = () => ({
    perfiles: [{ id: USR, iglesia_id: IG, nombre: 'Yo', apellido: 'Mismo', email: 'p@prueba.test', rol, activo: true }],
    iglesias: [{ id: IG, nombre: 'Iglesia de Prueba', slug: 'prueba', activa: true, plan: 'premium', etapa: vencida ? 'prueba' : 'activa', prueba_hasta: vencida ? '2026-01-01T00:00:00Z' : null, pais: 'España' }],
    roles: Object.keys(PERMISOS).map(clave => ({ clave, nombre: clave, es_propietario: false, rol_permisos: PERMISOS[clave].map(permiso => ({ permiso })) })),
    plan_modulos: [...new Set(catalogo.map(modulo))].map(m => ({ modulo: m })), iglesia_modulos: [],
    permisos: catalogo.map(clave => ({ clave, modulo: modulo(clave) })), plataforma_admins: [],
    modulos: [{ clave: 'miembros', tipo: 'nucleo' }, { clave: 'casas', tipo: 'nucleo' }, { clave: 'zonas', tipo: 'nucleo' }, { clave: 'consolidacion', tipo: 'nucleo' }, { clave: 'asistencia', tipo: 'nucleo' }, { clave: 'usuarios', tipo: 'nucleo' }, { clave: 'reportes', tipo: 'incluido' }, { clave: 'eventos', tipo: 'incluido' }, { clave: 'gamificacion', tipo: 'incluido' }],
    casas_oracion: casas, miembros, consolidaciones: [], asistencias,
  })
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const url = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
    if (!url.pathname.startsWith('/rest/v1/')) return json(200, [])
    const tabla = url.pathname.split('/').pop()
    // Esta prueba es de un entorno sin las tablas del soporte (migración 350000 aún sin aplicar): el menú no ofrece Novedades ni Soporte
    if (tabla === 'adn_novedades') return json(404, { message: 'relation does not exist', code: '42P01' })
    if (req.method() === 'PATCH') {
      const id = (url.searchParams.get('id') ?? '').replace('eq.', '')
      e.patches.push({ tabla, id, cuerpo: req.postDataJSON() })
      if (postFalla) return json(403, { message: 'sin permiso' })
      return ruta.fulfill({ status: 204, headers: cors })
    }
    if (req.method() === 'POST') {
      e.posts.push({ tabla, cuerpo: req.postDataJSON() })
      if (postFalla) return json(403, { message: 'sin permiso' })
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
const enlacesMenu = page => page.locator('aside nav a').evaluateAll(as => as.map(a => new URL(a.href).pathname).filter(r => !['/privacidad', '/terminos', '/aviso-legal', '/cookies'].includes(r)))
let fallos = 0
const prueba = async (n, fn) => { try { await fn(); console.log(`✓ ${n}`) } catch (x) { fallos++; console.error(`✗ ${n}\n   ${x.message}`) } }

try {
  await prueba('el menú muestra a cada rol solo lo que puede abrir, y «Mi panel» solo al líder de casa', async () => {
    const esperado = {
      administrador: ['/', '/miembros', '/eventos', '/casas', '/zonas', '/consolidacion', '/logros', '/reportes', '/configuracion'],
      lider_zona: ['/', '/miembros', '/casas', '/zonas', '/consolidacion'],
      lider_casa: ['/mi-panel', '/', '/miembros', '/casas', '/consolidacion'],
      miembro: ['/', '/eventos'],
    }
    for (const [rol, rutas] of Object.entries(esperado)) {
      const { browser, page, errores } = await escenario(rol)
      await page.goto(url('/')); await page.waitForSelector('aside nav a')
      assert.deepEqual(await enlacesMenu(page), rutas, rol)
      assert.deepEqual(errores, [], rol)
      await browser.close()
    }
  })

  await prueba('prueba vencida: aviso de solo lectura, el núcleo se ve y lo demás se cierra', async () => {
    const { browser, page, errores } = await escenario('administrador', { vencida: true })
    await page.goto(url('/')); await page.waitForSelector('aside nav a')
    assert.equal(await page.locator('[data-test=aviso-solo-lectura]').count(), 1)
    assert.match(await page.textContent('[data-test=aviso-solo-lectura]'), /Tu prueba terminó/)
    // Solo módulos del núcleo y solo con permiso de lectura: no hay reportes, eventos ni configuración
    assert.deepEqual(await enlacesMenu(page), ['/', '/miembros', '/casas', '/consolidacion'])
    assert.deepEqual(errores, [])
    await browser.close()
    const normal = await escenario('administrador')
    await normal.page.goto(url('/')); await normal.page.waitForSelector('aside nav a')
    assert.equal(await normal.page.locator('[data-test=aviso-solo-lectura]').count(), 0, 'sin prueba vencida no hay aviso')
    await normal.browser.close()
  })

  await prueba('abrir escribiendo la dirección una sección sin permiso lleva a «sin acceso», y desde ahí se vuelve a la portada del rol', async () => {
    const { browser, page, errores } = await escenario('lider_casa')
    await page.goto(url('/configuracion')); await page.waitForSelector('[data-test=sin-acceso]')
    assert.equal(new URL(page.url()).pathname, '/sin-acceso')
    assert.equal(new URL(page.url()).searchParams.get('desde'), '/configuracion')
    assert.match(await page.textContent('[data-test=sin-acceso]'), /No tienes acceso/)
    await page.click('[data-test=sin-acceso-inicio]'); await page.waitForSelector('[data-test=mi-casa], [data-test=sin-casa]')
    assert.equal(new URL(page.url()).pathname, '/mi-panel')
    assert.deepEqual(errores, [])
    await browser.close()

    // el administrador tampoco ve «Mi panel», que es del líder de casa
    const a = await escenario('administrador')
    await a.page.goto(url('/mi-panel')); await a.page.waitForSelector('[data-test=sin-acceso]')
    assert.equal(new URL(a.page.url()).pathname, '/sin-acceso')
    await a.browser.close()

    // y quien sí puede, entra
    const z = await escenario('lider_zona')
    await z.page.goto(url('/zonas')); await z.page.waitForSelector('aside nav a')
    assert.equal(new URL(z.page.url()).pathname, '/zonas')
    await z.browser.close()
  })

  await prueba('cada rol aterriza en su portada al iniciar sesión', async () => {
    for (const [rol, destino] of [['lider_casa', '/mi-panel'], ['administrador', '/'], ['lider_zona', '/']]) {
      const { browser, page } = await escenario(rol)
      await page.goto(url('/login')); await page.waitForSelector('aside nav a')
      assert.equal(new URL(page.url()).pathname, destino, rol)
      await browser.close()
    }
  })

  await prueba('«Mi panel»: mi casa, mis personas con llamar y WhatsApp, y pasar lista que crea las filas de asistencia', async () => {
    const { browser, page, e, errores } = await escenario('lider_casa')
    await page.goto(url('/mi-panel')); await page.waitForSelector('[data-test=mi-casa]')
    assert.match(await page.textContent('[data-test=mi-casa]'), /Casa Uno/)
    assert.match(await page.textContent('[data-test=n-personas]'), /2 personas/)
    assert.equal(await page.locator('[data-gente=m1] [data-test=llamar]').getAttribute('href'), 'tel:+34600111222')
    assert.match(await page.locator('[data-gente=m1] [data-test=whatsapp]').getAttribute('href'), /^https:\/\/wa\.me\/34600111222/)
    assert.equal(await page.locator('[data-gente=m2] [data-test=llamar]').count(), 0, 'sin teléfono no hay enlace')
    // pasar lista: viene Ana, no Beto
    await page.check('[data-persona=m1]')
    assert.match(await page.textContent('[data-test=presentes]'), /1 de 2 presentes/)
    await page.click('[data-test=guardar-lista]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Lista guardada'))
    assert.deepEqual(e.posts.map(p => [p.tabla, p.cuerpo]), [['asistencias', [
      { casa_oracion_id: 'c1', miembro_id: 'm1', fecha: hoy, presente: true },
      { casa_oracion_id: 'c1', miembro_id: 'm2', fecha: hoy, presente: false },
    ]]])
    assert.equal(e.patches.length, 0)
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('pasar lista otra vez el mismo día actualiza lo guardado y no duplica filas', async () => {
    const { browser, page, e } = await escenario('lider_casa', { asistenciasHoy: [{ id: 'a1', miembro_id: 'm1', presente: true }, { id: 'a2', miembro_id: 'm2', presente: false }] })
    await page.goto(url('/mi-panel')); await page.waitForSelector('[data-persona=m1]')
    assert.equal(await page.locator('[data-persona=m1]').isChecked(), true, 'recuerda quién vino')
    await page.uncheck('[data-persona=m1]'); await page.check('[data-persona=m2]')
    await page.click('[data-test=guardar-lista]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Lista guardada'))
    assert.equal(e.posts.length, 0, 'no inserta de nuevo')
    assert.deepEqual(e.patches.map(p => [p.tabla, p.id, p.cuerpo]), [['asistencias', 'a1', { presente: false }], ['asistencias', 'a2', { presente: true }]])
    await browser.close()
  })

  await prueba('si el servidor rechaza la lista, se ve el error en rojo y no se da por guardada', async () => {
    const { browser, page } = await escenario('lider_casa', { postFalla: true })
    await page.goto(url('/mi-panel')); await page.waitForSelector('[data-persona=m1]')
    await page.check('[data-persona=m1]'); await page.click('[data-test=guardar-lista]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('No se pudo guardar'))
    assert.match(await page.locator('[data-test=aviso]').getAttribute('class'), /red/)
    await browser.close()
  })
} finally { parar() }

if (fallos) { console.error(`\n${fallos} prueba(s) fallida(s)`); process.exit(1) }
console.log('\nAcceso: todas las pruebas de interfaz pasan')
