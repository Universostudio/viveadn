// Prueba del criterio de «prueba vencida = núcleo en solo lectura» para la interfaz. Uso: npm run test:prueba-vencida
import assert from 'node:assert/strict'
import { esPermisoDeLectura, modulosEnPruebaVencida, pruebaVencida } from '../src/lib/pruebaVencida.ts'

const AHORA = Date.UTC(2026, 10, 16, 12)
assert.equal(pruebaVencida({ etapa: 'prueba', prueba_hasta: '2026-11-16T11:59:59Z', activa: true }, AHORA), true)
assert.equal(pruebaVencida({ etapa: 'prueba', prueba_hasta: '2026-11-16T12:00:00Z', activa: true }, AHORA), true, 'a la hora exacta ya venció (igual que la base: <= now)')
assert.equal(pruebaVencida({ etapa: 'prueba', prueba_hasta: '2026-11-16T12:00:01Z', activa: true }, AHORA), false)
for (const ig of [null, undefined, { etapa: 'activa', prueba_hasta: '2026-01-01T00:00:00Z' }, { etapa: 'receso', prueba_hasta: '2026-01-01T00:00:00Z', activa: false }, { etapa: 'prueba', prueba_hasta: null }])
  assert.equal(pruebaVencida(ig as any, AHORA), false, JSON.stringify(ig))
for (const ok of ['miembros.ver', 'miembros.exportar', 'casas.ver_propia', 'consolidacion.ver_casa', 'miembros.ver_asignados', 'zonas.ver']) assert.equal(esPermisoDeLectura(ok), true, ok)
for (const no of ['miembros.crear', 'miembros.editar', 'miembros.eliminar', 'miembros.importar', 'iglesia.configurar', 'asistencia.registrar_propia', 'formacion.actualizar', 'roles.gestionar', 'consolidacion.registrar_contacto', 'x.verano', 'miembros.ver.x']) assert.equal(esPermisoDeLectura(no), false, no)
const tipos = { miembros: 'nucleo', casas: 'nucleo', reportes: 'incluido', credenciales: 'especial', op72_avanzado: 'complemento' }
assert.deepEqual([...modulosEnPruebaVencida(new Set(['miembros', 'reportes', 'casas', 'credenciales', 'desconocido']), tipos)].sort(), ['casas', 'miembros'])
console.log('Prueba vencida: todo correcto')
