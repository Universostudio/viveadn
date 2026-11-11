// Prueba de la pantalla de datos y baja del propietario en un navegador real, con la red simulada (no toca ningún servicio).
// Uso: npm run test:datos-ui   (levanta Vite en el puerto 5199 con una dirección de Supabase inventada y la intercepta)
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5199
const SB = 'https://fake.supabase.test'
const IG = '11111111-1111-1111-1111-111111111111'
const USR = '22222222-2222-2222-2222-222222222222'
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

async function escenario({ propietario, activa, baja }) {
  const estado = { baja, descargas: 6, llamadas: [] }
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ acceptDownloads: true, locale: 'es-ES' })
  const sesion = { access_token: 'x.y.z', refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: USR, aud: 'authenticated', email: 'p@prueba.test', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } }
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  const tablas = {
    perfiles: [{ id: USR, iglesia_id: IG, nombre: 'Pro', apellido: 'Pietario', email: 'p@prueba.test', rol: propietario ? 'propietario' : 'administrador', activo: true }],
    iglesias: [{ id: IG, nombre: 'Iglesia de Prueba', slug: 'iglesia-prueba', activa, plan: 'premium', etapa: activa ? 'activa' : 'suspendida' }],
    roles: [{ nombre: propietario ? 'Propietario' : 'Administrador', es_propietario: propietario, rol_permisos: [] }],
  }
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const url = new URL(req.url())
    const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    if (url.pathname.startsWith('/rest/v1/')) {
      const filas = tablas[url.pathname.split('/').pop()] ?? []
      const objeto = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object')
      return ruta.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(objeto ? (filas[0] ?? null) : filas) })
    }
    if (url.pathname === '/functions/v1/datos-iglesia') {
      const cuerpo = req.postDataJSON(); estado.llamadas.push(cuerpo.accion)
      const resp = (status, body) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
      if (!propietario) return resp(403, { error: 'Solo el propietario de la iglesia puede hacerlo' })
      switch (cuerpo.accion) {
        case 'estado': return resp(200, { ok: true, estado: { nombre: 'Iglesia de Prueba', slug: 'iglesia-prueba', etapa: 'activa', baja: estado.baja, descargas_restantes: estado.descargas, plazo_dias: 30 } })
        case 'exportar_plan': estado.descargas--; return resp(200, { ok: true, plan: { formato: 'viveadn-exportacion-2', iglesia_id: IG, exportado_en: '2026-11-11T00:00:00Z', total_filas: 0,
          tablas: [{ nombre: 'zonas', orden_carga: 1, archivo_csv: 'csv/zonas.csv', filas: 0, columnas: [{ nombre: 'id', tipo: 'uuid', obligatoria: true }], omitidas: [], clave: ['id'] }], archivos: {} } })
        case 'exportar_pagina': return resp(200, { ok: true, pagina: cuerpo.formato === 'json' ? { n: 0, json: '[]', hashes: [] } : { n: 0, csv: '' } })
        case 'solicitar_baja':
          if (cuerpo.confirmar !== 'iglesia-prueba') return resp(400, { error: 'La confirmación no coincide' })
          estado.baja = { solicitada_en: '2026-11-11T10:00:00Z', purga_el: '2026-12-11T10:00:00Z', por_la_iglesia: true, cancelable: true }
          return resp(200, { ok: true, purga_el: '2026-12-11T10:00:00Z' })
        case 'cancelar_baja': estado.baja = null; return resp(200, { ok: true, etapa: 'activa' })
      }
      return resp(400, { error: 'Accion no valida' })
    }
    return ruta.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: '[]' })
  })
  const page = await ctx.newPage()
  const errores = []
  page.on('pageerror', e => errores.push(e.message))
  return { browser, page, estado, errores }
}
const url = ruta => `http://localhost:${PUERTO}${ruta}`

