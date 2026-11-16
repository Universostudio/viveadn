// Prueba de la pantalla «Seguimiento» de Configuración (método de seguimiento de nuevas personas) en un navegador real, con la red simulada y con estado:
// elegir plantilla, crear un método propio, validar, editar con aviso de procesos abiertos, restaurar, archivar, plan sin método propio, base sin métodos y errores.
// Uso: npm run test:seguimiento-config-ui   (levanta Vite en el puerto 5198 con una dirección de Supabase inventada y la intercepta)
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5198
const SB = 'https://fake.supabase.test'
const IG = '11111111-1111-1111-1111-111111111111'
const USR = '22222222-2222-2222-2222-222222222222'
const OP72 = '5e000000-0000-4000-8000-000000000072'
const SIMPLE = '5e000000-0000-4000-8000-000000000001'
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

const plantillas = () => [
  { id: OP72, iglesia_id: null, clave: 'op72', nombre: 'OP72', plantilla_origen: null, pasos: 3, plazo_horas: 72, umbral_amarillo_horas: 24, umbral_naranja_horas: 48, primer_contacto_horas: 24, archivado_en: null },
  { id: SIMPLE, iglesia_id: null, clave: 'simple', nombre: 'Seguimiento simple', plantilla_origen: null, pasos: 1, plazo_horas: 168, umbral_amarillo_horas: 72, umbral_naranja_horas: 120, primer_contacto_horas: 72, archivado_en: null },
]

// plan: 'premium' (con método propio) o 'semilla'; rol: 'propietario' o 'colaborador' (sin permiso de configurar)
async function escenario({ plan = 'premium', rol = 'propietario', conMetodos = true, metodosFallan = false, escrituraFalla = null, uso = { total: 5, abiertos: 3 }, propios = [] } = {}) {
  const e = { escrituras: [], rpc: [], config: null, metodos: [...plantillas(), ...propios], metodosFallan }
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ locale: 'es-ES', viewport: { width: 1280, height: 1400 } })
  const sesion = { access_token: 'x.y.z', refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: USR, aud: 'authenticated', email: 'p@prueba.test', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } }
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  const modulos = ['iglesia', 'consolidacion', 'miembros', ...(plan === 'premium' ? ['seguimiento_propio'] : [])]
  const tablas = () => ({
    perfiles: [{ id: USR, iglesia_id: IG, nombre: 'Yo', apellido: 'Mismo', email: 'p@prueba.test', rol, activo: true }],
    iglesias: [{ id: IG, nombre: 'Iglesia de Prueba', slug: 'prueba', activa: true, plan, etapa: 'activa', pais: 'España', modo_alias: false }],
    roles: [{ clave: 'propietario', nombre: 'Superadministrador', es_propietario: true, rol_permisos: [] },
            { clave: 'colaborador', nombre: 'Colaborador', es_propietario: false, rol_permisos: [{ permiso: 'consolidacion.ver' }] }],
    plan_modulos: modulos.map(modulo => ({ modulo })), iglesia_modulos: [],
    permisos: [{ clave: 'iglesia.configurar', modulo: 'iglesia' }, { clave: 'consolidacion.ver', modulo: 'consolidacion' }, { clave: 'miembros.ver', modulo: 'miembros' }],
    plataforma_admins: [], usuarios: [], invitaciones: [],
    adn_seguimiento_metodos: e.metodos, adn_seguimiento_config: e.config ? [e.config] : [],
  })
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*', 'access-control-expose-headers': '*' }
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const url = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body, extra = {}) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json', ...extra }, body: JSON.stringify(body) })
    if (!url.pathname.startsWith('/rest/v1/')) return json(200, [])
    if (url.pathname.includes('/rpc/')) { e.rpc.push({ nombre: url.pathname.split('/').pop(), cuerpo: req.postDataJSON() }); return json(200, uso) }
    const tabla = url.pathname.split('/').pop()
    if (tabla === 'adn_seguimiento_metodos' && !conMetodos) return json(404, { message: 'relation does not exist', code: '42P01' })
    if (tabla === 'adn_seguimiento_metodos' && e.metodosFallan && req.method() === 'GET' && url.searchParams.get('select') === '*') return json(500, { message: 'caído', code: 'XX000' })
    const quiereObjeto = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object')
    const minimo = (req.headers()['prefer'] ?? '').includes('return=minimal') || !(req.headers()['prefer'] ?? '').includes('return=representation')
    if (req.method() === 'POST' || req.method() === 'PATCH') {
      const cuerpo = req.postDataJSON()
      e.escrituras.push({ metodo: req.method(), tabla, cuerpo, filtro: url.search })
      if (escrituraFalla) return json(escrituraFalla.status, { message: escrituraFalla.message, code: escrituraFalla.code })
      if (tabla === 'adn_seguimiento_metodos' && req.method() === 'POST') {
        const fila = { id: 'nuevo-' + (e.metodos.length + 1), archivado_en: null, ...cuerpo }
        e.metodos.push(fila)
        return quiereObjeto ? json(201, fila) : json(201, minimo ? null : [fila])
      }
      if (tabla === 'adn_seguimiento_metodos' && req.method() === 'PATCH') {
        const id = url.searchParams.get('id')?.replace('eq.', '')
        const f = e.metodos.find(m => m.id === id)
        if (f) Object.assign(f, cuerpo)
        return minimo ? ruta.fulfill({ status: 204, headers: cors }) : json(200, f ? [f] : [])
      }
      if (tabla === 'adn_seguimiento_config') {
        if (req.method() === 'POST') e.config = { ...cuerpo }
        else e.config = { ...(e.config ?? {}), ...cuerpo }
        return minimo ? ruta.fulfill({ status: 201, headers: cors }) : json(200, [e.config])
      }
      return json(200, [])
    }
    let filas = tablas()[tabla] ?? []
    for (const [k, v] of url.searchParams) if (v.startsWith('eq.') && filas.some(f => k in f)) filas = filas.filter(f => String(f[k]) === v.slice(3))
    const limite = Number(url.searchParams.get('limit') ?? 0)
    if (limite) filas = filas.slice(0, limite)
    if (req.method() === 'HEAD') return ruta.fulfill({ status: 200, headers: { ...cors, 'content-range': `*/${filas.length}` } })
    if (quiereObjeto) return json(200, filas[0] ?? null)
    return json(200, filas, { 'content-range': `0-${Math.max(0, filas.length - 1)}/${filas.length}` })
  })
  const page = await ctx.newPage()
  const errores = []
  page.on('pageerror', x => errores.push(x.message))
  return { browser, page, e, errores }
}
const url = r => `http://localhost:${PUERTO}${r}`
const texto = (page, s) => page.locator(s).first().innerText()
const abrirPestana = async page => { await page.goto(url('/configuracion')); await page.getByRole('button', { name: 'Seguimiento', exact: true }).click(); await page.waitForSelector('[data-test=config-seguimiento]') }
let fallos = 0
const prueba = async (n, fn) => { try { await fn(); console.log(`✓ ${n}`) } catch (x) { fallos++; console.error(`✗ ${n}\n   ${x.message}`) } }
const propioFila = (extra = {}) => ({ id: 'p1', iglesia_id: IG, clave: 'propio_a1', nombre: 'Mi método', plantilla_origen: OP72, pasos: 2, plazo_horas: 96, umbral_amarillo_horas: 30, umbral_naranja_horas: 60, primer_contacto_horas: 12, archivado_en: null, ...extra })

