// Prueba del soporte dentro de la plataforma en un navegador real, con la red simulada y con estado: lado de la iglesia (novedades con aviso en el menú,
// avisos descartables, tickets con validación y conversación) y lado de la plataforma (tickets, novedades, avisos con destinatarios y registro de entrega).
// Uso: npm run test:soporte-ui   (levanta Vite en el puerto 5200 con una dirección de Supabase inventada y la intercepta; no toca ningún servicio)
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import assert from 'node:assert/strict'
const { chromium } = createRequire(import.meta.url)('playwright')

const PUERTO = 5200
const SB = 'https://fake.supabase.test'
const IG = '11111111-1111-1111-1111-111111111111'
const USR = '22222222-2222-2222-2222-222222222222'
const vite = spawn('npx', ['vite', '--port', String(PUERTO), '--strictPort'], { env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_ANON_KEY: 'anon-de-prueba' }, stdio: 'ignore' })
const parar = () => { try { vite.kill('SIGTERM') } catch { /* ya parado */ } }
process.on('exit', parar)
for (let i = 0; i < 60; i++) { try { if ((await fetch(`http://localhost:${PUERTO}/`)).ok) break } catch { /* aún no */ } await new Promise(r => setTimeout(r, 500)) }

const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*', 'access-control-expose-headers': '*' }
const sesion = { access_token: 'x.y.z', refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
  user: { id: USR, aud: 'authenticated', email: 'p@prueba.test', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } }
const url = r => `http://localhost:${PUERTO}${r}`
let fallos = 0
const prueba = async (n, fn) => { try { await fn(); console.log(`✓ ${n}`) } catch (x) { fallos++; console.error(`✗ ${n}\n   ${x.message}`) } }

