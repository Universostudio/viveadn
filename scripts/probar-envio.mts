// Pruebas del envío de avisos por correo y sus topes. Uso: npm run test:envio
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
const { enviarAviso, leerConfig, avisoBaja, avisoPurga, TOPE_GLOBAL_GRATUITO, TOPE_GLOBAL_PAGO, TOPES } = await import('../supabase/functions/datos-iglesia/envio.ts')
type Aviso = Parameters<typeof enviarAviso>[0]
type Deps = Parameters<typeof enviarAviso>[1]

assert.equal(readFileSync('supabase/functions/datos-iglesia/envio.ts', 'utf8'), readFileSync('supabase/functions/plataforma/envio.ts', 'utf8'), 'el módulo es idéntico en las dos funciones')

// Configuración: apagado por defecto y topes que solo se pueden bajar
const env = (o: Record<string, string>) => (k: string) => o[k]
assert.equal(leerConfig(env({})).activo, false, 'apagado por defecto')
for (const v of ['true', '1', 'yes', 'on', '', 'no', 'sí']) assert.equal(leerConfig(env({ ADN_ENVIO_ACTIVO: v })).activo, false, `«${v}» no lo enciende`)
assert.equal(leerConfig(env({ ADN_ENVIO_ACTIVO: ' SI ' })).activo, true, 'solo «si» lo enciende')
assert.equal(leerConfig(env({})).topeGlobal, TOPE_GLOBAL_GRATUITO, 'sin plan, el tope del gratuito')
assert.equal(TOPE_GLOBAL_GRATUITO < 50, true, 'el tope gratuito queda por debajo de los 50 diarios del proveedor')
assert.equal(leerConfig(env({ ADN_ENVIO_PLAN: 'pago' })).topeGlobal, TOPE_GLOBAL_PAGO, 'plan de pago: 5000')
assert.equal(leerConfig(env({ ADN_ENVIO_PLAN: 'otra cosa' })).plan, 'gratuito', 'un plan desconocido es el gratuito')
assert.equal(leerConfig(env({ ADN_ENVIO_TOPE_GLOBAL: '10' })).topeGlobal, 10, 'la variable puede bajar el tope')
assert.equal(leerConfig(env({ ADN_ENVIO_TOPE_GLOBAL: '1000' })).topeGlobal, TOPE_GLOBAL_GRATUITO, 'pero no subirlo sobre el máximo del plan gratuito')
assert.equal(leerConfig(env({ ADN_ENVIO_PLAN: 'pago', ADN_ENVIO_TOPE_GLOBAL: '99999' })).topeGlobal, TOPE_GLOBAL_PAGO, 'ni sobre el del plan de pago')
for (const v of ['-3', 'x', '2.5', ' ']) assert.equal(leerConfig(env({ ADN_ENVIO_TOPE_GLOBAL: v })).topeGlobal, TOPE_GLOBAL_GRATUITO, `valor no válido «${v}»`)
assert.equal(leerConfig(env({ ADN_ENVIO_TOPE_GLOBAL: '0' })).topeGlobal, 0, 'un 0 apaga el envío')
assert.deepEqual(TOPES, { purgaDia: 1, bajaIglesia: 2, confirmacionIglesia: 200, confirmacionPlataforma: 2000 }, 'topes aprobados por Gerencia')

