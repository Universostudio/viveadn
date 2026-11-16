// Prueba de la validación y la forma de las respuestas del soporte en la función de borde. Uso: npm run test:soporte-funcion
import assert from 'node:assert/strict'
import { correoDeAviso, esUuid, estadisticasDeAvisos, listaDeTickets, resumenDeSoporte, ticketAbierto, validarAviso, validarNovedad, validarRespuesta } from '../supabase/functions/plataforma/soporte.ts'
import { clavesPersonales, salidaSegura } from '../supabase/functions/plataforma/panel.ts'

const ID = '11111111-1111-4111-8111-111111111111'
const AHORA = Date.UTC(2026, 10, 16, 12)

// Respuesta
assert.deepEqual(validarRespuesta({ id: ID, texto: '  Hola  ' }), { ok: true, id: ID, texto: 'Hola' })
for (const mal of [{}, { id: 'x', texto: 'a' }, { id: ID, texto: '   ' }, { id: ID }]) assert.equal(validarRespuesta(mal as any).ok, false, JSON.stringify(mal))
assert.equal((validarRespuesta({ id: ID, texto: 'a'.repeat(5000) }) as any).texto.length, 4000, 'se corta a 4000')
assert.ok(esUuid(ID) && !esUuid('nada') && !esUuid(5))

// Novedad
assert.deepEqual(validarNovedad({ version: ' 1.2.0 ', titulo: 'Más rápido', texto: 'Texto' }), { ok: true, version: '1.2.0', titulo: 'Más rápido', texto: 'Texto' })
for (const mal of [{ titulo: 'Titulo', texto: 't' }, { version: '1', titulo: 'ab', texto: 't' }, { version: '1', titulo: 'Titulo', texto: ' ' }]) assert.equal(validarNovedad(mal).ok, false)

// Aviso: destino
const base = { tipo: 'alerta', titulo: 'Mantenimiento', texto: 'Esta noche' }
const av = (o: object) => validarAviso({ ...base, ...o }, AHORA)
assert.deepEqual((av({ destino: { todas: true } }) as any).aviso.destino, { todas: true })
assert.deepEqual((av({ destino: { planes: ['premium', 'premium', 'semilla'] } }) as any).aviso.destino, { planes: ['premium', 'semilla'] }, 'sin repetidos')
assert.deepEqual((av({ destino: { estados: ['activa'], planes: ['basico'] } }) as any).aviso.destino, { estados: ['activa'], planes: ['basico'] }, 'planes y estados juntos')
for (const destino of [undefined, {}, { planes: [] }, { planes: ['Premium!'] }, { planes: 'premium' }, { estados: ['inventado'] }, { estados: [] }, { todas: false }]) assert.equal(av({ destino }).ok, false, JSON.stringify(destino))
// Aviso: resto de campos
assert.equal(validarAviso({ ...base, tipo: 'publicidad', destino: { todas: true } }, AHORA).ok, false)
assert.equal(av({ titulo: 'ab', destino: { todas: true } }).ok, false); assert.equal(av({ texto: ' ', destino: { todas: true } }).ok, false)
assert.equal((av({ destino: { todas: true } }) as any).aviso.incluir_demo, false, 'las demostraciones no entran si no se pide')
assert.equal((av({ destino: { todas: true }, incluir_demo: true }) as any).aviso.incluir_demo, true)
assert.equal((av({ destino: { todas: true }, incluir_demo: 'si' }) as any).aviso.incluir_demo, false, 'solo un verdadero de verdad')
assert.equal((av({ destino: { todas: true }, hasta: new Date(AHORA + 86400000).toISOString() }) as any).aviso.hasta, new Date(AHORA + 86400000).toISOString())
assert.equal(av({ destino: { todas: true }, hasta: new Date(AHORA - 1000).toISOString() }).ok, false, 'una fecha de fin pasada se rechaza')
assert.equal(av({ destino: { todas: true }, hasta: 'ayer' }).ok, false)

// El correo masivo no se envía: solo se anota
assert.equal(correoDeAviso(false, true), 'no_pedido'); assert.equal(correoDeAviso(false, false), 'no_pedido')
assert.equal(correoDeAviso(true, false), 'apagado', 'con el interruptor apagado se anota «apagado»')
assert.equal(correoDeAviso(true, true), 'sin_envio', 'encendido no hay quien envíe: no queda «pendiente», se rechaza')

