// Prueba de la pantalla de seguimiento de nuevos convertidos en un navegador real, con la red simulada (no toca ningún servicio).
// Uso: npm run test:seguimiento-ui   (levanta Vite en el puerto 5197 con una dirección de Supabase inventada y la intercepta)
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5197
const SB = 'https://fake.supabase.test'
const IG = '11111111-1111-1111-1111-111111111111'
const USR = '22222222-2222-2222-2222-222222222222'
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

const hace = h => new Date(Date.now() - h * 3600000).toISOString()
const permisosCatalogo = ['consolidacion.ver', 'consolidacion.ver_asignados', 'consolidacion.ver_casa', 'consolidacion.crear', 'consolidacion.editar', 'consolidacion.reasignar', 'consolidacion.registrar_contacto', 'miembros.ver', 'miembros.ver_asignados', 'usuarios.ver']
const ROLES = {
  consolidador: ['consolidacion.ver_asignados', 'consolidacion.registrar_contacto', 'miembros.ver_asignados', 'usuarios.ver'],
  administrador: ['consolidacion.ver', 'consolidacion.crear', 'consolidacion.editar', 'consolidacion.reasignar', 'consolidacion.registrar_contacto', 'miembros.ver', 'usuarios.ver'],
  lider_casa: ['consolidacion.ver_casa', 'miembros.ver_asignados', 'usuarios.ver'],
}

async function escenario(rol, { patchFalla = false, pais = 'España' } = {}) {
  const estado = { patches: [], filas: [
    { id: 'c1', miembro_id: 'm1', consolidador_id: USR, fecha_conversion: hace(10), fecha_limite: hace(-62), estado_alerta: 'verde', completado: false, notas: null,
      primer_contacto_fecha: null, primer_contacto_notas: null, segundo_contacto_fecha: null, segundo_contacto_notas: null, tercer_contacto_fecha: null, tercer_contacto_notas: null,
      miembros: { id: 'm1', nombre: 'Ana', apellido: 'Prueba', crm_id: 'ADN-001', telefono: '+34 600 111 222' }, consolidador_perfil: { nombre: 'Con', apellido: 'Solidador' } },
    { id: 'c2', miembro_id: 'm2', consolidador_id: null, fecha_conversion: hace(30), fecha_limite: hace(-42), estado_alerta: 'amarillo', completado: false, notas: 'Vino con un amigo',
      primer_contacto_fecha: null, primer_contacto_notas: null, segundo_contacto_fecha: null, segundo_contacto_notas: null, tercer_contacto_fecha: null, tercer_contacto_notas: null,
      miembros: { id: 'm2', nombre: 'Beto', apellido: 'Ejemplo', crm_id: 'ADN-002', telefono: null }, consolidador_perfil: null },
    { id: 'c3', miembro_id: 'm3', consolidador_id: USR, fecha_conversion: hace(5), fecha_limite: hace(-67), estado_alerta: 'verde', completado: false, notas: null,
      primer_contacto_fecha: null, primer_contacto_notas: null, segundo_contacto_fecha: null, segundo_contacto_notas: null, tercer_contacto_fecha: null, tercer_contacto_notas: null,
      miembros: { id: 'm3', nombre: 'Cleo', apellido: 'Muestra', crm_id: 'ADN-003', telefono: '600 333 444' }, consolidador_perfil: { nombre: 'Con', apellido: 'Solidador' } },
  ] }
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ locale: 'es-ES', viewport: { width: 1280, height: 900 } })
  const sesion = { access_token: 'x.y.z', refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: USR, aud: 'authenticated', email: 'p@prueba.test', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } }
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  const tablas = {
    perfiles: [{ id: USR, iglesia_id: IG, nombre: 'Yo', apellido: 'Mismo', email: 'p@prueba.test', rol, activo: true },
      { id: '33333333-3333-3333-3333-333333333333', iglesia_id: IG, nombre: 'Con', apellido: 'Solidadora', rol: 'consolidador', activo: true },
      { id: '44444444-4444-4444-4444-444444444444', iglesia_id: IG, nombre: 'Lider', apellido: 'Casa', rol: 'lider_casa', activo: true }],
    iglesias: [{ id: IG, nombre: 'Iglesia de Prueba', slug: 'prueba', activa: true, plan: 'premium', etapa: 'activa', pais }],
    // Una fila por clave; la del propio usuario va primera (la aplicación pide la suya con maybeSingle)
    roles: [rol, ...['consolidador', 'lider_casa'].filter(c => c !== rol)].map(clave => ({ clave, nombre: clave, es_propietario: false, rol_permisos: ROLES[clave].map(permiso => ({ permiso })) })),
    plan_modulos: [{ modulo: 'consolidacion' }, { modulo: 'miembros' }, { modulo: 'usuarios' }],
    iglesia_modulos: [],
    permisos: permisosCatalogo.map(clave => ({ clave, modulo: clave.startsWith('consolidacion') ? 'consolidacion' : clave.startsWith('miembros') ? 'miembros' : 'usuarios' })),
    plataforma_admins: [],
    consolidaciones: estado.filas,
    miembros: [{ id: 'm1', nombre: 'Ana', apellido: 'Prueba', crm_id: 'ADN-001' }, { id: 'm4', nombre: 'Dani', apellido: 'Nuevo', crm_id: 'ADN-004' }],
  }
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const url = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
    if (url.pathname.startsWith('/rest/v1/rpc/')) return json(200, {})
    if (url.pathname.startsWith('/rest/v1/')) {
      const tabla = url.pathname.split('/').pop()
      if (req.method() === 'PATCH') {
        const cuerpo = req.postDataJSON(); const id = (url.searchParams.get('id') ?? '').replace('eq.', '')
        estado.patches.push({ tabla, id, cuerpo })
        if (patchFalla) return json(403, { message: 'sin permiso' })
        const fila = estado.filas.find(f => f.id === id); if (fila) Object.assign(fila, cuerpo)
        return ruta.fulfill({ status: 204, headers: cors })
      }
      // Filtros eq. sencillos, como los que manda la aplicación (sin ellos, maybeSingle recibiría varias filas)
      let filas = tablas[tabla] ?? []
      for (const [k, v] of url.searchParams) if (v.startsWith('eq.') && filas.some(f => k in f)) filas = filas.filter(f => String(f[k]) === v.slice(3))
      const objeto = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object')
      return json(200, objeto ? (filas[0] ?? null) : filas)
    }
    return json(200, [])
  })
  const page = await ctx.newPage()
  const errores = []
  page.on('pageerror', e => errores.push(e.message))
  return { browser, page, estado, errores }
}
const url = r => `http://localhost:${PUERTO}${r}`
let fallos = 0
const prueba = async (n, fn) => { try { await fn(); console.log(`✓ ${n}`) } catch (e) { fallos++; console.error(`✗ ${n}\n   ${e.message}`) } }
const abrir = async page => { await page.goto(url('/consolidacion')); await page.waitForSelector('[data-consolidacion]') }

