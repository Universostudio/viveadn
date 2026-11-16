// Prueba de la ficha editable de una persona en un navegador real, con la red simulada.
// Uso: npm run test:ficha-ui   (levanta Vite en el puerto 5193 con una dirección de Supabase inventada y la intercepta)
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5193
const SB = 'https://fake.supabase.test'
const IG = '11111111-1111-1111-1111-111111111111'
const USR = '22222222-2222-2222-2222-222222222222'
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

const PERMISOS = {
  administrador: ['miembros.ver', 'miembros.editar', 'casas.ver', 'comunicacion.ver'],
  lider_zona: ['miembros.ver_zona', 'casas.ver_zona'],
}
const catalogo = [...new Set(Object.values(PERMISOS).flat())]
const modulo = c => c.split('.')[0]

async function escenario(rol, { patchFalla = false, miembroFalla = null, consolidacionesFalla = false } = {}) {
  const e = { patches: [], estadoMiembro: miembroFalla }
  const miembro = { id: 'm1', iglesia_id: IG, crm_id: 'ADN-001', nombre: 'Ana', apellido: 'Uno', email: 'ana@x.test', telefono: '+34 600 111 222', fecha_nacimiento: '1990-05-17', nivel_compromiso: 'nuevo', casa_oracion_id: 'c1', notas: null, activo: true, puntos: 40, racha_dias: 2, created_at: '2026-01-02T10:00:00Z', casas_oracion: { nombre: 'Casa Uno', codigo_zona: 'ZN-000001' } }
  const casas = [{ id: 'c1', nombre: 'Casa Uno', codigo_zona: 'ZN-000001', activa: true }, { id: 'c2', nombre: 'Casa Dos', codigo_zona: 'ZN-000002', activa: true }]
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ locale: 'es-ES', viewport: { width: 1280, height: 1000 } })
  const sesion = { access_token: 'x.y.z', refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: USR, aud: 'authenticated', email: 'p@prueba.test', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } }
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  const tablas = () => ({
    perfiles: [{ id: USR, iglesia_id: IG, nombre: 'Yo', apellido: 'Mismo', email: 'p@prueba.test', rol, activo: true }],
    iglesias: [{ id: IG, nombre: 'Iglesia de Prueba', slug: 'prueba', activa: true, plan: 'premium', etapa: 'activa', pais: 'España', modo_alias: false }],
    roles: Object.keys(PERMISOS).map(clave => ({ clave, nombre: clave, es_propietario: false, rol_permisos: PERMISOS[clave].map(permiso => ({ permiso })) })),
    plan_modulos: [...new Set(catalogo.map(modulo))].map(m => ({ modulo: m })), iglesia_modulos: [],
    permisos: catalogo.map(clave => ({ clave, modulo: modulo(clave) })), plataforma_admins: [],
    miembros: [miembro], casas_oracion: casas, consolidaciones: [], progreso_formacion: [], logros: [], adn_miembro_contactos: [],
  })
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*', 'access-control-expose-headers': '*' }
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const url = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
    if (!url.pathname.startsWith('/rest/v1/')) return json(200, [])
    if (url.pathname.includes('/rpc/')) return json(200, null)
    const tabla = url.pathname.split('/').pop()
    if (req.method() === 'PATCH') {
      const cuerpo = req.postDataJSON(); e.patches.push({ tabla, cuerpo })
      if (patchFalla) return json(403, { message: 'sin permiso', code: '42501' })
      Object.assign(miembro, cuerpo)
      return json(200, { ...miembro })
    }
    if (tabla === 'consolidaciones' && consolidacionesFalla) return json(500, { message: 'caído', code: 'XX000' })
    let filas = tablas()[tabla] ?? []
    for (const [k, v] of url.searchParams) {
      if (v.startsWith('eq.') && filas.some(f => k in f)) filas = filas.filter(f => String(f[k]) === v.slice(3))
    }
    const objeto = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object')
    if (tabla === 'miembros' && objeto) {
      if (e.estadoMiembro === 500) return json(500, { message: 'caído', code: 'XX000' })
      if (e.estadoMiembro === 'ausente') return json(406, { message: 'no rows', code: 'PGRST116' })
    }
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
  await prueba('quien puede editar ve el botón, el formulario sale con los datos y valida antes de llamar al servidor', async () => {
    const { browser, page, e, errores } = await escenario('administrador')
    await page.goto(url('/miembros/m1')); await page.waitForSelector('[data-test=editar]')
    await page.click('[data-test=editar]'); await page.waitForSelector('[data-test=form-ficha]')
    assert.equal(await page.inputValue('#fi-nombre'), 'Ana'); assert.equal(await page.inputValue('#fi-email'), 'ana@x.test'); assert.equal(await page.inputValue('#fi-nac'), '1990-05-17')
    await page.fill('#fi-nombre', '  '); await page.fill('#fi-email', 'sin-arroba'); await page.fill('#fi-tel', 'abc'); await page.click('[data-test=guardar]')
    for (const s of ['e-nombre', 'e-email', 'e-telefono']) assert.equal(await page.locator(`[data-test=${s}]`).count(), 1, s)
    assert.equal(await page.getAttribute('#fi-email', 'aria-invalid'), 'true')
    assert.equal(e.patches.length, 0, 'con errores no se llama al servidor')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('guardar manda solo los campos que cambian, normalizados, y la ficha muestra lo nuevo', async () => {
    const { browser, page, e } = await escenario('administrador')
    await page.goto(url('/miembros/m1')); await page.click('[data-test=editar]'); await page.waitForSelector('[data-test=form-ficha]')
    await page.fill('#fi-tel', '+34 611 222 333'); await page.fill('#fi-email', ' ANA@X.TEST '); await page.fill('#fi-notas', 'Conocida en el culto'); await page.selectOption('#fi-casa', 'c2')
    await page.click('[data-test=guardar]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Cambios guardados'))
    assert.deepEqual(e.patches.map(p => p.cuerpo), [{ telefono: '+34 611 222 333', notas: 'Conocida en el culto', casa_oracion_id: 'c2' }], 'el correo cambió solo de mayúsculas y espacios: no se envía')
    assert.equal(await page.locator('[data-test=form-ficha]').count(), 0, 'el formulario se cierra')
    assert.match(await page.textContent('body'), /\+34 611 222 333/)
    await browser.close()
  })

  await prueba('sin cambios no se llama al servidor y se dice; vaciar un dato lo guarda como nulo', async () => {
    const { browser, page, e } = await escenario('administrador')
    await page.goto(url('/miembros/m1')); await page.click('[data-test=editar]'); await page.waitForSelector('[data-test=form-ficha]')
    await page.click('[data-test=guardar]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('nada que guardar'))
    assert.equal(e.patches.length, 0)
    await page.click('[data-test=editar]'); await page.fill('#fi-email', ''); await page.fill('#fi-nac', ''); await page.uncheck('[data-test=f-activo]'); await page.click('[data-test=guardar]'); await page.click('[data-test=desactivar-si]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Cambios guardados'))
    assert.deepEqual(e.patches[0].cuerpo, { email: null, fecha_nacimiento: null, activo: false })
    await browser.close()
  })

  await prueba('si el servidor rechaza el cambio, se ve el error en rojo y la ficha sigue abierta con lo escrito', async () => {
    const { browser, page } = await escenario('administrador', { patchFalla: true })
    await page.goto(url('/miembros/m1')); await page.click('[data-test=editar]'); await page.waitForSelector('[data-test=form-ficha]')
    await page.fill('#fi-tel', '+34 699 000 111'); await page.click('[data-test=guardar]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('No se pudieron guardar'))
    assert.match(await page.locator('[data-test=aviso]').getAttribute('class'), /red/)
    assert.equal(await page.locator('[data-test=form-ficha]').count(), 1, 'sigue abierta')
    assert.equal(await page.inputValue('#fi-tel'), '+34 699 000 111', 'lo escrito no se pierde')
    await browser.close()
  })

  await prueba('desactivar a una persona pide confirmación: «Volver» no guarda nada y «Sí, desactivar» guarda', async () => {
    const { browser, page, e } = await escenario('administrador')
    await page.goto(url('/miembros/m1')); await page.click('[data-test=editar]'); await page.waitForSelector('[data-test=form-ficha]')
    await page.uncheck('[data-test=f-activo]'); await page.click('[data-test=guardar]')
    await page.waitForSelector('[data-test=confirmar-desactivar]')
    assert.match(await page.textContent('[data-test=confirmar-desactivar]'), /Ana dejará de salir en las listas y en los recuentos/)
    assert.equal(e.patches.length, 0, 'sin confirmar no se llama al servidor')
    await page.click('[data-test=desactivar-no]')
    assert.equal(await page.locator('[data-test=confirmar-desactivar]').count(), 0); assert.equal(e.patches.length, 0)
    await page.click('[data-test=guardar]'); await page.click('[data-test=desactivar-si]')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Cambios guardados'))
    assert.deepEqual(e.patches.map(p => p.cuerpo), [{ activo: false }])
    await browser.close()
  })

  await prueba('Escape cierra la edición sin guardar, y sin permiso de editar no hay botón', async () => {
    const { browser, page, e } = await escenario('administrador')
    await page.goto(url('/miembros/m1')); await page.click('[data-test=editar]'); await page.fill('#fi-nombre', 'Otra'); await page.press('#fi-nombre', 'Escape')
    assert.equal(await page.locator('[data-test=form-ficha]').count(), 0); assert.equal(e.patches.length, 0)
    await browser.close()
    const z = await escenario('lider_zona')
    await z.page.goto(url('/miembros/m1')); await z.page.waitForSelector('h2')
    assert.equal(await z.page.locator('[data-test=editar]').count(), 0)
    await z.browser.close()
  })

  await prueba('un fallo de lectura no se disfraza de «no encontrado»: se dice y se puede reintentar; una persona ausente sí es «no encontrada»', async () => {
    const a = await escenario('administrador', { miembroFalla: 500 })
    await a.page.goto(url('/miembros/m1')); await a.page.waitForSelector('[data-test=error-carga]')
    a.e.estadoMiembro = null
    await a.page.click('[data-test=reintentar]'); await a.page.waitForSelector('[data-test=editar]')
    await a.browser.close()
    const b = await escenario('administrador', { miembroFalla: 'ausente' })
    await b.page.goto(url('/miembros/m1')); await b.page.waitForFunction(() => document.body.textContent.includes('Miembro no encontrado'))
    assert.equal(await b.page.locator('[data-test=error-carga]').count(), 0)
    await b.browser.close()
  })

  await prueba('si falla una lectura secundaria, la ficha avisa de que puede estar incompleta', async () => {
    const { browser, page } = await escenario('administrador', { consolidacionesFalla: true })
    await page.goto(url('/miembros/m1')); await page.waitForSelector('[data-test=lecturas-fallidas]')
    assert.match(await page.textContent('[data-test=lecturas-fallidas]'), /historial de seguimiento/)
    await browser.close()
  })
} finally { parar() }

if (fallos) { console.error(`\n${fallos} prueba(s) fallida(s)`); process.exit(1) }
console.log('\nFicha: todas las pruebas de interfaz pasan')
