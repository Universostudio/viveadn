// Prueba de las reglas del soporte en la aplicación de la iglesia. Uso: npm run test:soporte
import assert from 'node:assert/strict'
import { avisosVisibles, errorDeSoporte, validarMensaje, validarTicket, MAX_ASUNTO, MAX_TEXTO } from '../src/lib/soporte.ts'

assert.deepEqual(validarTicket({ asunto: 'No guarda', prioridad: 'alta', texto: 'Sale un error' }), {})
assert.equal(validarTicket({ asunto: 'ab', prioridad: 'alta', texto: 'x' }).asunto, 'soporte.errores.asuntoCorto')
assert.equal(validarTicket({ asunto: '   ab   ', prioridad: 'alta', texto: 'x' }).asunto, 'soporte.errores.asuntoCorto', 'los espacios no cuentan')
assert.equal(validarTicket({ asunto: 'a'.repeat(MAX_ASUNTO + 1), prioridad: 'alta', texto: 'x' }).asunto, 'soporte.errores.asuntoLargo')
assert.equal(validarTicket({ asunto: 'a'.repeat(MAX_ASUNTO), prioridad: 'alta', texto: 'x' }).asunto, undefined)
assert.equal(validarTicket({ asunto: 'Asunto', prioridad: 'urgentisima', texto: 'x' }).prioridad, 'soporte.errores.prioridad')
for (const p of ['baja', 'normal', 'alta', 'urgente']) assert.equal(validarTicket({ asunto: 'Asunto', prioridad: p, texto: 'x' }).prioridad, undefined, p)
assert.equal(validarTicket({ asunto: 'Asunto', prioridad: 'baja', texto: '  ' }).texto, 'soporte.errores.textoVacio')
assert.equal(validarTicket({ asunto: 'Asunto', prioridad: 'baja', texto: 'x'.repeat(MAX_TEXTO + 1) }).texto, 'soporte.errores.textoLargo')
assert.deepEqual(Object.keys(validarTicket({ asunto: '', prioridad: '', texto: '' })).sort(), ['asunto', 'prioridad', 'texto'])
assert.equal(validarMensaje('Hola'), null); assert.equal(validarMensaje('  '), 'soporte.errores.textoVacio'); assert.equal(validarMensaje('x'.repeat(MAX_TEXTO + 1)), 'soporte.errores.textoLargo')

assert.equal(errorDeSoporte({ message: 'ADN_DEMASIADOS_TICKETS' }), 'soporte.errores.demasiados')
assert.equal(errorDeSoporte({ message: 'ADN_TICKET_CERRADO' }), 'soporte.errores.cerrado')
assert.equal(errorDeSoporte({ message: 'ADN_TICKET_LLENO' }), 'soporte.errores.lleno')
assert.equal(errorDeSoporte({ code: '42501', message: 'new row violates row-level security policy' }), 'soporte.errores.permiso')
assert.equal(errorDeSoporte({ message: 'raro' }), 'soporte.errores.generico'); assert.equal(errorDeSoporte(null), 'soporte.errores.generico')

// Avisos: descartados y caducados (aviso null) fuera; las alertas primero; embebido como objeto o como lista
const f = (id: string, tipo: string, extra: object = {}) => ({ aviso_id: id, leido_en: null, descartado_en: null, aviso: { id, tipo, titulo: 'T' + id, texto: 'x' }, ...extra })
const v = avisosVisibles([f('1', 'actualizacion'), f('2', 'alerta'), f('3', 'mantenimiento'), f('4', 'alerta', { descartado_en: 'x' }), f('5', 'alerta', { aviso: null }), f('6', 'alerta', { aviso: [{ id: '6', tipo: 'alerta', titulo: 'T6', texto: 'x' }], leido_en: 'y' })])
assert.deepEqual(v.map(a => a.id), ['2', '6', '3', '1'], 'alertas, mantenimiento, actualización; sin el descartado ni el caducado')
assert.equal(v.find(a => a.id === '6')!.leido, true); assert.equal(v.find(a => a.id === '2')!.leido, false)
assert.deepEqual(avisosVisibles(null), [])
console.log('Soporte (iglesia): todo correcto')
