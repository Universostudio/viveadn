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
assert.equal(correoDeAviso(true, true), 'pendiente', 'encendido, queda pendiente: el envío real no está construido')

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
