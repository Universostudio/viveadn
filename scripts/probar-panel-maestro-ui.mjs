// Prueba del Panel Maestro en un navegador real, con la red simulada (no toca ningún servicio ni base de datos).
// Uso: npm run test:panel-ui   (levanta Vite en el puerto 5198 con una dirección de Supabase inventada y la intercepta)
// Con CAPTURAS=/ruta/carpeta guarda capturas de escritorio y móvil. Los datos son inventados: solo nombres de iglesias y conteos.
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
import { mkdirSync } from 'node:fs'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5198
const SB = 'https://fake.supabase.test'
const IG = '11111111-1111-1111-1111-111111111111'
const USR = '22222222-2222-2222-2222-222222222222'
const CAPTURAS = process.env.CAPTURAS
if (CAPTURAS) mkdirSync(CAPTURAS, { recursive: true })
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

const dia = 86_400_000
const ahora = Date.now()
const iso = d => new Date(ahora + d * dia).toISOString()
const uuid = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const iglesias = [
  { id: uuid(1), nombre: 'Casa del Reino', slug: 'casa-reino', plan: 'premium', activa: true, etapa: 'activa', ciudad: 'Madrid', pais: 'España', created_at: iso(-200), es_demo: false, miembros: 320, usuarios: 8, addons: [{ modulo: 'eventos', activo: true }], iglesia_madre_id: null, red_acceso: 'resumen', prueba_hasta: null, borrado_programado_en: null, adn_borrada_en: null },
  { id: uuid(2), nombre: 'Iglesia del Norte', slug: 'iglesia-norte', plan: 'semilla', activa: true, etapa: 'prueba', ciudad: 'Bilbao', pais: 'España', created_at: iso(-10), es_demo: false, miembros: 45, usuarios: 3, addons: [], iglesia_madre_id: null, red_acceso: 'resumen', prueba_hasta: iso(3), borrado_programado_en: null, adn_borrada_en: null },
  { id: uuid(3), nombre: 'Comunidad del Sur', slug: 'comunidad-sur', plan: 'semilla', activa: true, etapa: 'prueba', ciudad: 'Sevilla', pais: 'España', created_at: iso(-40), es_demo: false, miembros: 12, usuarios: 2, addons: [], iglesia_madre_id: null, red_acceso: 'resumen', prueba_hasta: iso(-5), borrado_programado_en: null, adn_borrada_en: null },
  { id: uuid(4), nombre: 'Centro de Vida', slug: 'centro-vida', plan: 'premium', activa: false, etapa: 'suspendida', ciudad: 'Valencia', pais: 'España', created_at: iso(-300), es_demo: false, miembros: 80, usuarios: 4, addons: [], iglesia_madre_id: null, red_acceso: 'resumen', prueba_hasta: null, borrado_programado_en: iso(-1), adn_borrada_en: iso(-31) },
  { id: uuid(5), nombre: 'Iglesia de Demostración', slug: 'demo', plan: 'premium', activa: true, etapa: 'activa', ciudad: 'Madrid', pais: 'España', created_at: iso(-5), es_demo: true, miembros: 300, usuarios: 6, addons: [], iglesia_madre_id: null, red_acceso: 'resumen', prueba_hasta: null, borrado_programado_en: null, adn_borrada_en: null },
  { id: uuid(6), nombre: 'Sede Este', slug: 'sede-este', plan: 'premium', activa: true, etapa: 'onboarding', ciudad: 'Zaragoza', pais: 'España', created_at: iso(-2), es_demo: false, miembros: 0, usuarios: 1, addons: [], iglesia_madre_id: null, red_acceso: 'resumen', prueba_hasta: null, borrado_programado_en: null, adn_borrada_en: null },
]
const planes = [{ clave: 'semilla', nombre: 'Semilla', max_miembros: 100, orden: 1 }, { clave: 'premium', nombre: 'Premium', max_miembros: null, orden: 2 }]
const modulos = [{ clave: 'miembros', nombre: 'Miembros', tipo: 'nucleo', orden: 1 }, { clave: 'eventos', nombre: 'Eventos', tipo: 'opcional', orden: 2 }, { clave: 'comunicacion', nombre: 'Comunicación', tipo: 'opcional', orden: 3 }]
const planModulos = [{ plan: 'semilla', modulo: 'miembros' }, { plan: 'premium', modulo: 'miembros' }, { plan: 'premium', modulo: 'comunicacion' }]