// ---------- Lado de la iglesia ----------
async function iglesia({ tablas = true, rol = 'propietario', sinVer = 2, avisos = true, rpcFalla = null } = {}) {
  const e = { rpc: [], escrituras: [], sinVer, entregas: avisos ? [
    { aviso_id: 'av1', leido_en: null, descartado_en: null, aviso: { id: 'av1', tipo: 'alerta', titulo: 'Mantenimiento urgente', texto: 'Esta noche no habrá servicio.' } },
    { aviso_id: 'av2', leido_en: null, descartado_en: null, aviso: { id: 'av2', tipo: 'actualizacion', titulo: 'Versión nueva', texto: 'Ya puedes ver las novedades.' } },
  ] : [], tickets: [{ id: 't1', asunto: 'No carga la lista', prioridad: 'alta', estado: 'respondido', updated_at: '2026-11-10T10:00:00Z' }],
  mensajes: [{ id: 1, ticket_id: 't1', autor_tipo: 'iglesia', texto: 'La lista de miembros no abre.', created_at: '2026-11-10T09:00:00Z' }, { id: 2, ticket_id: 't1', autor_tipo: 'plataforma', texto: 'Ya lo estamos mirando.', created_at: '2026-11-10T10:00:00Z' }] }
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ locale: 'es-ES', viewport: { width: 1280, height: 1000 } })
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  const permisos = rol === 'propietario' ? [] : [{ permiso: 'miembros.ver' }]
  const filasDe = t => ({
    perfiles: [{ id: USR, iglesia_id: IG, nombre: 'Yo', apellido: 'Mismo', email: 'p@prueba.test', rol, activo: true }],
    iglesias: [{ id: IG, nombre: 'Iglesia de Prueba', slug: 'prueba', activa: true, plan: 'premium', etapa: 'activa', pais: 'España' }],
    roles: [{ clave: 'propietario', nombre: 'Superadministrador', es_propietario: true, rol_permisos: [] }, { clave: 'colaborador', nombre: 'Colaborador', es_propietario: false, rol_permisos: permisos }],
    plan_modulos: ['iglesia', 'miembros'].map(modulo => ({ modulo })), iglesia_modulos: [],
    permisos: [{ clave: 'iglesia.configurar', modulo: 'iglesia' }, { clave: 'miembros.ver', modulo: 'miembros' }],
    plataforma_admins: [], usuarios: [], invitaciones: [], miembros: [],
    adn_novedades: [{ id: 'n1', version: '1.4.0', titulo: 'Soporte dentro de la plataforma', texto: 'Ahora puedes escribirnos desde aquí.', publicada_en: '2026-11-11T08:00:00Z' }, { id: 'n0', version: '1.3.0', titulo: 'Cifras coherentes', texto: 'Las cifras ya cuadran.', publicada_en: '2026-10-01T08:00:00Z' }],
    adn_novedades_vistas: [], adn_avisos_entregas: e.entregas.filter(x => !x.descartado_en), adn_tickets: e.tickets, adn_ticket_mensajes: e.mensajes,
  })[t] ?? []
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const u = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body, extra = {}) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json', ...extra }, body: JSON.stringify(body) })
    if (!u.pathname.startsWith('/rest/v1/')) return json(200, [])
    const tabla = u.pathname.split('/').pop()
    if (u.pathname.includes('/rpc/')) {
      e.rpc.push({ nombre: tabla, cuerpo: req.postDataJSON() })
      if (tabla === 'adn_novedades_marcar_vistas') { e.sinVer = 0; return json(200, null) }
      if (rpcFalla) return json(rpcFalla.status, { message: rpcFalla.message, code: rpcFalla.code })
      if (tabla === 'adn_ticket_crear') { e.tickets.unshift({ id: 't2', asunto: req.postDataJSON().p_asunto, prioridad: req.postDataJSON().p_prioridad, estado: 'abierto', updated_at: new Date().toISOString() }); return json(200, 't2') }
      return json(200, null)
    }
    if (!tablas && tabla.startsWith('adn_') && ['adn_novedades', 'adn_novedades_vistas', 'adn_avisos_entregas', 'adn_tickets', 'adn_ticket_mensajes'].includes(tabla)) return json(404, { message: 'relation does not exist', code: '42P01' })
    if (req.method() === 'PATCH' || req.method() === 'POST') {
      const cuerpo = req.postDataJSON(); e.escrituras.push({ metodo: req.method(), tabla, cuerpo, filtro: u.search })
      if (tabla === 'adn_avisos_entregas' && req.method() === 'PATCH') {
        const id = u.searchParams.get('aviso_id')?.replace('eq.', '')
        for (const x of e.entregas) if (!id || x.aviso_id === id) Object.assign(x, cuerpo)
      }
      if (tabla === 'adn_ticket_mensajes' && req.method() === 'POST') e.mensajes.push({ id: 9, ticket_id: cuerpo.ticket_id, autor_tipo: 'iglesia', texto: cuerpo.texto, created_at: new Date().toISOString() })
      return ruta.fulfill({ status: 201, headers: cors })
    }
    let filas = filasDe(tabla)
    for (const [k, v] of u.searchParams) if (v.startsWith('eq.') && filas.some(f => k in f)) filas = filas.filter(f => String(f[k]) === v.slice(3))
    if (req.method() === 'HEAD') return ruta.fulfill({ status: 200, headers: { ...cors, 'content-range': `*/${tabla === 'adn_novedades' ? e.sinVer : filas.length}` } })
    const objeto = (req.headers()['accept'] ?? '').includes('vnd.pgrst.object')
    if (objeto) return json(200, filas[0] ?? null)
    return json(200, filas, { 'content-range': `0-${Math.max(0, filas.length - 1)}/${filas.length}` })
  })
  const page = await ctx.newPage(); const errores = []
  page.on('pageerror', x => errores.push(x.message))
  return { browser, page, e, errores }
}