// Pila de pruebas: contador en memoria con la misma lógica que la base y un proveedor simulado
function montar(opciones: { activo?: boolean; clave?: string | null; proveedor?: 'ok' | 'cae' | '500'; reservaFalla?: boolean; liberaFalla?: boolean; plan?: 'gratuito' | 'pago' } = {}) {
  const { activo = true, clave = 'bk_eu1_secreto', proveedor = 'ok', reservaFalla = false, liberaFalla = false, plan = 'gratuito' } = opciones
  const cuenta = new Map<string, number>()
  const llamadas = { reservar: [] as unknown[][], liberar: 0, fetch: [] as { url: string; init: any }[] }
  const deps: Deps = {
    config: { activo, plan, claveBird: clave, soporte: 'soporte@viveadn.com', topeGlobal: plan === 'pago' ? TOPE_GLOBAL_PAGO : TOPE_GLOBAL_GRATUITO },
    reservar: async (tipo, iglesia, tI, tT, tG) => {
      llamadas.reservar.push([tipo, iglesia, tI, tT, tG])
      if (reservaFalla) throw new Error('base caída')
      const suma = (f: (k: string) => boolean) => [...cuenta].filter(([k]) => f(k)).reduce((a, [, n]) => a + n, 0)
      if (suma(() => true) >= tG) return 'tope_global'
      if (tT !== null && suma(k => k.startsWith(tipo + '|')) >= tT) return 'tope_tipo'
      const k = `${tipo}|${iglesia}`
      if (tI !== null && iglesia !== null && (cuenta.get(k) ?? 0) >= tI) return 'tope_iglesia'
      cuenta.set(k, (cuenta.get(k) ?? 0) + 1)
      return 'ok'
    },
    liberar: async (tipo, iglesia) => { llamadas.liberar++; if (liberaFalla) throw new Error('no se pudo'); const k = `${tipo}|${iglesia}`; cuenta.set(k, Math.max((cuenta.get(k) ?? 1) - 1, 0)) },
    fetchFn: (async (url: string, init: any) => {
      llamadas.fetch.push({ url, init })
      if (proveedor === 'cae') throw new Error('red caída')
      return { ok: proveedor === 'ok', status: proveedor === '500' ? 500 : 200 }
    }) as unknown as typeof fetch,
  }
  return { deps, llamadas, cuenta }
}
const aviso = (o: Partial<Aviso> = {}): Aviso => ({ tipo: 'baja', iglesia: 'i1', destino: 'propietario@iglesia.test', destinoRegistrado: true, asunto: 'a', texto: 't', html: '<p>t</p>', idempotencia: 'baja/i1/pedida/x', ...o })

// Apagado: ni cuenta ni proveedor
{ const m = montar({ activo: false }); assert.deepEqual(await enviarAviso(aviso(), m.deps), { estado: 'apagado' }); assert.equal(m.llamadas.reservar.length + m.llamadas.fetch.length, 0, 'apagado no toca nada') }
// Dirección no registrada o mal formada: no se envía ni se reserva
for (const destino of ['', 'sin-arroba', 'a@b', 'a b@c.test', 'a@c.test, b@c.test', 'a@c.test;b@c.test', '<a@c.test>', 'a@c.test\nBcc: x@y.test', 'x'.repeat(250) + '@c.test']) {
  const m = montar(); assert.deepEqual(await enviarAviso(aviso({ destino }), m.deps), { estado: 'destino_no_valido' }, `destino «${destino.slice(0, 20)}»`)
  assert.equal(m.llamadas.reservar.length + m.llamadas.fetch.length, 0)
}
{ const m = montar(); assert.deepEqual(await enviarAviso(aviso({ destinoRegistrado: false }), m.deps), { estado: 'destino_no_valido' }, 'una dirección no registrada nunca recibe correo'); assert.equal(m.llamadas.fetch.length, 0) }
// Sin clave
{ const m = montar({ clave: null }); assert.deepEqual(await enviarAviso(aviso(), m.deps), { estado: 'sin_clave' }); assert.equal(m.llamadas.fetch.length, 0) }
// Envío correcto: un solo destinatario, transaccional, sin seguimiento y con clave de idempotencia
{
  const m = montar(); assert.deepEqual(await enviarAviso(aviso(), m.deps), { estado: 'enviado' })
  assert.equal(m.llamadas.fetch.length, 1)
  assert.equal(m.llamadas.fetch[0].url, 'https://eu1.platform.bird.com/v1/email/messages', 'región tomada de la clave')
  const cuerpo = JSON.parse(m.llamadas.fetch[0].init.body)
  assert.deepEqual(cuerpo.to, [{ email: 'propietario@iglesia.test' }], 'un solo destinatario')
  assert.equal(cuerpo.category, 'transactional'); assert.equal(cuerpo.track_clicks, false); assert.equal(cuerpo.track_opens, false)
  assert.equal(m.llamadas.fetch[0].init.headers['Idempotency-Key'], 'baja/i1/pedida/x')
  assert.equal(montar({ clave: 'bk_us1_x' }).deps.config.claveBird, 'bk_us1_x')
  const us = montar({ clave: 'bk_us1_x' }); await enviarAviso(aviso(), us.deps); assert.match(us.llamadas.fetch[0].url, /^https:\/\/us1\.platform/, 'otra región')
}
// Topes pasados a la base, por tipo
{
  const m = montar(); await enviarAviso(aviso({ tipo: 'purga', iglesia: null }), m.deps); await enviarAviso(aviso({ tipo: 'baja' }), m.deps); await enviarAviso(aviso({ tipo: 'confirmacion' }), m.deps)
  assert.deepEqual(m.llamadas.reservar, [['purga', null, null, 1, 40], ['baja', 'i1', 2, null, 40], ['confirmacion', 'i1', 200, 2000, 40]], 'purga 1 al día; baja 2 por iglesia; confirmación 200 y 2000')
}
// Tope por iglesia: la tercera baja del día no sale
{
  const m = montar(); for (let i = 0; i < 2; i++) assert.equal((await enviarAviso(aviso(), m.deps)).estado, 'enviado')
  assert.deepEqual(await enviarAviso(aviso(), m.deps), { estado: 'tope', cual: 'tope_iglesia' }); assert.equal(m.llamadas.fetch.length, 2, 'con el tope alcanzado no se llama al proveedor')
  assert.equal((await enviarAviso(aviso({ iglesia: 'i2' }), m.deps)).estado, 'enviado', 'otra iglesia sí')
}
// Tope de la purga: una alerta al día
{ const m = montar(); const p = aviso({ tipo: 'purga', iglesia: null }); assert.equal((await enviarAviso(p, m.deps)).estado, 'enviado'); assert.deepEqual(await enviarAviso(p, m.deps), { estado: 'tope', cual: 'tope_tipo' }) }
// Tope global del plan gratuito: 40 envíos y el 41 falla limpio, de cualquier tipo
{
  const m = montar(); let enviados = 0
  for (let i = 0; i < 60; i++) { const r = await enviarAviso(aviso({ iglesia: `i${i}` }), m.deps); if (r.estado === 'enviado') enviados++ }
  assert.equal(enviados, 40, 'el gratuito se queda en 40 al día'); assert.equal(m.llamadas.fetch.length, 40, 'y no se llama al proveedor más veces')
  assert.deepEqual(await enviarAviso(aviso({ tipo: 'purga', iglesia: null }), m.deps), { estado: 'tope', cual: 'tope_global' }, 'ni la alerta de purga pasa del global')
}
// Proveedor caído: no lanza, devuelve el cupo y no rompe nada
for (const proveedor of ['cae', '500'] as const) {
  const m = montar({ proveedor }); const r = await enviarAviso(aviso(), m.deps)
  assert.deepEqual(r, { estado: 'fallo' }, `proveedor ${proveedor}`); assert.equal(m.llamadas.liberar, 1, 'devuelve el cupo'); assert.equal(m.cuenta.get('baja|i1'), 0)
}
{ const m = montar({ proveedor: 'cae', liberaFalla: true }); assert.deepEqual(await enviarAviso(aviso(), m.deps), { estado: 'fallo' }, 'ni siquiera un fallo al devolver el cupo lanza') }
// Sin contador no se envía (falla cerrado)
{ const m = montar({ reservaFalla: true }); assert.deepEqual(await enviarAviso(aviso(), m.deps), { estado: 'fallo' }); assert.equal(m.llamadas.fetch.length, 0, 'si la base no responde, no sale correo') }

