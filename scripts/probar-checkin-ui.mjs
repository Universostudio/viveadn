// Prueba de la página pública de registro por QR con la pregunta «¿Es nuevo creyente?», en un navegador real con la red simulada.
// Uso: npm run test:checkin-ui   (levanta Vite en el puerto 5194 con una dirección de Supabase inventada y la intercepta)
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5194
const SB = 'https://fake.supabase.test'
const TOKEN = 'a'.repeat(64)
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

async function abrir() {
  const registros = []
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ locale: 'es-ES', viewport: { width: 390, height: 900 } })
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const url = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
    if (url.pathname === '/functions/v1/checkin-evento') {
      const b = req.postDataJSON()
      if (b.accion === 'consultar') return json(200, { estado: 'abierto', iglesia: 'Iglesia de Prueba', evento: 'Culto del domingo', contacto: null, alias: false })
      if (b.accion === 'registrar') { registros.push(b); return json(200, { ok: true }) }
    }
    return json(200, [])
  })
  const page = await ctx.newPage()
  const errores = []
  page.on('pageerror', x => errores.push(x.message))
  await page.goto(`http://localhost:${PUERTO}/checkin/${TOKEN}`)
  await page.waitForSelector('#ck-nombre')
  return { browser, page, registros, errores }
}
async function rellenar(page) {
  await page.fill('#ck-nombre', 'Ana'); await page.fill('#ck-apellido', 'Prueba'); await page.fill('#ck-tel', '+34 600 111 222')
  await page.check('input[type=checkbox] >> nth=0'); await page.check('input[type=checkbox] >> nth=1')
}
let fallos = 0
const prueba = async (n, fn) => { try { await fn(); console.log(`✓ ${n}`) } catch (x) { fallos++; console.error(`✗ ${n}\n   ${x.message}`) } }

try {
  await prueba('la pregunta «¿Es nuevo creyente?» aparece sin respuesta marcada y es obligatoria: sin responder no se envía nada', async () => {
    const { browser, page, registros, errores } = await abrir()
    assert.match(await page.textContent('[data-test=nuevo-creyente]'), /¿Eres nuevo creyente\?/)
    assert.equal(await page.locator('[data-test=nc-si]').isChecked(), false)
    assert.equal(await page.locator('[data-test=nc-no]').isChecked(), false)
    await rellenar(page); await page.click('button[type=submit]')
    await page.waitForSelector('[role=alert]')
    assert.match(await page.textContent('[role=alert]'), /Elige una respuesta/)
    assert.equal(registros.length, 0, 'no se llama al servidor sin respuesta')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  for (const [boton, esperado] of [['nc-si', true], ['nc-no', false]]) {
    await prueba(`responder ${esperado ? 'Sí' : 'No'} envía nuevo_creyente: ${esperado} exactamente`, async () => {
      const { browser, page, registros } = await abrir()
      await rellenar(page); await page.check(`[data-test=${boton}]`); await page.click('button[type=submit]')
      await page.waitForSelector('[role=status]')
      assert.equal(registros.length, 1)
      assert.strictEqual(registros[0].nuevo_creyente, esperado)
      assert.equal(registros[0].nombre, 'Ana')
      await browser.close()
    })
  }

  await prueba('cambiar de opinión antes de enviar manda la última respuesta, y las dos opciones se alcanzan con teclado', async () => {
    const { browser, page, registros } = await abrir()
    await rellenar(page)
    await page.focus('[data-test=nc-si]'); await page.keyboard.press('Space')
    assert.equal(await page.locator('[data-test=nc-si]').isChecked(), true)
    await page.keyboard.press('ArrowDown')
    assert.equal(await page.locator('[data-test=nc-no]').isChecked(), true, 'las flechas pasan de una opción a otra')
    await page.click('button[type=submit]'); await page.waitForSelector('[role=status]')
    assert.strictEqual(registros[0].nuevo_creyente, false)
    await browser.close()
  })
} finally { parar() }

if (fallos) { console.error(`\n${fallos} prueba(s) fallida(s)`); process.exit(1) }
console.log('\nRegistro por QR: todas las pruebas de interfaz pasan')
