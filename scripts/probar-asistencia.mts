// Prueba de la lista de asistencia de una casa: qué se inserta, qué se actualiza y qué no se toca. Sin red ni navegador.
// Uso: npm run test:asistencia
import assert from 'node:assert/strict'
import { hoyLocal, planDeAsistencia, resumenPorFecha } from '../src/lib/asistencia.ts'

const casa = 'c1', fecha = '2026-11-15'
// Primera lista del día: todo se inserta, presentes y ausentes
let p = planDeAsistencia(casa, fecha, ['a', 'b', 'c'], [], new Set(['a', 'c']))
assert.deepEqual(p.insertar.map(x => [x.miembro_id, x.presente]), [['a', true], ['b', false], ['c', true]])
assert.ok(p.insertar.every(x => x.casa_oracion_id === casa && x.fecha === fecha))
assert.deepEqual(p.actualizar, [])
// Guardar otra vez lo mismo no duplica ni cambia nada
p = planDeAsistencia(casa, fecha, ['a', 'b', 'c'], [{ id: '1', miembro_id: 'a', presente: true }, { id: '2', miembro_id: 'b', presente: false }, { id: '3', miembro_id: 'c', presente: true }], new Set(['a', 'c']))
assert.deepEqual(p, { insertar: [], actualizar: [] }, 'repetir la lista no duplica filas')
// Corregir: b llegó tarde, c se fue
p = planDeAsistencia(casa, fecha, ['a', 'b', 'c'], [{ id: '1', miembro_id: 'a', presente: true }, { id: '2', miembro_id: 'b', presente: false }, { id: '3', miembro_id: 'c', presente: true }], new Set(['a', 'b']))
assert.deepEqual(p, { insertar: [], actualizar: [{ id: '2', presente: true }, { id: '3', presente: false }] })
// Alguien nuevo en la casa se inserta; una fila de alguien que ya no está en la casa no se toca
p = planDeAsistencia(casa, fecha, ['a', 'd'], [{ id: '1', miembro_id: 'a', presente: true }, { id: '9', miembro_id: 'zz', presente: true }], new Set(['a', 'd']))
assert.deepEqual(p.insertar.map(x => x.miembro_id), ['d']); assert.deepEqual(p.actualizar, [])
// presente nulo cuenta como ausente
assert.deepEqual(planDeAsistencia(casa, fecha, ['a'], [{ id: '1', miembro_id: 'a', presente: null }], new Set()).actualizar, [], 'nulo y ausente son lo mismo')
assert.deepEqual(planDeAsistencia(casa, fecha, [], [], new Set(['a'])), { insertar: [], actualizar: [] }, 'una casa sin gente no genera nada')

// Fecha local
assert.equal(hoyLocal(new Date(2026, 10, 15, 23, 30)), '2026-11-15', 'a las 23:30 locales sigue siendo el mismo día')
assert.equal(hoyLocal(new Date(2026, 10, 16, 0, 10)), '2026-11-16')
// Resumen
assert.deepEqual(resumenPorFecha([{ fecha: '2026-11-08', presente: true }, { fecha: '2026-11-15', presente: true }, { fecha: '2026-11-15', presente: false }, { fecha: '2026-11-15', presente: null }]),
  [{ fecha: '2026-11-15', presentes: 1, total: 3 }, { fecha: '2026-11-08', presentes: 1, total: 1 }], 'más reciente primero')

console.log('Asistencia: todo correcto')