try {
  await prueba('Premium: se ven las dos plantillas con OP72 en uso y «valores por validar» solo en Seguimiento simple', async () => {
    const { browser, page, errores } = await escenario()
    await abrirPestana(page)
    await page.waitForSelector('[data-test=metodo-op72]')
    assert.match(await texto(page, '[data-test=metodo-op72]'), /OP72/)
    assert.equal(await page.locator('[data-test=metodo-op72] [data-test=seg-activo]').count(), 1, 'sin configuración, OP72 es el método en uso')
    assert.match(await texto(page, '[data-test=metodo-op72]'), /Contactos: 3\. Plazo: 72 h\./)
    assert.match(await texto(page, '[data-test=metodo-op72]'), /Verde hasta 24 h, amarillo hasta 48 h, naranja hasta 72 h y rojo después/)
    assert.equal(await page.locator('[data-test=metodo-simple] [data-test=seg-activo]').count(), 0)
    assert.equal(await page.locator('[data-test=metodo-simple] [data-test=seg-por-validar]').count(), 1, 'Seguimiento simple se marca por validar')
    assert.equal(await page.locator('[data-test=metodo-op72] [data-test=seg-por-validar]').count(), 0, 'OP72 no')
    assert.equal(await page.locator('[data-test=seg-solo-premium]').count(), 0)
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('elegir Seguimiento simple escribe la configuración de la iglesia y pasa a estar en uso; los procesos abiertos se avisan que no cambian', async () => {
    const { browser, page, e } = await escenario()
    await abrirPestana(page)
    await page.click('[data-test=seg-usar-simple]')
    await page.waitForSelector('[data-test=metodo-simple] [data-test=seg-activo]')
    assert.deepEqual(e.escrituras.map(x => `${x.metodo} ${x.tabla}`), ['POST adn_seguimiento_config'])
    assert.deepEqual(e.escrituras[0].cuerpo, { iglesia_id: IG, metodo_id: SIMPLE })
    assert.match(await texto(page, '[data-test=seg-aviso]'), /Los procesos abiertos siguen con el suyo/)
    assert.equal(await page.locator('[data-test=metodo-op72] [data-test=seg-activo]').count(), 0)
    await page.click('[data-test=seg-usar-op72]')
    await page.waitForSelector('[data-test=metodo-op72] [data-test=seg-activo]')
    assert.equal(e.escrituras[1].metodo, 'PATCH', 'con configuración ya creada se actualiza, no se vuelve a insertar')
    assert.deepEqual(e.escrituras[1].cuerpo, { metodo_id: OP72 })
    await browser.close()
  })

  await prueba('crear mi método a partir de OP72: copia los valores, abre el editor y no cambia nada hasta guardar', async () => {
    const { browser, page, e } = await escenario()
    await abrirPestana(page)
    await page.click('[data-test=seg-copiar-op72]')
    await page.waitForSelector('[data-test=seg-editor]')
    const cuerpo = e.escrituras[0].cuerpo
    assert.equal(e.escrituras[0].tabla, 'adn_seguimiento_metodos')
    assert.equal(cuerpo.iglesia_id, IG)
    assert.equal(cuerpo.plantilla_origen, OP72)
    assert.equal(cuerpo.nombre, 'OP72 (copia)')
    assert.match(cuerpo.clave, /^propio_[a-z0-9]+$/)
    assert.deepEqual([cuerpo.pasos, cuerpo.plazo_horas, cuerpo.umbral_amarillo_horas, cuerpo.umbral_naranja_horas, cuerpo.primer_contacto_horas], [3, 72, 24, 48, 24])
    assert.equal(await page.inputValue('[data-test=seg-f-nombre]'), 'OP72 (copia)')
    assert.equal(await page.inputValue('[data-test=seg-f-plazo]'), '72')
    assert.match(await texto(page, '[data-test=seg-aviso]'), /Método creado/)
    assert.equal(await page.locator('[data-test=seg-guardar]').isDisabled(), true, 'sin cambios no se puede guardar')
    assert.equal(e.rpc.length, 1, 'al abrir el editor pregunta cuántos procesos usan el método')
    await browser.close()
  })

  await prueba('editar: cada regla muestra su error junto al campo, no se envía nada y al corregir se guarda con los números y el aviso de procesos abiertos', async () => {
    const { browser, page, e } = await escenario({ propios: [propioFila()] })
    await abrirPestana(page)
    await page.click('[data-test=seg-editar-propio_a1]')
    await page.waitForSelector('[data-test=seg-editor]')
    assert.match(await texto(page, '[data-test=seg-uso]'), /5 en total, 3 abiertos/)
    // El nombre y el número de pasos no mueven plazos: sin aviso de procesos
    await page.fill('[data-test=seg-f-nombre]', 'Mi método v2')
    assert.equal(await page.locator('[data-test=seg-aviso-procesos]').count(), 0)
    // Errores
    await page.fill('[data-test=seg-f-amarillo]', '70'); await page.fill('[data-test=seg-f-naranja]', '60')
    assert.match(await texto(page, '[data-test=seg-e-naranja]'), /naranja tiene que empezar después del amarillo/)
    await page.fill('[data-test=seg-f-naranja]', '100')
    assert.match(await texto(page, '[data-test=seg-e-naranja]'), /no puede pasar del plazo total/)
    await page.fill('[data-test=seg-f-plazo]', '0')
    assert.match(await texto(page, '[data-test=seg-e-plazo]'), /de 1 a 720 horas/)
    await page.fill('[data-test=seg-f-plazo]', '800')
    assert.match(await texto(page, '[data-test=seg-e-plazo]'), /de 1 a 720 horas/)
    await page.fill('[data-test=seg-f-nombre]', '   ')
    assert.match(await texto(page, '[data-test=seg-e-nombre]'), /Escribe un nombre/)
    await page.fill('[data-test=seg-f-primer]', '2000'); await page.fill('[data-test=seg-f-plazo]', '96')
    assert.match(await texto(page, '[data-test=seg-e-primer]'), /no puede pasar del plazo total/)
    await page.click('[data-test=seg-guardar]')
    assert.match(await texto(page, '[data-test=seg-error]'), /Revisa los campos marcados/)
    assert.equal(e.escrituras.length, 0, 'con errores no se envía nada a la base')
    // Corregir y guardar
    await page.fill('[data-test=seg-f-nombre]', ' Mi método v2 '); await page.fill('[data-test=seg-f-amarillo]', '40'); await page.fill('[data-test=seg-f-naranja]', '80'); await page.fill('[data-test=seg-f-plazo]', '120'); await page.fill('[data-test=seg-f-primer]', '')
    assert.equal(await page.locator('[data-test=seg-e-naranja], [data-test=seg-e-plazo], [data-test=seg-e-primer], [data-test=seg-e-nombre]').count(), 0, 'sin errores al corregir')
    assert.match(await texto(page, '[data-test=seg-aviso-procesos]'), /3 procesos abiertos usan este método/)
    await page.click('[data-test=seg-guardar]')
    await page.waitForSelector('[data-test=seg-aviso]')
    assert.equal(e.escrituras.length, 1)
    assert.equal(e.escrituras[0].metodo, 'PATCH'); assert.match(e.escrituras[0].filtro, /id=eq\.p1/)
    assert.deepEqual(e.escrituras[0].cuerpo, { nombre: 'Mi método v2', pasos: 2, plazo_horas: 120, umbral_amarillo_horas: 40, umbral_naranja_horas: 80, primer_contacto_horas: null })
    assert.match(await texto(page, '[data-test=seg-aviso]'), /Cambios guardados/)
    assert.match(await texto(page, '[data-test=metodo-propio_a1]'), /Mi método v2/)
    assert.match(await texto(page, '[data-test=metodo-propio_a1]'), /Plazo: 120 h/)
    assert.equal(await page.locator('[data-test=seg-guardar]').isDisabled(), true)
    await browser.close()
  })

  await prueba('restaurar vuelve a los valores de la plantilla de origen pero hasta guardar no se envía nada', async () => {
    const { browser, page, e } = await escenario({ propios: [propioFila()] })
    await abrirPestana(page)
    await page.click('[data-test=seg-editar-propio_a1]'); await page.waitForSelector('[data-test=seg-editor]')
    await page.click('[data-test=seg-restaurar]')
    assert.equal(await page.inputValue('[data-test=seg-f-plazo]'), '72')
    assert.equal(await page.inputValue('[data-test=seg-f-amarillo]'), '24')
    assert.equal(await page.inputValue('[data-test=seg-f-nombre]'), 'Mi método', 'conserva su nombre')
    assert.equal(e.escrituras.length, 0)
    assert.match(await texto(page, '[data-test=seg-aviso]'), /Guarda para aplicarlos/)
    await page.click('[data-test=seg-guardar]'); await page.waitForFunction(() => document.querySelector('[data-test=seg-aviso]')?.textContent?.includes('guardados'))
    assert.equal(e.escrituras[0].cuerpo.plazo_horas, 72)
    await browser.close()
  })

  await prueba('el método en uso no se archiva; uno que no se usa se archiva con confirmación y desaparece de la lista', async () => {
    const { browser, page, e } = await escenario({ propios: [propioFila()] })
    await abrirPestana(page)
    await page.click('[data-test=seg-usar-propio_a1]'); await page.waitForSelector('[data-test=metodo-propio_a1] [data-test=seg-activo]')
    await page.click('[data-test=seg-editar-propio_a1]'); await page.waitForSelector('[data-test=seg-editor]')
    assert.equal(await page.locator('[data-test=seg-archivar]').count(), 0, 'el método en uso no ofrece archivar')
    assert.match(await texto(page, '[data-test=seg-editor]'), /elige antes otro método/)
    await page.click('[data-test=seg-usar-op72]'); await page.waitForSelector('[data-test=metodo-op72] [data-test=seg-activo]')
    await page.waitForSelector('[data-test=seg-archivar]')
    await page.click('[data-test=seg-archivar]')
    assert.match(await texto(page, '[data-test=seg-confirmar-archivo]'), /¿Archivar «Mi método»\?/)
    await page.click('[data-test=seg-archivar-no]')
    assert.equal(await page.locator('[data-test=seg-confirmar-archivo]').count(), 0)
    const antes = e.escrituras.length
    await page.click('[data-test=seg-archivar]'); await page.click('[data-test=seg-archivar-si]')
    await page.waitForFunction(() => !document.querySelector('[data-test=metodo-propio_a1]'))
    const ultima = e.escrituras[e.escrituras.length - 1]
    assert.equal(e.escrituras.length, antes + 1)
    assert.equal(ultima.metodo, 'PATCH'); assert.match(ultima.filtro, /id=eq\.p1/)
    assert.deepEqual(Object.keys(ultima.cuerpo), ['archivado_en'])
    assert.match(await texto(page, '[data-test=seg-aviso]'), /Método archivado/)
    await browser.close()
  })

  await prueba('plan sin método propio (Semilla): elige plantillas, no ve crear ni editar y se le explica', async () => {
    const { browser, page, e } = await escenario({ plan: 'semilla', propios: [propioFila()] })
    await abrirPestana(page)
    await page.waitForSelector('[data-test=metodo-op72]')
    assert.equal(await page.locator('[data-test=seg-solo-premium]').count(), 1)
    assert.match(await texto(page, '[data-test=seg-solo-premium]'), /forma parte del plan Premium/)
    assert.equal(await page.locator('[data-test^=seg-copiar-]').count(), 0, 'sin módulo no hay «crear mi método»')
    assert.equal(await page.locator('[data-test^=seg-editar-]').count(), 0, 'ni editar')
    await page.click('[data-test=seg-usar-simple]'); await page.waitForSelector('[data-test=metodo-simple] [data-test=seg-activo]')
    assert.deepEqual(e.escrituras.map(x => x.tabla), ['adn_seguimiento_config'], 'solo escribe la elección de plantilla')
    await browser.close()
  })

  await prueba('sin permiso para configurar la iglesia la pestaña no aparece', async () => {
    const { browser, page } = await escenario({ rol: 'colaborador' })
    await page.goto(url('/configuracion')); await page.waitForSelector('h1')
    await page.waitForTimeout(500)
    assert.equal(await page.getByRole('button', { name: 'Seguimiento', exact: true }).count(), 0)
    await browser.close()
  })

  await prueba('base sin métodos (migración sin aplicar): lo dice con claridad, sin errores ni botones de escritura', async () => {
    const { browser, page, errores } = await escenario({ conMetodos: false })
    await abrirPestana(page)
    await page.waitForSelector('[data-test=seg-no-disponible]')
    assert.match(await texto(page, '[data-test=seg-no-disponible]'), /todavía no está disponible/)
    assert.equal(await page.locator('[data-test^=seg-usar-], [data-test^=seg-copiar-]').count(), 0)
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('si la base rechaza un guardado se muestra el motivo y nada cambia en pantalla', async () => {
    const { browser, page } = await escenario({ propios: [propioFila()], escrituraFalla: { status: 403, code: '42501', message: 'new row violates row-level security policy' } })
    await abrirPestana(page)
    await page.click('[data-test=seg-editar-propio_a1]'); await page.waitForSelector('[data-test=seg-editor]')
    await page.fill('[data-test=seg-f-nombre]', 'Otro nombre')
    await page.click('[data-test=seg-guardar]')
    await page.waitForSelector('[data-test=seg-error]')
    assert.match(await texto(page, '[data-test=seg-error]'), /No tienes permiso para cambiar esto, o tu plan no incluye el método propio/)
    assert.equal(await page.inputValue('[data-test=seg-f-nombre]'), 'Otro nombre', 'lo escrito no se pierde')
    await page.click('[data-test=seg-usar-simple]')
    await page.waitForFunction(() => document.querySelector('[data-test=seg-error]')?.textContent?.includes('permiso'))
    assert.equal(await page.locator('[data-test=metodo-simple] [data-test=seg-activo]').count(), 0, 'no se marca en uso lo que la base rechazó')
    await browser.close()
  })

  await prueba('si no se pueden cargar los métodos: aviso con reintentar, no una lista vacía', async () => {
    const { browser, page, e } = await escenario({ metodosFallan: true })
    await abrirPestana(page)
    await page.waitForSelector('[data-test=seg-error-carga]')
    assert.equal(await page.locator('[data-test^=seg-usar-]').count(), 0)
    e.metodosFallan = false
    await page.click('[data-test=seg-reintentar]')
    await page.waitForSelector('[data-test=metodo-op72]')
    assert.equal(await page.locator('[data-test=seg-error-carga]').count(), 0)
    await browser.close()
  })
} finally { parar() }
if (fallos) { console.error(`\n${fallos} prueba(s) fallan`); process.exit(1) }
console.log('\nSeguimiento (configuración): todas las pruebas de interfaz pasan')