try {
  // 1. Propietario con la iglesia activa: descarga y baja
  {
    const { browser, page, estado, errores } = await escenario({ propietario: true, activa: true, baja: null })
    await page.goto(url('/datos-iglesia'))
    await page.waitForSelector('[data-test=descarga]')
    assert.ok(await page.isEnabled('[data-test=descargar]'), 'la descarga está disponible')
    page.on('console', m => { if (process.env.DEPURAR) console.log('consola:', m.text()) })
    const espera = page.waitForEvent('download', { timeout: 15000 }).catch(async e => { throw new Error(`sin descarga; aviso en pantalla: ${await page.textContent('[data-test=aviso]').catch(() => '(ninguno)')}; llamadas: ${estado.llamadas.join(',')}; errores: ${errores.join(' | ')}`) })
    await page.click('[data-test=descargar]')
    const descarga = await espera
    const ruta = await descarga.path()
    assert.equal(readFileSync(ruta).subarray(0, 2).toString(), 'PK', 'lo descargado es un ZIP')
    assert.match(descarga.suggestedFilename(), /^viveadn-iglesia-prueba-\d{4}-\d{2}-\d{2}\.zip$/, 'nombre del archivo')
    await page.waitForSelector('[data-test=aviso]')
    assert.deepEqual(estado.llamadas.filter(a => a === 'exportar_plan').length, 1, 'se pidió un solo plan (una sola anotación de descarga)')
    assert.match(await page.textContent('[data-test=descarga]'), /quedan esta hora: 5/, 'las descargas restantes bajan a 5')
    // Baja: el botón solo se activa con la dirección exacta y la casilla marcada
    assert.ok(await page.isDisabled('[data-test=pedir-baja]'), 'la baja empieza desactivada')
    await page.fill('#baja-confirmar', 'otra-direccion'); await page.check('[data-test=entiendo]')
    assert.ok(await page.isDisabled('[data-test=pedir-baja]'), 'con la dirección equivocada sigue desactivada')
    await page.fill('#baja-confirmar', 'iglesia-prueba')
    assert.ok(await page.isEnabled('[data-test=pedir-baja]'), 'con la dirección exacta y la casilla se activa')
    await page.click('[data-test=pedir-baja]')
    await page.waitForSelector('[data-test=baja-activa]')
    assert.match(await page.textContent('[data-test=baja-activa]'), /11 de diciembre de 2026/, 'muestra la fecha de la purga')
    await page.click('[data-test=cancelar-baja]')
    await page.waitForSelector('[data-test=pedir-baja]')
    assert.equal(estado.baja, null, 'cancelada')
    // Configuración ofrece el enlace al propietario
    await page.goto(url('/configuracion')); await page.click('button:has-text("Seguridad")')
    await page.waitForSelector('[data-test=datos-y-baja]', { timeout: 8000 }).catch(async () => { throw new Error(`sin tarjeta; errores: ${errores.join(" | ")}; url ${page.url()}; texto: ${(await page.locator('body').innerText()).replace(/\n+/g, " | ").slice(0, 1500)}`) })
    assert.equal(await page.locator('[data-test=abrir-datos]').count(), 1, 'el propietario ve el enlace en Configuración')
    assert.deepEqual(errores, [], 'sin errores de página')
    await browser.close()
  }
  // 2. Quien no es propietario solo ve el aviso y no pide nada más
  {
    const { browser, page, estado, errores } = await escenario({ propietario: false, activa: true, baja: null })
    await page.goto(url('/datos-iglesia'))
    await page.waitForSelector('[data-test=solo-propietario]')
    assert.equal(await page.locator('[data-test=descargar]').count(), 0, 'sin botón de descarga')
    assert.equal(await page.locator('[data-test=pedir-baja]').count(), 0, 'sin botón de baja')
    assert.deepEqual(estado.llamadas, ['estado'], 'solo se consultó el estado')
    await page.goto(url('/configuracion')); await page.click('button:has-text("Seguridad")')
    await page.waitForSelector('[data-test=datos-y-baja]')
    assert.equal(await page.locator('[data-test=abrir-datos]').count(), 0, 'Configuración no ofrece el enlace a quien no es propietario')
    assert.equal(await page.locator('[data-test=datos-solo-propietario]').count(), 1, 'y le explica que es del propietario')
    assert.deepEqual(errores, [], 'sin errores de página')
    await browser.close()
  }
  // 3. Iglesia suspendida por una baja propia: el propietario ve el aviso y puede cancelar
  {
    const baja = { solicitada_en: '2026-11-11T10:00:00Z', purga_el: '2026-12-11T10:00:00Z', por_la_iglesia: true, cancelable: true }
    const { browser, page, errores } = await escenario({ propietario: true, activa: false, baja })
    await page.goto(url('/'))
    await page.waitForSelector('[data-test=aviso-suspendida]')
    await page.click('[data-test=aviso-suspendida] a')
    await page.waitForSelector('[data-test=baja-activa]')
    assert.ok(await page.isEnabled('[data-test=cancelar-baja]'), 'se puede cancelar')
    assert.equal(await page.locator('[data-test=aviso-suspendida]').count(), 0, 'en esta página no se repite el aviso')
    assert.deepEqual(errores, [], 'sin errores de página')
    await browser.close()
  }
  // 4. Baja abierta por la plataforma: no hay botón de cancelar
  {
    const baja = { solicitada_en: '2026-11-11T10:00:00Z', purga_el: '2026-12-11T10:00:00Z', por_la_iglesia: false, cancelable: false }
    const { browser, page } = await escenario({ propietario: true, activa: false, baja })
    await page.goto(url('/datos-iglesia'))
    await page.waitForSelector('[data-test=baja-activa]')
    assert.equal(await page.locator('[data-test=cancelar-baja]').count(), 0, 'no se ofrece cancelar una baja de la plataforma')
    await browser.close()
  }
  console.log('OK: pantalla de datos y baja verificada en un navegador (4 escenarios)')
} finally { parar() }