// Lista de tickets: sin texto y sin datos personales
const filas = [
  { id: ID, iglesia_id: 'i1', asunto: 'No guarda', prioridad: 'alta', estado: 'abierto', created_at: '2026-11-10T10:00:00Z', updated_at: '2026-11-11T10:00:00Z', cerrado_en: null, iglesias: { nombre: 'Casa' }, mensajes: [{ count: 3 }], texto: 'NO DEBE SALIR' },
  { id: 'b', iglesia_id: 'i2', asunto: 'Otro', prioridad: 'baja', estado: 'cerrado', created_at: '2026-11-09T10:00:00Z', updated_at: '2026-11-09T10:00:00Z', cerrado_en: '2026-11-09T12:00:00Z', iglesias: [{ nombre: 'Sur' }], mensajes: null },
]
const lista = listaDeTickets(filas as any)
assert.deepEqual(lista.map(t => [t.iglesia, t.mensajes, t.estado]), [['Casa', 3, 'abierto'], ['Sur', 0, 'cerrado']])
assert.ok(!JSON.stringify(lista).includes('NO DEBE SALIR'), 'la lista no lleva el texto')
assert.deepEqual(listaDeTickets(null), [])
const abierto = ticketAbierto(filas[0] as any, [{ id: '2', autor_tipo: 'plataforma', texto: 'Respuesta', created_at: 'b' }, { id: 1, autor_tipo: 'iglesia', texto: 'Pregunta', created_at: 'a' }])
assert.deepEqual(abierto.conversacion.map(m => [m.id, m.de]), [[2, 'plataforma'], [1, 'iglesia']])
assert.deepEqual(clavesPersonales(lista), [], 'la lista pasa la barrera de privacidad del panel')
assert.doesNotThrow(() => salidaSegura({ ok: true, tickets: lista }))

// Resumen
const r = resumenDeSoporte(
  [{ estado: 'abierto', prioridad: 'urgente' }, { estado: 'abierto', prioridad: 'baja' }, { estado: 'respondido', prioridad: 'urgente' }, { estado: 'cerrado', prioridad: 'urgente' }],
  [{ version: '1.2', publicada_en: 'x' }, { version: '1.1', publicada_en: 'y' }], [{ id: 'a' }],
  [{ aviso_id: 'a', leido_en: 'z', descartado_en: null }, { aviso_id: 'a', leido_en: 'z', descartado_en: 'z' }, { aviso_id: 'a', leido_en: null, descartado_en: null }])
assert.deepEqual(r.tickets, { abiertos: 2, respondidos: 1, cerrados: 1, urgentes: 2 }, 'los urgentes sin cerrar: el abierto y el respondido, no el cerrado')
assert.deepEqual(r.novedades, { total: 2, ultima: { version: '1.2', publicada_en: 'x' } })
assert.deepEqual(r.avisos, { vigentes: 1, entregas: 3, leidos: 2, descartados: 1 })
assert.deepEqual(resumenDeSoporte(null, null, null, null), { tickets: { abiertos: 0, respondidos: 0, cerrados: 0, urgentes: 0 }, novedades: { total: 0, ultima: null }, avisos: { vigentes: 0, entregas: 0, leidos: 0, descartados: 0 } }, 'sin datos: ceros honestos')
assert.deepEqual(estadisticasDeAvisos([{ aviso_id: 'a', leido_en: 'z', descartado_en: null }, { aviso_id: 'b', leido_en: null, descartado_en: null }, { aviso_id: 'a', leido_en: null, descartado_en: 'z' }]),
  { a: { entregas: 2, leidos: 1, descartados: 1 }, b: { entregas: 1, leidos: 0, descartados: 0 } })
console.log('Soporte (función): todo correcto')

// M3: abrir un ticket audita ANTES de leer los mensajes y, si la auditoría falla, el texto no sale
import { readFileSync } from 'node:fs'
const fuente = readFileSync(new URL('../supabase/functions/plataforma/index.ts', import.meta.url), 'utf8')
const abrir = fuente.slice(fuente.indexOf("case 'ticket_abrir'"), fuente.indexOf("case 'ticket_responder'"))
assert.ok(abrir.indexOf("auditar('ticket_abrir'") > -1 && abrir.indexOf("auditar('ticket_abrir'") < abrir.indexOf('adn_ticket_mensajes'), 'ticket_abrir audita antes de leer los mensajes')
assert.match(abrir, /if \(!auditado\) return json\(\{ error: [^}]*\}, 503\)/, 'si la auditoría falla, ticket_abrir responde 503 sin texto')
console.log('Soporte (función): lectura de tickets audita antes y falla si no pudo auditar')