// ---------- Lado de la plataforma ----------
async function plataforma({ resumen = 'ok', ticketsVacios = false } = {}) {
  const e = { cuerpos: [], tickets: [{ id: 't1', iglesia_id: IG, iglesia: 'Casa del Reino', asunto: 'No carga la lista', prioridad: 'alta', estado: 'abierto', creado: '2026-11-10T09:00:00Z', actualizado: '2026-11-10T09:00:00Z', cerrado: null, mensajes: 1 }], conv: [{ id: 1, de: 'iglesia', texto: 'La lista de miembros no abre.', fecha: '2026-11-10T09:00:00Z' }], novedades: [], avisos: [] }
  if (ticketsVacios) e.tickets = []
  const browser = await chromium.launch()
  const ctx = await browser.newContext({ locale: 'es-ES', viewport: { width: 1366, height: 1100 } })
  await ctx.addInitScript(s => localStorage.setItem('sb-fake-auth-token', s), JSON.stringify(sesion))
  await ctx.route(`${SB}/**`, async ruta => {
    const req = ruta.request(); const u = new URL(req.url())
    if (req.method() === 'OPTIONS') return ruta.fulfill({ status: 204, headers: cors })
    const json = (status, body) => ruta.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
    if (u.pathname.startsWith('/rest/v1/')) {
      const t = u.pathname.split('/').pop()
      const filas = t === 'plataforma_admins' ? [{ user_id: USR }] : []
      return json(200, (req.headers()['accept'] ?? '').includes('vnd.pgrst.object') ? (filas[0] ?? null) : filas)
    }
    if (u.pathname !== '/functions/v1/plataforma') return json(200, [])
    const c = req.postDataJSON(); e.cuerpos.push(c)
    switch (c.accion) {
      case 'listar': return json(200, { iglesias: [], planes: [{ id: 'semilla', nombre: 'Semilla' }, { id: 'premium', nombre: 'Premium' }], modulos: [], plan_modulos: [] })
      case 'registro_estado': return json(200, { abierto: false, requiere_codigo: true, codigos: [] })
      case 'estado_purga': return json(200, { ok: true, atrasada: false, en_borrado: 0, vencidas: 0, horas_mas_atrasada: 0 })
      case 'soporte_resumen':
        if (resumen === 'falta') return json(501, { error: 'El soporte no esta disponible hasta aplicar su migracion' })
        if (resumen === 'error') return json(500, { error: 'No se pudo leer el soporte' })
        return json(200, { ok: true, tickets: { abiertos: e.tickets.filter(x => x.estado === 'abierto').length, respondidos: e.tickets.filter(x => x.estado === 'respondido').length, cerrados: 0, urgentes: 1 }, novedades: { total: e.novedades.length, ultima: null }, avisos: { vigentes: e.avisos.filter(x => !x.retirado_en).length, entregas: 0, leidos: 0, descartados: 0 } })
      case 'ticket_listar': return json(200, { ok: true, tickets: e.tickets })
      case 'ticket_abrir': return json(200, { ok: true, ticket: { ...e.tickets[0], conversacion: e.conv }, auditado: true })
      case 'ticket_responder': e.conv.push({ id: 2, de: 'plataforma', texto: c.texto, fecha: new Date().toISOString() }); e.tickets[0].estado = 'respondido'; return json(200, { ok: true, auditado: true })
      case 'ticket_cerrar': e.tickets[0].estado = 'cerrado'; return json(200, { ok: true, auditado: true })
      case 'novedad_listar': return json(200, { ok: true, novedades: e.novedades })
      case 'novedad_publicar': e.novedades.unshift({ id: 'n1', version: c.version, titulo: c.titulo, texto: c.texto, publicada_en: new Date().toISOString(), retirada_en: null }); return json(200, { ok: true, id: 'n1', auditado: true })
      case 'novedad_retirar': e.novedades[0].retirada_en = new Date().toISOString(); return json(200, { ok: true, auditado: true })
      case 'aviso_listar': return json(200, { ok: true, avisos: e.avisos })
      case 'aviso_crear': e.avisos.unshift({ id: 'a1', tipo: c.tipo, titulo: c.titulo, texto: c.texto, destino: c.destino, created_at: new Date().toISOString(), retirado_en: null, por_correo: c.por_correo, correo_estado: c.por_correo ? 'apagado' : 'no_pedido', entregas: 4, leidos: 1, descartados: 0 }); return json(200, { ok: true, id: 'a1', entregas: 4, correo: c.por_correo ? 'apagado' : 'no_pedido', auditado: true })
      case 'aviso_retirar': e.avisos[0].retirado_en = new Date().toISOString(); return json(200, { ok: true, auditado: true })
      default: return json(200, { ok: true })
    }
  })
  const page = await ctx.newPage(); const errores = []
  page.on('pageerror', x => errores.push(x.message))
  return { browser, page, e, errores }
}