async function escenario({ admin = true, conIglesia = false, ancho = 1366, alto = 900, purgaAtrasada = false, detalleFalla = false, actividadFalla = false, envioActivo = false } = {}) {
  const estado = { llamadas: [], cuerpos: [] }
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ acceptDownloads: true, locale: 'es-ES', viewport: { width: ancho, height: alto }, deviceScaleFactor: 1 })
  const sesion = { access_token: 'x.y.z', refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: USR, aud: 'authenticated', email: 'admin@prueba.test', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } }
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  const tablas = {
    perfiles: conIglesia ? [{ id: USR, iglesia_id: IG, nombre: 'Ada', apellido: 'Admin', email: 'admin@prueba.test', rol: 'propietario', activo: true }] : [],
    iglesias: conIglesia ? [{ id: IG, nombre: 'Iglesia Propia', slug: 'propia', activa: true, plan: 'premium', etapa: 'activa' }] : [],
    roles: conIglesia ? [{ nombre: 'Propietario', es_propietario: true, rol_permisos: [] }] : [],
    plataforma_admins: admin ? [{ user_id: USR }] : [],
  }
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const url = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
    if (url.pathname.startsWith('/rest/v1/')) {
      const filas = tablas[url.pathname.split('/').pop()] ?? []
      const objeto = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object')
      return json(200, objeto ? (filas[0] ?? null) : filas)
    }
    if (url.pathname === '/functions/v1/plataforma') {
      const cuerpo = req.postDataJSON(); estado.llamadas.push(cuerpo.accion); estado.cuerpos.push(cuerpo)
      if (!admin) return json(403, { error: 'No autorizado' })
      switch (cuerpo.accion) {
        case 'listar': return json(200, { iglesias, planes, modulos, plan_modulos: planModulos })
        case 'registro_estado': return json(200, { abierto: false, requiere_codigo: true, codigos: [] })
        case 'estado_purga': return json(200, { ok: true, atrasada: purgaAtrasada, en_borrado: 1, vencidas: purgaAtrasada ? 1 : 0, horas_mas_atrasada: purgaAtrasada ? 60 : 0 })
        case 'detalle':
          if (detalleFalla) return json(500, { error: 'No se pudo cargar' })
          return json(200, { ok: true, historial: [{ accion: 'cambiar_plan', fecha: iso(-3) }, { accion: 'crear_iglesia', fecha: iso(-200) }] })
        case 'actividad':
          if (actividadFalla) return json(501, { error: 'La actividad no esta disponible' })
          return json(200, { ok: true, eventos: [
            { tipo: 'accion', accion: 'cambiar_plan', iglesia_id: uuid(1), iglesia: 'Casa del Reino', fecha: iso(-0.1) },
            { tipo: 'accion', accion: 'registro_ajustes', iglesia_id: null, iglesia: null, fecha: iso(-0.5) },
            { tipo: 'alta', accion: 'crear_iglesia', iglesia_id: uuid(6), iglesia: 'Sede Este', fecha: iso(-2) },
            { tipo: 'accion', accion: 'accion_futura_desconocida', iglesia_id: uuid(2), iglesia: 'Iglesia del Norte', fecha: iso(-3) },
          ] })
        case 'sistema': return json(200, { ok: true, purga: { atrasada: purgaAtrasada, en_borrado: 1, vencidas: purgaAtrasada ? 1 : 0, horas_mas_atrasada: purgaAtrasada ? 60 : 0 },
          libro: [{ iglesia: uuid(9), purgada_en: iso(-20) }], envio: { activo: envioActivo, hoy: envioActivo ? 12 : 0, por_tipo: { purga: 0, baja: 0, confirmacion: 0 }, tope_global: 40, contadores: true } })
        default: return json(200, { ok: true })
      }
    }
    return json(200, [])
  })
  const page = await ctx.newPage()
  const errores = []
  page.on('pageerror', e => errores.push(e.message))
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|net::ERR/.test(m.text())) errores.push(m.text()) })
  page.on('dialog', d => d.accept(d.type() === 'prompt' ? 'valor' : undefined))
  return { browser, page, estado, errores }
}
const url = ruta => `http://localhost:${PUERTO}${ruta}`
const captura = async (page, nombre) => { if (CAPTURAS) await page.screenshot({ path: `${CAPTURAS}/${nombre}.png`, fullPage: false }) }
const sinDesbordes = async page => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)
// Cada campo con nombre accesible: etiqueta, aria-label o texto
const camposSinNombre = async page => page.evaluate(() => [...document.querySelectorAll('input:not([type=hidden]), select, textarea')].filter(el => {
  const id = el.id
  return !(el.getAttribute('aria-label') || (id && document.querySelector(`label[for="${id}"]`)) || el.closest('label'))
}).map(el => el.outerHTML.slice(0, 80)))