// Contenido
for (const idioma of ['es', 'en', 'fr', 'pt-BR', 'xx']) {
  const p = avisoBaja('pedida', { idioma, iglesia: 'Iglesia <b>X</b>', fecha: '11 de diciembre de 2026', soporte: 'soporte@viveadn.com' })
  assert.ok(p.asunto.length > 5 && p.texto.includes('11 de diciembre de 2026') && p.texto.includes('soporte@viveadn.com'), `texto de baja ${idioma}`)
  assert.ok(!p.html.includes('<b>X</b>') && p.html.includes('&lt;b&gt;X&lt;/b&gt;'), 'el nombre de la iglesia se escapa en el HTML')
  assert.ok(!/https?:\/\//.test(p.texto), 'el aviso no lleva enlaces ni secretos')
  assert.ok(avisoBaja('cancelada', { idioma, iglesia: 'X', soporte: 's@v.test' }).texto.length > 20)
}
assert.notEqual(avisoBaja('pedida', { idioma: 'en', iglesia: 'X', fecha: 'F', soporte: 's' }).asunto, avisoBaja('pedida', { idioma: 'es', iglesia: 'X', fecha: 'F', soporte: 's' }).asunto, 'cada idioma tiene su texto')
assert.equal(avisoBaja('pedida', { idioma: 'xx', iglesia: 'X', fecha: 'F', soporte: 's' }).asunto, avisoBaja('pedida', { idioma: 'es', iglesia: 'X', fecha: 'F', soporte: 's' }).asunto, 'un idioma desconocido usa el español')
const pu = avisoPurga({ vencidas: 3, horas_mas_atrasada: 72, en_borrado: 5 })
assert.match(pu.texto, /3 iglesia\(s\).*72 horas/s); assert.ok(!/@|http/.test(pu.texto), 'la alerta de purga solo lleva cifras')
console.log('Envío: todas las pruebas pasan')