try {
  await prueba('iglesia: el menú ofrece Novedades con aviso de 2 sin ver y Soporte; ver las novedades apaga el aviso', async () => {
    const { browser, page, e, errores } = await iglesia()
    await page.goto(url('/miembros'))
    await page.waitForSelector('a[href="/novedades"]')
    assert.equal(await page.locator('a[href="/soporte"]').count(), 1)
    await page.waitForSelector('[data-test=badge-novedades]')
    assert.equal((await page.locator('[data-test=badge-novedades]').innerText()).trim(), '2')
    await page.click('a[href="/novedades"]')
    await page.waitForSelector('[data-novedad=n1]')
    assert.equal(await page.locator('[data-test=novedad-nueva]').count(), 2, 'sin visita previa, las dos son nuevas')
    assert.match(await page.locator('[data-novedad=n1]').innerText(), /Versión 1\.4\.0/)
    await page.waitForFunction(() => !document.querySelector('[data-test=badge-novedades]'))
    assert.ok(e.rpc.some(r => r.nombre === 'adn_novedades_marcar_vistas'))
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('iglesia: los avisos salen con su tipo, quedan como leídos y se pueden descartar', async () => {
    const { browser, page, e } = await iglesia()
    await page.goto(url('/miembros'))
    await page.waitForSelector('[data-aviso=av1]')
    assert.equal(await page.locator('[data-aviso=av1]').getAttribute('role'), 'alert')
    assert.equal(await page.locator('[data-aviso=av2]').getAttribute('role'), 'status')
    assert.equal(await page.locator('[data-aviso]').first().getAttribute('data-aviso'), 'av1', 'la alerta va primero')
    assert.ok(e.escrituras.some(x => x.tabla === 'adn_avisos_entregas' && x.cuerpo.leido_en), 'se marca leído al mostrarse')
    await page.locator('[data-aviso=av1] [data-test=descartar-aviso]').click()
    await page.waitForFunction(() => !document.querySelector('[data-aviso=av1]'))
    assert.equal(await page.locator('[data-aviso=av2]').count(), 1)
    assert.ok(e.escrituras.some(x => x.tabla === 'adn_avisos_entregas' && x.cuerpo.descartado_en && x.filtro.includes('av1')))
    await browser.close()
  })

  await prueba('iglesia: un ticket vacío no se envía y avisa por campo; uno válido llama a la función y se abre su conversación', async () => {
    const { browser, page, e } = await iglesia()
    await page.goto(url('/soporte'))
    await page.waitForSelector('[data-test=soporte-nuevo]')
    await page.click('[data-test=s-enviar]')
    assert.match(await page.locator('[data-test=s-e-asunto]').innerText(), /al menos 3 letras/)
    assert.match(await page.locator('[data-test=s-e-texto]').innerText(), /Escribe el mensaje/)
    assert.equal(e.rpc.filter(r => r.nombre === 'adn_ticket_crear').length, 0, 'sin datos válidos no se llama')
    await page.fill('[data-test=s-asunto]', 'Error al importar')
    await page.selectOption('[data-test=s-prioridad]', 'urgente')
    await page.fill('[data-test=s-texto]', 'El archivo CSV se queda cargando.')
    await page.click('[data-test=s-enviar]')
    await page.waitForSelector('[data-test=soporte-conversacion]')
    const c = e.rpc.find(r => r.nombre === 'adn_ticket_crear').cuerpo
    assert.deepEqual(c, { p_asunto: 'Error al importar', p_prioridad: 'urgente', p_texto: 'El archivo CSV se queda cargando.' })
    assert.match(await page.locator('[data-test=soporte-aviso]').innerText(), /Ticket creado/)
    assert.equal(await page.locator('[data-ticket=t2]').count(), 1)
    await browser.close()
  })

  await prueba('iglesia: se abre un ticket respondido, se lee la conversación y se responde', async () => {
    const { browser, page, e } = await iglesia()
    await page.goto(url('/soporte'))
    await page.click('[data-ticket=t1] button')
    await page.waitForSelector('[data-de=plataforma]')
    assert.match(await page.locator('[data-de=plataforma]').innerText(), /Ya lo estamos mirando/)
    await page.fill('[data-test=s-resp]', 'Gracias, ahora sí abre.')
    await page.click('[data-test=s-responder]')
    await page.waitForFunction(() => document.querySelectorAll('[data-de=iglesia]').length === 2)
    const w = e.escrituras.find(x => x.tabla === 'adn_ticket_mensajes')
    assert.deepEqual(w.cuerpo, { ticket_id: 't1', texto: 'Gracias, ahora sí abre.' })
    await browser.close()
  })

  await prueba('iglesia: demasiados tickets abiertos se explica en claro', async () => {
    const { browser, page } = await iglesia({ rpcFalla: { status: 400, message: 'ADN_DEMASIADOS_TICKETS', code: 'P0001' } })
    await page.goto(url('/soporte'))
    await page.fill('[data-test=s-asunto]', 'Otra duda'); await page.fill('[data-test=s-texto]', 'Texto.')
    await page.click('[data-test=s-enviar]')
    assert.match(await page.locator('[data-test=soporte-error]').innerText(), /10 tickets abiertos/)
    await browser.close()
  })

  await prueba('iglesia: sin las tablas en la base no hay menú ni avisos, y la pantalla lo dice sin inventar nada', async () => {
    const { browser, page, errores } = await iglesia({ tablas: false })
    await page.goto(url('/miembros'))
    await page.waitForSelector('nav')
    await page.waitForTimeout(600)
    assert.equal(await page.locator('a[href="/soporte"]').count(), 0)
    assert.equal(await page.locator('a[href="/novedades"]').count(), 0)
    assert.equal(await page.locator('[data-test=avisos]').count(), 0)
    await page.goto(url('/soporte'))
    await page.waitForSelector('[data-test=soporte-no-disponible]')
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('iglesia: un rol sin permiso de configurar ve Novedades pero no Soporte', async () => {
    const { browser, page } = await iglesia({ rol: 'colaborador' })
    await page.goto(url('/miembros'))
    await page.waitForSelector('a[href="/novedades"]')
    assert.equal(await page.locator('a[href="/soporte"]').count(), 0)
    await browser.close()
  })

  await prueba('plataforma: cifras, lista de tickets sin texto, y al abrir uno se ve la conversación; responder y cerrar', async () => {
    const { browser, page, e, errores } = await plataforma()
    await page.goto(url('/plataforma/soporte'))
    await page.waitForSelector('[data-test=pm-tickets]')
    assert.equal((await page.locator('[data-test=cifra-abiertos]').innerText()).trim(), '1')
    const lista = await page.locator('[data-ticket=t1]').innerText()
    assert.match(lista, /No carga la lista/); assert.match(lista, /Casa del Reino/)
    assert.doesNotMatch(lista, /lista de miembros no abre/, 'la lista no trae el texto')
    assert.equal(e.cuerpos.filter(c => c.accion === 'ticket_abrir').length, 0, 'sin abrir no se lee el texto')
    await page.click('[data-ticket=t1] button')
    await page.waitForSelector('[data-test=pm-ticket-abierto]')
    assert.match(await page.locator('[data-test=pm-ticket-abierto]').innerText(), /lista de miembros no abre/)
    await page.fill('[data-test=pm-resp]', 'Estamos en ello.')
    await page.click('[data-test=pm-enviar-resp]')
    await page.waitForSelector('[data-de=plataforma]')
    assert.deepEqual(e.cuerpos.find(c => c.accion === 'ticket_responder'), { accion: 'ticket_responder', id: 't1', texto: 'Estamos en ello.', origen: `http://localhost:${PUERTO}` })
    await page.click('[data-test=pm-cerrar-ticket]')
    await page.waitForFunction(() => !document.querySelector('[data-test=pm-cerrar-ticket]'))
    assert.ok(e.cuerpos.some(c => c.accion === 'ticket_cerrar'))
    assert.deepEqual(errores, [])
    await browser.close()
  })

  await prueba('plataforma: el contador del menú sale de los tickets abiertos', async () => {
    const { browser, page } = await plataforma()
    await page.goto(url('/plataforma'))
    await page.waitForSelector('a[href="/plataforma/soporte"]')
    await page.waitForFunction(() => /1/.test(document.querySelector('a[href="/plataforma/soporte"]')?.textContent ?? ''))
    await browser.close()
  })

  await prueba('plataforma: publicar una novedad y retirarla', async () => {
    const { browser, page, e } = await plataforma()
    await page.goto(url('/plataforma/soporte'))
    await page.click('[data-pestana=novedades]')
    await page.waitForSelector('[data-test=pm-novedades-vacio]')
    await page.fill('[data-test=nv-version]', '1.5.0'); await page.fill('[data-test=nv-titulo]', 'Informes nuevos'); await page.fill('[data-test=nv-texto]', 'Hay informes de la plataforma.')
    await page.click('[data-test=nv-publicar]')
    await page.waitForSelector('[data-novedad=n1]')
    const p = e.cuerpos.find(c => c.accion === 'novedad_publicar')
    assert.equal(p.version, '1.5.0'); assert.equal(p.titulo, 'Informes nuevos')
    await page.click('[data-novedad=n1] button')
    await page.waitForFunction(() => /Retirada/.test(document.querySelector('[data-novedad=n1]')?.textContent ?? ''))
    await browser.close()
  })

  await prueba('plataforma: aviso por plan y estado, con correo pedido pero apagado, y el registro de entrega visible', async () => {
    const { browser, page, e } = await plataforma()
    await page.goto(url('/plataforma/soporte'))
    await page.click('[data-pestana=avisos]')
    await page.waitForSelector('[data-test=pm-avisos-vacio]')
    await page.selectOption('[data-test=av-tipo]', 'mantenimiento')
    await page.fill('[data-test=av-titulo]', 'Parada programada'); await page.fill('[data-test=av-texto]', 'El sábado a las 22:00.')
    await page.click('[data-test=av-dest-filtro]')
    await page.getByLabel('Premium').check()
    await page.getByLabel('Prueba', { exact: true }).check()
    await page.check('[data-test=av-correo]')
    await page.click('[data-test=av-crear]')
    await page.waitForSelector('[data-aviso=a1]')
    const c = e.cuerpos.find(x => x.accion === 'aviso_crear')
    assert.equal(c.tipo, 'mantenimiento'); assert.deepEqual(c.destino, { planes: ['premium'], estados: ['prueba'] }); assert.equal(c.por_correo, true); assert.equal(c.incluir_demo, false)
    const cifras = await page.locator('[data-test=aviso-cifras]').innerText()
    assert.match(cifras, /4 entregados · 1 leídos · 0 descartados/); assert.match(cifras, /no enviado/)
    assert.match(await page.locator('[data-test=pm-soporte-aviso]').innerText(), /4 iglesias/)
    await browser.close()
  })

  await prueba('plataforma: si el soporte no está en la base, se dice «sin conectar» y no se muestran ceros; un error se explica', async () => {
    let r = await plataforma({ resumen: 'falta' })
    await r.page.goto(url('/plataforma/soporte'))
    await r.page.waitForSelector('[data-test=sin-conectar]')
    assert.equal(await r.page.locator('[data-test=pm-soporte-cifras]').count(), 0)
    assert.equal(await r.page.locator('[data-test=sin-conectar]').count(), 2)
    await r.browser.close()
    r = await plataforma({ resumen: 'error' })
    await r.page.goto(url('/plataforma/soporte'))
    await r.page.waitForSelector('[data-test=pm-soporte-error]')
    assert.equal(await r.page.locator('[data-test=pm-soporte-cifras]').count(), 0)
    await r.browser.close()
  })
} finally { parar() }
if (fallos) { console.error(`\n${fallos} prueba(s) con fallos`); process.exit(1) }
console.log('\nSoporte UI: todo correcto')