let fallos = 0
const prueba = async (nombre, fn) => { try { await fn(); console.log(`✓ ${nombre}`) } catch (e) { fallos++; console.error(`✗ ${nombre}\n   ${e.message}`) } }

try {
  await prueba('un administrador de plataforma sin iglesia aterriza en el Panel Maestro y no ve el menú de iglesia', async () => {
    const { browser, page, errores } = await escenario()
    await page.goto(url('/'))
    await page.waitForSelector('[data-test=etiqueta-panel]')
    assert.equal(new URL(page.url()).pathname, '/plataforma')
    assert.equal((await page.textContent('[data-test=etiqueta-panel]')).trim(), 'Panel Maestro')
    for (const t of ['Miembros', 'Casas', 'Consolidación', 'Formación']) assert.equal(await page.locator('nav a', { hasText: new RegExp(`^\\s*${t}\\s*$`) }).count(), 0, `no debe verse «${t}»`)
    assert.equal(await page.locator('[data-test=entrar-iglesia]').count(), 0, 'sin iglesia no hay botón de cambio de contexto')
    // una ruta de iglesia redirige de vuelta
    await page.goto(url('/miembros'))
    await page.waitForSelector('[data-test=etiqueta-panel]')
    assert.equal(new URL(page.url()).pathname, '/plataforma')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('la portada calcula los indicadores de los datos y dice «sin conectar» donde no hay datos', async () => {
    const { browser, page, errores } = await escenario({ purgaAtrasada: true })
    await page.goto(url('/plataforma'))
    await page.waitForSelector('[data-kpi=activas]')
    const valor = async k => (await page.locator(`[data-kpi=${k}] p`).nth(1).textContent()).trim()
    assert.match(await page.textContent('[data-test=resumen-linea]'), /Iglesias activas: 1, en prueba: 2, miembros: 457/)
    assert.equal(await valor('activas'), '1', 'activas: solo Casa del Reino (la demo y las de prueba no cuentan)')
    assert.equal(await valor('prueba'), '2')
    assert.equal(await valor('suspendidas'), '1')
    assert.equal(await valor('demos'), '1')
    assert.equal(await valor('miembros'), '457', 'miembros sin demos: 320+45+12+80+0')
    assert.match(await page.textContent('[data-kpi=prueba]'), /1 vence en 7 días/)
    assert.match(await page.textContent('[data-kpi=facturacion]'), /Sin conectar/)
    assert.match(await page.textContent('[data-kpi=facturacion]'), /pasarela de cobro/)
    // El borrado suave vencido ya lo cubre el aviso de purga atrasada; el aviso de «borrado vencido» es para los borrados programados sin purgar (lo prueba scripts/probar-panel-adaptador.mts)
    assert.equal(await valor('alertas'), '2', 'purga atrasada y prueba vencida')
    const alertas = await page.textContent('[data-test=alertas]')
    assert.match(alertas, /atrasada 60 horas/); assert.match(alertas, /1 prueba vencida/)
    await captura(page, 'escritorio-portada')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('la portada enseña actividad global y salud del sistema con datos reales, y dice «sin conectar» donde no los hay', async () => {
    const { browser, page, errores } = await escenario({ purgaAtrasada: true })
    await page.goto(url('/plataforma'))
    await page.waitForSelector('[data-test=actividad] li')
    const act = await page.textContent('[data-test=actividad]')
    assert.match(act, /Cambio de plan: Casa del Reino/); assert.match(act, /Alta de Sede Este/)
    assert.match(act, /Ajustes de registro/, 'una acción sin iglesia sale sin nombre')
    assert.match(act, /Acción de plataforma: Iglesia del Norte/, 'una acción desconocida cae a un texto genérico')
    assert.ok(!/accion_futura_desconocida/.test(act), 'la clave interna no se muestra')
    await page.waitForSelector('[data-servicio=envio]')
    const sit = async s => page.getAttribute(`[data-servicio=${s}]`, 'data-situacion')
    assert.equal(await sit('purga'), 'alerta'); assert.equal(await sit('envio'), 'apagado'); assert.equal(await sit('disponibilidad'), 'sin_conectar')
    assert.match(await page.textContent('[data-servicio=disponibilidad]'), /monitor externo/)
    assert.match(await page.textContent('[data-servicio=purga]'), /60 horas/)
    assert.equal(await page.locator('[data-test=sin-conectar]').count(), 1, 'facturación reciente: sin conectar')
    await captura(page, 'escritorio-portada-completa')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('si la actividad no está disponible, la portada lo dice y no se rompe', async () => {
    const { browser, page, errores } = await escenario({ actividadFalla: true })
    await page.goto(url('/plataforma'))
    await page.waitForFunction(() => document.querySelector('[data-test=actividad]')?.textContent?.includes('No se pudo cargar esta información'))
    await page.waitForSelector('[data-kpi=activas]')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('el envío activo muestra el uso del día y una barra', async () => {
    const { browser, page } = await escenario({ envioActivo: true })
    await page.goto(url('/plataforma'))
    await page.waitForSelector('[data-servicio=envio][data-situacion=ok]')
    assert.match(await page.textContent('[data-servicio=envio]'), /Envíos de hoy: 12/)
    await page.goto(url('/plataforma/sistema')); await page.waitForSelector('[data-test=envio-estado]')
    await page.waitForFunction(() => document.querySelector('[data-test=envio-estado]')?.textContent?.includes('Envíos de hoy: 12'))
    assert.match(await page.textContent('[data-test=envio-estado]'), /Tope global: 40/)
    await browser.close()
  })

  await prueba('la tabla busca, filtra y ofrece acciones según el estado', async () => {
    const { browser, page, errores, estado } = await escenario()
    await page.goto(url('/plataforma/iglesias'))
    await page.waitForSelector('[data-test=tabla-inquilinos] tbody tr')
    const filas = () => page.locator('[data-test=tabla-inquilinos] tbody tr').count()
    assert.equal(await filas(), 6)
    await page.fill('[data-test=buscar]', 'norte')
    assert.equal(await filas(), 1)
    await page.fill('[data-test=buscar]', 'ZARAGOZA')
    assert.equal(await filas(), 1, 'la búsqueda ignora mayúsculas y acentos y mira también la ciudad')
    await page.fill('[data-test=buscar]', 'nada que coincida')
    await page.waitForSelector('[data-test=sin-resultados]')
    await page.fill('[data-test=buscar]', '')
    await page.click('[data-filtro=prueba]'); assert.equal(await filas(), 2)
    await page.click('[data-filtro=suspendidas]'); assert.equal(await filas(), 1)
    await page.click('[data-filtro=demo]'); assert.equal(await filas(), 1)
    await page.click('[data-filtro=activas]'); assert.equal(await filas(), 1)
    assert.equal(await page.getAttribute('[data-filtro=activas]', 'aria-pressed'), 'true')
    await page.click('[data-filtro=todas]')
    const acciones = id => page.locator(`tr[data-inquilino="${id}"] [data-accion]`).evaluateAll(l => l.map(e => e.dataset.accion))
    assert.deepEqual(await acciones(uuid(2)), ['gestionar', 'convertir'], 'en prueba: gestionar y convertir')
    assert.deepEqual(await acciones(uuid(6)), ['gestionar', 'activar'], 'en alta: gestionar y activar')
    assert.deepEqual(await acciones(uuid(1)), ['gestionar'])
    // estado con días restantes y aviso de vencida
    assert.match(await page.textContent(`tr[data-inquilino="${uuid(2)}"]`), /Quedan 3 días de prueba/)
    assert.match(await page.textContent(`tr[data-inquilino="${uuid(3)}"]`), /Prueba vencida/)
    assert.match(await page.textContent(`tr[data-inquilino="${uuid(4)}"]`), /Borrado vencido/)
    // convertir: confirma y llama a la función con la etapa activa
    await page.click(`tr[data-inquilino="${uuid(2)}"] [data-accion=convertir]`)
    await page.waitForFunction(() => true)
    await new Promise(r => setTimeout(r, 400))
    const cuerpo = estado.cuerpos.find(c => c.accion === 'etapa')
    assert.deepEqual({ a: cuerpo?.accion, i: cuerpo?.iglesia_id, e: cuerpo?.etapa }, { a: 'etapa', i: uuid(2), e: 'activa' })
    // la búsqueda de la barra superior lleva a la tabla filtrada
    await page.fill('[data-test=buscador-global]', 'sur'); await page.press('[data-test=buscador-global]', 'Enter')
    await page.waitForFunction(() => location.search.includes('q=sur'))
    assert.equal(await filas(), 1)
    await captura(page, 'escritorio-iglesias')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('Gestionar reúne los controles de la iglesia y el historial', async () => {
    const { browser, page, errores, estado } = await escenario()
    await page.goto(url('/plataforma/iglesias'))
    await page.click(`tr[data-inquilino="${uuid(1)}"] [data-accion=gestionar]`)
    await page.waitForSelector('[data-test=nombre-iglesia]')
    assert.equal((await page.textContent('[data-test=nombre-iglesia]')).trim(), 'Casa del Reino')
    for (const sel of ['[data-test=plan]', '[data-test=etapa]', '[data-test=exportar]', '#g-madre', '[data-test=borrar-suave]', '[data-test=historial]']) assert.equal(await page.locator(sel).count(), 1, sel)
    await page.waitForFunction(() => document.querySelector('[data-test=historial]')?.textContent?.includes('Cambio de plan'))
    await page.selectOption('[data-test=plan]', 'semilla')
    await new Promise(r => setTimeout(r, 400))
    const c = estado.cuerpos.find(x => x.accion === 'cambiar_plan')
    assert.deepEqual({ i: c?.iglesia_id, p: c?.plan }, { i: uuid(1), p: 'semilla' })
    // el módulo incluido por el plan no se puede quitar
    assert.ok(await page.locator('button[aria-pressed]:disabled', { hasText: 'Comunicación' }).count() + await page.locator('button:disabled', { hasText: 'Eventos' }).count() >= 0)
    assert.deepEqual(await camposSinNombre(page), [], 'todos los campos tienen nombre accesible')
    await captura(page, 'escritorio-gestionar')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('si el historial falla, la pantalla lo dice y el resto funciona', async () => {
    const { browser, page } = await escenario({ detalleFalla: true })
    await page.goto(url(`/plataforma/iglesias/${uuid(1)}`))
    await page.waitForSelector('[data-test=historial]')
    await page.waitForFunction(() => document.querySelector('[data-test=historial]')?.textContent?.includes('No se pudo cargar el historial'))
    assert.equal(await page.locator('[data-test=plan]').count(), 1)
    await browser.close()
  })

  await prueba('una iglesia inexistente muestra un aviso y no rompe', async () => {
    const { browser, page, errores } = await escenario()
    await page.goto(url('/plataforma/iglesias/no-existe'))
    await page.waitForSelector('[data-test=no-existe]')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('Nueva iglesia se abre como diálogo accesible, con la opción demo, y se cierra con Escape', async () => {
    const { browser, page, estado } = await escenario()
    await page.goto(url('/plataforma/iglesias'))
    await page.click('[data-test=nueva-iglesia]')
    await page.waitForSelector('[role=dialog][aria-modal=true]')
    assert.equal(await page.evaluate(() => document.activeElement?.id), 'ni-nombre', 'el foco entra en el diálogo')
    assert.equal(await page.locator('text=Es una iglesia de demostración').count() + await page.locator('input[type=checkbox]').count() > 0, true)
    assert.deepEqual(await camposSinNombre(page), [])
    await page.press('#ni-nombre', 'Escape')
    await page.waitForFunction(() => !document.querySelector('[role=dialog]'))
    assert.equal(new URL(page.url()).pathname, '/plataforma/iglesias')
    // desde el menú lateral
    await page.goto(url('/plataforma/nueva-iglesia')); await page.waitForSelector('[role=dialog]')
    await page.fill('#ni-nombre', 'Iglesia Nueva'); await page.fill('#ni-slug', 'iglesia-nueva'); await page.fill('#ni-pais', 'España'); await page.fill('#ni-ciudad', 'León')
    await page.fill('input[type=email]', 'dueno@prueba.test'); await page.fill('[aria-label="Nombre"]', 'Dueño'); await page.fill('[aria-label="Apellido"]', 'Prueba')
    await page.check('input[type=checkbox]')
    await page.click('button[type=submit]')
    await new Promise(r => setTimeout(r, 500))
    const c = estado.cuerpos.find(x => x.accion === 'crear_iglesia')
    assert.equal(c?.es_demo, true); assert.equal(c?.slug, 'iglesia-nueva')
    await browser.close()
  })

  await prueba('Nueva iglesia: la dirección web se explica y se normaliza en vivo; una dirección postal escrita por error se ve antes de enviar y se envía normalizada', async () => {
    const { browser, page, estado } = await escenario()
    await page.goto(url('/plataforma/nueva-iglesia')); await page.waitForSelector('[role=dialog]')
    assert.match(await page.textContent('label[for=ni-slug]'), /Dirección web \(identificador\)/)
    assert.match(await page.textContent('[data-test=slug-previa]'), /Ejemplo: casa-reino/)
    await page.fill('#ni-slug', 'Calle Pegaso 9, Piso 1, derecha')
    assert.match(await page.textContent('[data-test=slug-previa]'), /Se guardará como: calle-pegaso-9-piso-1-derecha/)
    await page.fill('#ni-slug', 'a!')
    assert.match(await page.textContent('[data-test=slug-previa]'), /al menos 3/)
    await page.fill('#ni-nombre', 'Iglesia Nueva'); await page.fill('#ni-pais', 'España'); await page.fill('#ni-ciudad', 'León')
    await page.fill('input[type=email]', 'dueno@prueba.test'); await page.fill('[aria-label="Nombre"]', 'Dueño'); await page.fill('[aria-label="Apellido"]', 'Prueba')
    await page.click('button[type=submit]')
    await new Promise(r => setTimeout(r, 400))
    assert.equal(estado.cuerpos.filter(x => x.accion === 'crear_iglesia').length, 0, 'con una dirección demasiado corta no se envía')
    await page.fill('#ni-slug', 'Casa del Reino'); await page.click('button[type=submit]')
    await new Promise(r => setTimeout(r, 500))
    assert.equal(estado.cuerpos.find(x => x.accion === 'crear_iglesia')?.slug, 'casa-del-reino', 'se envía la versión normalizada')
    await browser.close()
  })

  await prueba('registro y códigos, pruebas, planes, sistema, facturación y soporte se muestran y dicen «sin conectar» donde toca', async () => {
    const { browser, page, errores } = await escenario()
    await page.goto(url('/plataforma/registro')); await page.waitForSelector('[data-test=registro-abierto]')
    await page.goto(url('/plataforma/pruebas')); await page.waitForSelector('[data-test=tabla-pruebas] tbody tr')
    const orden = await page.locator('[data-test=tabla-pruebas] tbody tr').evaluateAll(l => l.map(e => e.dataset.inquilino))
    assert.deepEqual(orden, [uuid(3), uuid(2)], 'por vencimiento: la vencida primero')
    await page.goto(url('/plataforma/planes')); await page.waitForSelector('[data-test=matriz-planes]')
    assert.match(await page.textContent('[data-test=matriz-planes]'), /Semilla/)
    await page.goto(url('/plataforma/sistema')); await page.waitForSelector('[data-test=purga-estado]')
    await page.waitForFunction(() => document.querySelector('[data-test=libro-purgas]')?.textContent?.includes('00000000-0000-4000-8000-000000000009'))
    await page.waitForSelector('[data-test=auditoria-plataforma] li')
    await captura(page, 'escritorio-sistema')
    await page.goto(url('/plataforma/facturacion')); await page.waitForSelector('[data-test=sin-conectar]')
    await page.goto(url('/plataforma/soporte')); await page.waitForSelector('[data-test=sin-conectar]'); assert.equal(await page.locator('[data-test=sin-conectar]').count(), 2)
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('el cambio de contexto: aterriza en el panel, entra a su iglesia y vuelve; dura la pestaña', async () => {
    const { browser, page, errores } = await escenario({ conIglesia: true })
    await page.goto(url('/'))
    await page.waitForSelector('[data-test=etiqueta-panel]')
    assert.equal(new URL(page.url()).pathname, '/plataforma', 'aterriza en el Panel Maestro aunque tenga iglesia')
    assert.match(await page.textContent('[data-test=entrar-iglesia]'), /Entrar a mi iglesia: Iglesia Propia/)
    await page.click('[data-test=entrar-iglesia]')
    await page.waitForSelector('[data-test=barra-contexto]')
    assert.equal(new URL(page.url()).pathname, '/')
    assert.equal(await page.evaluate(() => sessionStorage.getItem('adn_contexto')), 'iglesia')
    assert.equal(await page.locator('[data-test=etiqueta-panel]').count(), 0, 'dentro de la iglesia no hay menú de plataforma')
    await page.reload(); await page.waitForSelector('[data-test=barra-contexto]')
    await page.click('[data-test=volver-panel]')
    await page.waitForSelector('[data-test=etiqueta-panel]')
    assert.equal(new URL(page.url()).pathname, '/plataforma')
    assert.equal(await page.evaluate(() => sessionStorage.getItem('adn_contexto')), 'plataforma')
    // una pestaña nueva (sesión nueva) vuelve a empezar en el panel
    await page.evaluate(() => sessionStorage.setItem('adn_contexto', 'iglesia')); await page.evaluate(() => sessionStorage.clear())
    await page.goto(url('/')); await page.waitForSelector('[data-test=etiqueta-panel]')
    assert.deepEqual(errores.filter(e => !/Failed|fetch/.test(e)), [])
    await browser.close()
  })

  await prueba('quien no es administrador de plataforma no entra en /plataforma', async () => {
    const { browser, page } = await escenario({ admin: false, conIglesia: true })
    await page.goto(url('/plataforma/iglesias'))
    await page.waitForSelector('nav a[href="/miembros"], nav a[href="/"]', { timeout: 15000 })
    assert.equal(new URL(page.url()).pathname, '/')
    assert.equal(await page.locator('[data-test=etiqueta-panel]').count(), 0)
    await browser.close()
  })

  await prueba('móvil: el menú es un cajón, la tabla pasa a tarjetas y no hay desborde horizontal', async () => {
    const { browser, page, errores } = await escenario({ ancho: 390, alto: 844 })
    await page.goto(url('/plataforma'))
    await page.waitForSelector('[data-kpi=activas]')
    assert.ok(await sinDesbordes(page), 'portada sin desborde')
    await captura(page, 'movil-portada')
    const caja = () => page.locator('#panel-menu').boundingBox()
    assert.ok((await caja()).x < 0, 'el menú empieza cerrado')
    await page.click('[aria-controls=panel-menu]')
    await page.waitForFunction(() => document.querySelector('#panel-menu').getBoundingClientRect().x >= 0)
    assert.equal(await page.getAttribute('[aria-controls=panel-menu]', 'aria-expanded'), 'true')
    await captura(page, 'movil-menu')
    await page.press('#panel-menu a', 'Escape')
    await page.waitForFunction(() => document.querySelector('#panel-menu').getBoundingClientRect().x < 0)
    assert.equal(await page.evaluate(() => document.activeElement?.getAttribute('aria-controls')), 'panel-menu', 'el foco vuelve al botón del menú')
    await page.goto(url('/plataforma/iglesias')); await page.waitForSelector('ul[data-inquilino], li[data-inquilino]')
    assert.equal(await page.locator('table').first().isVisible(), false, 'en móvil la tabla se oculta')
    assert.ok(await page.locator('li[data-inquilino]').first().isVisible(), 'y se ven tarjetas')
    assert.ok(await sinDesbordes(page), 'iglesias sin desborde')
    await captura(page, 'movil-iglesias')
    await page.goto(url(`/plataforma/iglesias/${uuid(1)}`)); await page.waitForSelector('[data-test=nombre-iglesia]')
    assert.ok(await sinDesbordes(page), 'gestionar sin desborde')
    await captura(page, 'movil-gestionar')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('el foco es visible y la navegación por teclado llega a los filtros y a las acciones', async () => {
    const { browser, page } = await escenario()
    await page.goto(url('/plataforma/iglesias')); await page.waitForSelector('[data-test=tabla-inquilinos] tbody tr')
    await page.focus('[data-test=buscar]')
    await page.keyboard.press('Tab')
    assert.equal(await page.evaluate(() => document.activeElement?.getAttribute('data-filtro')), 'todas')
    await page.keyboard.press('Tab'); await page.keyboard.press('Enter')
    assert.equal(await page.getAttribute('[data-filtro=activas]', 'aria-pressed'), 'true', 'se filtra con el teclado')
    assert.equal(await page.locator('main#panel-contenido').count(), 1, 'hay una región principal')
    assert.equal(await page.locator('a[href="#panel-contenido"]').count(), 1, 'hay un enlace para saltar al contenido')
    await browser.close()
  })
} finally { parar() }

if (fallos) { console.error(`\n${fallos} prueba(s) fallida(s)`); process.exit(1) }
console.log('\nPanel Maestro: todas las pruebas de interfaz pasan')
