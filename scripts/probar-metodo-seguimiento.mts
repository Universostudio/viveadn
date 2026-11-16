// Prueba de las reglas del método de seguimiento propio (las mismas que la base de datos). Uso: npm run test:metodo-seguimiento
import assert from 'node:assert/strict'
import { validarMetodo, esValido, borradorDe, valoresDe, hayCambios, cambiaElPlazo, restaurarDesde, copiaDe, claveNueva, ordenarMetodos, errorDeBase, tramos, PLANTILLA_OP72_ID, PLANTILLA_SIMPLE_ID, MAX_NOMBRE, type MetodoFila, type BorradorMetodo } from '../src/lib/metodoSeguimiento.ts'

const op72: MetodoFila = { id: PLANTILLA_OP72_ID, iglesia_id: null, clave: 'op72', nombre: 'OP72', plantilla_origen: null, pasos: 3, plazo_horas: 72, umbral_amarillo_horas: 24, umbral_naranja_horas: 48, primer_contacto_horas: 24, archivado_en: null }
const simple: MetodoFila = { ...op72, id: PLANTILLA_SIMPLE_ID, clave: 'simple', nombre: 'Seguimiento simple', pasos: 1, plazo_horas: 168, umbral_amarillo_horas: 72, umbral_naranja_horas: 120, primer_contacto_horas: 72 }
const propio: MetodoFila = { ...op72, id: 'x1', iglesia_id: 'ig', clave: 'propio_ab12cd', nombre: 'Mi método', plantilla_origen: PLANTILLA_OP72_ID, pasos: 2, plazo_horas: 96, umbral_amarillo_horas: 30, umbral_naranja_horas: 60, primer_contacto_horas: 12 }
const bueno: BorradorMetodo = borradorDe(propio)

// Un borrador sano pasa, también el de las dos plantillas
assert.deepEqual(validarMetodo(bueno), {})
assert.ok(esValido(borradorDe(op72)) && esValido(borradorDe(simple)))
// Texto de un campo (cadenas) también vale
assert.ok(esValido({ nombre: 'Uno', pasos: '2', plazo_horas: '96', umbral_amarillo_horas: '30', umbral_naranja_horas: '60', primer_contacto_horas: '' }), 'las cadenas de los campos se aceptan y el primer contacto puede ir vacío')

// Cada regla de la base, una a una
const con = (c: Partial<BorradorMetodo>) => validarMetodo({ ...bueno, ...c })
assert.equal(con({ nombre: '   ' }).nombre, 'seguimiento.errores.nombreVacio')
assert.equal(con({ nombre: 'x'.repeat(MAX_NOMBRE + 1) }).nombre, 'seguimiento.errores.nombreLargo')
assert.equal(con({ nombre: 'x'.repeat(MAX_NOMBRE) }).nombre, undefined)
for (const p of [0, 4, '', 'dos', 1.5]) assert.equal(con({ pasos: p }).pasos, 'seguimiento.errores.pasos', `pasos ${p}`)
for (const p of [1, 2, 3]) assert.equal(con({ pasos: p }).pasos, undefined, `pasos ${p}`)
for (const p of [0, 721, '', 'x', 10.5]) assert.equal(con({ plazo_horas: p }).plazo, 'seguimiento.errores.plazo', `plazo ${p}`)
assert.equal(con({ plazo_horas: 720, umbral_naranja_horas: 60 }).plazo, undefined, 'el plazo máximo es 720')
assert.equal(con({ plazo_horas: 1, umbral_amarillo_horas: 1, umbral_naranja_horas: 1 }).naranja, 'seguimiento.errores.naranjaMenor', 'amarillo menor que naranja, siempre estricto')
assert.equal(con({ umbral_amarillo_horas: 0 }).amarillo, 'seguimiento.errores.amarillo')
assert.equal(con({ umbral_amarillo_horas: 60, umbral_naranja_horas: 60 }).naranja, 'seguimiento.errores.naranjaMenor')
assert.equal(con({ umbral_amarillo_horas: 70, umbral_naranja_horas: 60 }).naranja, 'seguimiento.errores.naranjaMenor')
assert.equal(con({ umbral_naranja_horas: 97 }).naranja, 'seguimiento.errores.naranjaMayorPlazo', 'el naranja no pasa del plazo')
assert.equal(con({ umbral_naranja_horas: 96 }).naranja, undefined, 'el naranja puede ser igual al plazo')
assert.equal(con({ primer_contacto_horas: 97 }).primer, 'seguimiento.errores.primerMayorPlazo')
assert.equal(con({ primer_contacto_horas: 96 }).primer, undefined)
assert.equal(con({ primer_contacto_horas: 0 }).primer, 'seguimiento.errores.primer')
assert.equal(con({ primer_contacto_horas: null }).primer, undefined, 'sin objetivo de primer contacto es válido')
// Varios errores a la vez, cada uno en su campo
const varios = validarMetodo({ nombre: '', pasos: 9, plazo_horas: 0, umbral_amarillo_horas: '', umbral_naranja_horas: '', primer_contacto_horas: null })
assert.deepEqual(Object.keys(varios).sort(), ['amarillo', 'naranja', 'nombre', 'pasos', 'plazo'])