try {
  await prueba('el consolidador no ve «Nuevo convertido», pero sí llamar, WhatsApp y registrar contacto', async () => {
    const { browser, page, errores } = await escenario('consolidador')
    await abrir(page)
    assert.equal(await page.locator('[data-test=nuevo-convertido]').count(), 0, 'el botón de crear no se ofrece sin permiso')
    const c1 = '[data-consolidacion=c1]'
    assert.equal(await page.getAttribute(`${c1} [data-test=llamar]`, 'href'), 'tel:+34600111222')
    assert.equal(await page.getAttribute(`${c1} [data-test=whatsapp]`, 'href'), 'https://wa.me/34600111222')
    assert.match(await page.getAttribute(`${c1} [data-test=llamar]`, 'aria-label'), /Llamar a Ana Prueba/)
    assert.equal(await page.getAttribute(`${c1} [data-test=whatsapp]`, 'target'), '_blank')
    assert.match(await page.getAttribute(`${c1} [data-test=whatsapp]`, 'rel'), /noopener/)
    // sin teléfono: se dice, no hay enlaces
    assert.equal(await page.locator('[data-consolidacion=c2] [data-test=llamar]').count(), 0)
    assert.equal(await page.locator('[data-consolidacion=c2] [data-test=sin-telefono]').count(), 1)
    // país conocido: el número sin prefijo se completa
    assert.equal(await page.getAttribute('[data-consolidacion=c3] [data-test=whatsapp]', 'href'), 'https://wa.me/34600333444')
    assert.equal(await page.locator('[data-consolidacion=c1] [data-test=sin-asignar]').count(), 0)
    assert.equal(await page.locator('[data-consolidacion=c2] [data-test=sin-asignar]').count(), 1, 'una sin asignar lo dice')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('registrar contactos: fecha y nota, tres como máximo, no futuros, y el error del servidor se ve', async () => {
    const { browser, page, estado } = await escenario('consolidador')
    await abrir(page)
    await page.click('[data-consolidacion=c1] [data-test=registrar-contacto]')
    await page.waitForSelector('[data-test=detalle]')
    assert.equal(await page.locator('[data-test=asignar]').count(), 0, 'un consolidador no reasigna')
    assert.equal(await page.evaluate(() => document.querySelectorAll('[data-test=contacto]').length), 0)
    // futura: se rechaza sin llamar al servidor
    const futura = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 16)
    await page.fill('[data-test=contacto-fecha]', futura); await page.fill('[data-test=contacto-nota]', 'No debería guardarse')
    await page.click('[data-test=guardar-contacto]')
    await page.waitForSelector('[data-test=error-contacto]')
    assert.equal(estado.patches.length, 0)
    // tres contactos válidos
    const pasada = h => { const d = new Date(Date.now() - h * 3600000); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16) }
    for (const [i, nota] of ['Llamada: no contestó', 'Hablamos 10 min, viene el domingo', 'Vino al culto'].entries()) {
      await page.fill('[data-test=contacto-fecha]', pasada(5 - i)); await page.fill('[data-test=contacto-nota]', nota)
      await page.click('[data-test=guardar-contacto]')
      await page.waitForFunction(n => document.querySelectorAll('[data-test=contacto]').length === n, i + 1)
    }
    assert.deepEqual(estado.patches.map(p => Object.keys(p.cuerpo).sort()), [
      ['primer_contacto_fecha', 'primer_contacto_notas'], ['segundo_contacto_fecha', 'segundo_contacto_notas'], ['tercer_contacto_fecha', 'tercer_contacto_notas']], 'cada contacto usa su hueco')
    assert.equal(estado.patches[1].cuerpo.segundo_contacto_notas, 'Hablamos 10 min, viene el domingo')
    assert.ok(estado.patches.every(p => p.tabla === 'consolidaciones' && p.id === 'c1'), 'siempre sobre la consolidación abierta')
    assert.equal(await page.locator('[data-test=contactos-completos]').count(), 1, 'con tres, el formulario se cierra y lo explica')
    assert.equal(await page.locator('[data-test=guardar-contacto]').count(), 0)
    await browser.close()
  })

  await prueba('si el servidor rechaza el contacto, la pantalla lo dice y no lo da por guardado', async () => {
    const { browser, page } = await escenario('consolidador', { patchFalla: true })
    await abrir(page)
    await page.click('[data-consolidacion=c1] [data-test=registrar-contacto]')
    await page.waitForSelector('[data-test=detalle]')
    await page.fill('[data-test=contacto-nota]', 'Intento')
    await page.click('[data-test=guardar-contacto]')
    await page.waitForSelector('[data-test=error-contacto]')
    assert.equal(await page.locator('[data-test=contacto]').count(), 0, 'no aparece como guardado')
    await browser.close()
  })

  await prueba('un número sin prefijo y un país desconocido: no se adivina el WhatsApp y se explica', async () => {
    const { browser, page } = await escenario('consolidador', { pais: 'Narnia' })
    await abrir(page)
    assert.equal(await page.locator('[data-consolidacion=c3] [data-test=whatsapp]').count(), 0)
    assert.equal(await page.locator('[data-consolidacion=c3] [data-test=sin-prefijo]').count(), 1)
    assert.equal(await page.locator('[data-consolidacion=c3] [data-test=llamar]').count(), 1, 'llamar sigue disponible')
    assert.equal(await page.locator('[data-consolidacion=c1] [data-test=whatsapp]').count(), 1, 'con prefijo internacional sí')
    await browser.close()
  })

  await prueba('el administrador crea y asigna consolidador (solo candidatos con el permiso)', async () => {
    const { browser, page, estado } = await escenario('administrador')
    await abrir(page)
    assert.equal(await page.locator('[data-test=nuevo-convertido]').count(), 1)
    await page.click('[data-consolidacion=c2] [data-test=ver-detalles]')
    await page.waitForSelector('[data-test=asignar]')
    const opciones = await page.locator('[data-test=asignar] option').allTextContents()
    assert.ok(opciones.some(o => /Con Solidadora/.test(o)), 'el consolidador es candidato')
    assert.ok(!opciones.some(o => /Lider Casa/.test(o)), 'el líder de casa no (su rol no registra contactos)')
    await page.selectOption('[data-test=asignar]', '33333333-3333-3333-3333-333333333333')
    await page.waitForFunction(() => document.querySelector('[data-test=aviso]')?.textContent?.includes('Consolidador actualizado'))
    const p = estado.patches.find(x => x.cuerpo.consolidador_id)
    assert.deepEqual({ id: p?.id, c: p?.cuerpo.consolidador_id }, { id: 'c2', c: '33333333-3333-3333-3333-333333333333' })
    await browser.close()
  })

  await prueba('el líder de casa solo ve: sin crear, sin completar, sin registrar contactos, sin reasignar', async () => {
    const { browser, page } = await escenario('lider_casa')
    await abrir(page)
    for (const sel of ['[data-test=nuevo-convertido]', '[data-test=completar]', '[data-test=registrar-contacto]']) assert.equal(await page.locator(sel).count(), 0, sel)
    await page.click('[data-consolidacion=c1] [data-test=ver-detalles]')
    await page.waitForSelector('[data-test=detalle]')
    assert.equal(await page.locator('[data-test=asignar]').count(), 0)
    assert.equal(await page.locator('[data-test=guardar-contacto]').count(), 0)
    assert.equal(await page.locator('[data-consolidacion=c1] [data-test=llamar]').count(), 1, 'sí puede llamar')
    await page.press('[data-test=detalle]', 'Escape')
    await page.waitForFunction(() => !document.querySelector('[data-test=detalle]'))
    await browser.close()
  })
} finally { parar() }

if (fallos) { console.error(`\n${fallos} prueba(s) fallida(s)`); process.exit(1) }
console.log('\nSeguimiento: todas las pruebas de interfaz pasan')