// M4: el resumen de soporte respeta «Incluir demostraciones»
import { sinDemos } from '../supabase/functions/plataforma/soporte.ts'
{
  const demo = new Set(['D'])
  const filas = [{ iglesia_id: 'A', n: 1 }, { iglesia_id: 'D', n: 2 }, { iglesia_id: null, n: 3 }]
  assert.deepEqual(sinDemos(filas, demo, false)!.map(f => f.n), [1, 3], 'apagado: las filas de demostración no cuentan')
  assert.deepEqual(sinDemos(filas, demo, true)!.map(f => f.n), [1, 2, 3], 'encendido: cuentan todas')
  assert.equal(sinDemos(null, demo, false), null)
  assert.match(fuente.slice(fuente.indexOf("case 'soporte_resumen'"), fuente.indexOf("case 'ticket_listar'")), /body\.incluir_demo !== false/)
  console.log('Soporte (función): el resumen usa el mismo interruptor de demostraciones')
}

// M6: agregados de SQL con la misma forma que los cálculos de antes
import { leerTodo } from '../supabase/functions/plataforma/paginar.ts'
import { estadisticasDeAgregado, resumenDeAgregado } from '../supabase/functions/plataforma/soporte.ts'
{
  const tickets = [{ estado: 'abierto', prioridad: 'urgente' }, { estado: 'abierto', prioridad: 'normal' }, { estado: 'respondido', prioridad: 'urgente' }, { estado: 'cerrado', prioridad: 'urgente' }]
  const nov = [{ version: '1.3', publicada_en: '2026-11-10T00:00:00Z' }, { version: '1.2', publicada_en: '2026-11-01T00:00:00Z' }]
  const entregas = [{ aviso_id: 'a', leido_en: 'x', descartado_en: null }, { aviso_id: 'a', leido_en: null, descartado_en: 'y' }]
  const viejo = resumenDeSoporte(tickets, nov, [{ id: 'a' }], entregas)
  const nuevo = resumenDeAgregado({ tickets_abiertos: '2', tickets_respondidos: 1, tickets_cerrados: 1, tickets_urgentes: 2, avisos_vigentes: 1, entregas: 2, leidos: 1, descartados: 1, novedades_total: 2, ultima_version: '1.3', ultima_publicada: '2026-11-10T00:00:00Z' })
  assert.deepEqual(nuevo, viejo, 'el agregado de SQL da la misma respuesta que contar las filas')
  assert.deepEqual(resumenDeAgregado(null), { tickets: { abiertos: 0, respondidos: 0, cerrados: 0, urgentes: 0 }, novedades: { total: 0, ultima: null }, avisos: { vigentes: 0, entregas: 0, leidos: 0, descartados: 0 } }, 'sin fila: ceros honestos')
  assert.deepEqual(estadisticasDeAgregado([{ aviso_id: 'a', entregas: '2', leidos: 1, descartados: '1' }]), estadisticasDeAvisos(entregas))

  // Lectura por páginas: el servicio devuelve como mucho 3 filas por respuesta, y aun así llegan las 10; una lista cortada nunca se entrega como completa
  const todas = Array.from({ length: 10 }, (_, i) => ({ i }))
  const servicio = (maximo: number) => async (d: number, h: number) => ({ data: todas.slice(d, Math.min(h + 1, d + maximo)), error: null })
  for (const maximo of [1, 3, 7, 1000]) assert.equal((await leerTodo(servicio(maximo), 5)).data.length, 10, `con un límite de ${maximo} filas por respuesta se leen las 10`)
  assert.equal((await leerTodo(async () => ({ data: null, error: { message: 'x' } }))).error?.message, 'x', 'el error se propaga')
  assert.equal((await leerTodo(servicio(1000), 5, 4)).error?.message, 'demasiadas filas', 'por encima del tope falla en vez de devolver una lista cortada')
  console.log('Soporte (función): agregados de SQL y lectura por páginas')
}
