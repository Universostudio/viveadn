// Prueba del panel de inicio honesto: tarjetas por rol con los permisos reales, y datos que no cargaron. Uso: npm run test:panel-inicio
import assert from 'node:assert/strict'
import { tarjetasDeInicio, medida, textoMedida, hayMas } from '../src/lib/panelInicio.ts'

const con = (...permisos: string[]) => (...c: string[]) => c.some(x => permisos.includes(x))

// Sin permisos no hay tarjetas
assert.deepEqual(tarjetasDeInicio(con()), { personas: null, casas: null, seguimiento: null, nuevaPersona: false })
// Un rol amplio cuenta todo
assert.deepEqual(tarjetasDeInicio(con('miembros.ver', 'casas.ver', 'consolidacion.ver', 'miembros.crear')), { personas: 'todo', casas: 'todo', seguimiento: 'todo', nuevaPersona: true })
// Si tiene el permiso amplio y el acotado, manda el amplio
assert.equal(tarjetasDeInicio(con('miembros.ver', 'miembros.ver_zona')).personas, 'todo')
// Líder de casa: lo suyo, no el total de la iglesia
assert.deepEqual(tarjetasDeInicio(con('casas.ver_propia', 'miembros.ver_asignados', 'consolidacion.ver_casa')), { personas: 'acotado', casas: 'acotado', seguimiento: 'acotado', nuevaPersona: false })
// Líder de zona
assert.deepEqual(tarjetasDeInicio(con('casas.ver_zona', 'miembros.ver_zona', 'consolidacion.ver_zona')), { personas: 'acotado', casas: 'acotado', seguimiento: 'acotado', nuevaPersona: false })
// Consolidador: solo su seguimiento y sus asignados
assert.deepEqual(tarjetasDeInicio(con('miembros.ver_asignados', 'consolidacion.ver_asignados')), { personas: 'acotado', casas: null, seguimiento: 'acotado', nuevaPersona: false })
// Colaborador: lo que registra
assert.deepEqual(tarjetasDeInicio(con('miembros.ver_propios', 'consolidacion.ver_propios', 'casas.ver')), { personas: 'acotado', casas: 'todo', seguimiento: 'acotado', nuevaPersona: false })
// Miembro: nada de estadísticas
assert.deepEqual(tarjetasDeInicio(con('eventos.ver')), { personas: null, casas: null, seguimiento: null, nuevaPersona: false })

// Medidas: un error no se muestra como 0
assert.deepEqual(medida({ count: 12, error: null }), { valor: 12, fallo: false })
assert.deepEqual(medida({ count: 0, error: null }), { valor: 0, fallo: false }, 'cero de verdad es cero')
assert.deepEqual(medida({ count: null, error: null }), { valor: null, fallo: true }, 'sin recuento no hay dato')
assert.deepEqual(medida({ count: 5, error: { message: 'x' } }), { valor: null, fallo: true }, 'con error no se fía del recuento')
assert.deepEqual(medida(undefined), { valor: null, fallo: true })
assert.deepEqual(medida(null), { valor: null, fallo: true })
assert.equal(textoMedida({ valor: 0, fallo: false }), '0')
assert.equal(textoMedida({ valor: 7, fallo: false }), '7')
assert.equal(textoMedida({ valor: null, fallo: true }), '—')

// «Mostrando N de M»
assert.equal(hayMas(5, 12), true)
assert.equal(hayMas(5, 5), false)
assert.equal(hayMas(3, 3), false)
assert.equal(hayMas(5, null), false, 'sin total no se afirma que haya más')
console.log('Panel de inicio: todo correcto')