// Valores para enviar
assert.deepEqual(valoresDe({ nombre: '  Mío ', pasos: '2', plazo_horas: '96', umbral_amarillo_horas: '30', umbral_naranja_horas: '60', primer_contacto_horas: '12' }),
  { nombre: 'Mío', pasos: 2, plazo_horas: 96, umbral_amarillo_horas: 30, umbral_naranja_horas: 60, primer_contacto_horas: 12 })
assert.equal(valoresDe({ ...bueno, primer_contacto_horas: '' }).primer_contacto_horas, null)

// Cambios y efecto sobre los procesos abiertos
assert.equal(hayCambios(propio, bueno), false)
assert.equal(hayCambios(propio, { ...bueno, nombre: ' Mi método ' }), false, 'los espacios sobrantes no cuentan como cambio')
assert.equal(hayCambios(propio, { ...bueno, nombre: 'Otro' }), true)
assert.equal(cambiaElPlazo(propio, { ...bueno, nombre: 'Otro', pasos: 2 }), false, 'nombre y pasos no mueven plazos')
assert.equal(cambiaElPlazo(propio, { ...bueno, plazo_horas: 80, umbral_naranja_horas: 48 }), true)
assert.equal(cambiaElPlazo(propio, { ...bueno, umbral_amarillo_horas: 20 }), true)
assert.equal(cambiaElPlazo(propio, { ...bueno, primer_contacto_horas: 5 }), false, 'el objetivo de primer contacto no mueve la fecha límite')

// Restaurar: valores de la plantilla, conservando el nombre del método
const cambiado = { ...bueno, nombre: 'Mi método', plazo_horas: 100, umbral_naranja_horas: 50 }
const restaurado = restaurarDesde(op72, cambiado)
assert.equal(restaurado.nombre, 'Mi método')
assert.equal(restaurado.plazo_horas, 72)
assert.deepEqual(tramos(op72), { verde: 24, amarillo: 48, naranja: 72 })

// Copias
const c = copiaDe(op72, ['propio_aaaaaa'], () => 'AB12CD')
assert.equal(c.clave, 'propio_ab12cd')
assert.equal(c.nombre, 'OP72 (copia)')
assert.equal(c.plantilla_origen, PLANTILLA_OP72_ID)
assert.equal(c.plazo_horas, 72)
assert.ok(esValido({ ...c }), 'una copia nace válida')
assert.ok(copiaDe({ ...op72, nombre: 'n'.repeat(80) }, [], () => 'abc').nombre.length <= MAX_NOMBRE, 'el nombre de la copia cabe')
assert.match(claveNueva([]), /^propio_[a-z0-9]{1,12}$/)
let n = 0
assert.equal(claveNueva(['propio_a', 'propio_b'], () => ['a', 'b', 'c'][n++]), 'propio_c', 'salta las claves en uso')
assert.match(claveNueva(['propio_x'], () => 'x'), /^propio_[a-z0-9]+$/, 'si todo choca, igualmente devuelve una clave válida')

// Orden y archivados
const archivado = { ...propio, id: 'x2', nombre: 'Viejo', archivado_en: '2026-11-01' }
const otro = { ...propio, id: 'x3', nombre: 'Álamo' }
assert.deepEqual(ordenarMetodos([otro, archivado, simple, propio, op72]).map(m => m.id), [PLANTILLA_OP72_ID, PLANTILLA_SIMPLE_ID, 'x3', 'x1'], 'plantillas primero, después los propios por nombre y sin archivados')

// Errores de la base
assert.equal(errorDeBase({ message: 'ADN_DEMASIADOS_METODOS' }), 'seguimiento.errores.demasiados')
assert.equal(errorDeBase({ message: 'ADN_METODO_ACTIVO' }), 'seguimiento.errores.activo')
assert.equal(errorDeBase({ message: 'ADN_METODO_ARCHIVADO' }), 'seguimiento.errores.archivado')
assert.equal(errorDeBase({ message: 'ADN_METODO_DE_OTRA_IGLESIA' }), 'seguimiento.errores.ajeno')
assert.equal(errorDeBase({ code: '23505', message: 'duplicate key' }), 'seguimiento.errores.repetido')
assert.equal(errorDeBase({ code: '42501', message: 'new row violates row-level security policy' }), 'seguimiento.errores.permiso')
assert.equal(errorDeBase({ message: 'algo raro' }), 'seguimiento.errores.generico')
assert.equal(errorDeBase(null), 'seguimiento.errores.generico')
console.log('Método de seguimiento: todo correcto')
