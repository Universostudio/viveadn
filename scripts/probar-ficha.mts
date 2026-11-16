// Prueba de la edición de la ficha: validación, normalización y cambios mínimos. Uso: npm run test:ficha
import assert from 'node:assert/strict'
import { aFormulario, validarFicha, cambiosDe, type FichaForm, type FichaOpciones } from '../src/lib/ficha.ts'

const NIVELES = ['nuevo', 'en_crecimiento', 'maduro', 'lider', 'multiplicador']
const o: FichaOpciones = { alias: false, niveles: NIVELES, hoy: '2026-11-16' }
const alias: FichaOpciones = { ...o, alias: true }
const fila = { nombre: 'Ana', apellido: 'Uno', email: 'ana@x.test', telefono: '+34 600 111 222', fecha_nacimiento: '1990-05-17', nivel_compromiso: 'nuevo', casa_oracion_id: 'c1', notas: null, activo: true, puntos: 40 }
const base = aFormulario(fila)

// De la fila al formulario: nulos a vacío, fecha sin hora, sin campos ajenos
assert.deepEqual(base, { nombre: 'Ana', apellido: 'Uno', email: 'ana@x.test', telefono: '+34 600 111 222', fecha_nacimiento: '1990-05-17', nivel_compromiso: 'nuevo', casa_oracion_id: 'c1', notas: '', activo: true })
assert.equal(aFormulario({ ...fila, fecha_nacimiento: '1990-05-17T00:00:00+00:00' }).fecha_nacimiento, '1990-05-17')
assert.equal(aFormulario({ nombre: 'X', apellido: '', activo: false }).activo, false)
assert.equal(aFormulario({ nombre: 'X', apellido: '' }).nivel_compromiso, 'nuevo', 'sin nivel, el de partida')

// Una ficha sin tocar es válida y no cambia nada
assert.deepEqual(validarFicha(base, o), {})
assert.deepEqual(cambiosDe(base, base, o), {})

// Validación campo a campo
const err = (cambio: Partial<FichaForm>, op = o) => validarFicha({ ...base, ...cambio }, op)
assert.equal(err({ nombre: '   ' }).nombre, 'ficha.errores.nombre')
assert.equal(err({ nombre: 'x'.repeat(101) }).nombre, 'ficha.errores.nombreInvalido')
assert.equal(err({ nombre: 'Ana​' }).nombre, 'ficha.errores.nombreInvalido', 'cero ancho no tiene sitio en un nombre')
assert.equal(err({ apellido: '' }).apellido, 'ficha.errores.apellido')
assert.equal(err({ apellido: '' }, alias).apellido, undefined, 'en modo alias no hay apellido')
assert.equal(err({ email: '' }).email, undefined, 'el correo es opcional')
for (const malo of ['sin-arroba', 'a@b', 'a b@c.d', 'a@b.c ' + 'x'.repeat(260)]) assert.equal(err({ email: malo }).email, 'ficha.errores.email', malo)
assert.equal(err({ email: 'malo' }, alias).email, undefined, 'en modo alias el correo no se valida porque no se toca')
assert.equal(err({ telefono: '' }).telefono, undefined, 'el teléfono es opcional')
for (const malo of ['abc', '12', '+34 6', '600-AAA-111']) assert.equal(err({ telefono: malo }).telefono, 'ficha.errores.telefono', malo)
assert.equal(err({ telefono: '(34) 600.111-222' }).telefono, undefined)
for (const malo of ['1990-02-30', '1990-13-01', '90-05-17', '1899-12-31', '2026-11-17', 'ayer']) assert.equal(err({ fecha_nacimiento: malo }).fecha_nacimiento, 'ficha.errores.fechaNacimiento', malo)
assert.equal(err({ fecha_nacimiento: '2026-11-16' }).fecha_nacimiento, undefined, 'hoy sí')
assert.equal(err({ fecha_nacimiento: '1996-02-29' }).fecha_nacimiento, undefined, 'bisiesto válido')
assert.equal(err({ fecha_nacimiento: '' }).fecha_nacimiento, undefined)
assert.equal(err({ nivel_compromiso: 'rey' }).nivel_compromiso, 'ficha.errores.nivel')
assert.equal(err({ notas: 'x'.repeat(2001) }).notas, 'ficha.errores.notas')
assert.deepEqual(Object.keys(validarFicha({ ...base, nombre: '', apellido: '', email: 'x', telefono: 'x' }, o)).sort(), ['apellido', 'email', 'nombre', 'telefono'], 'todos los errores a la vez')

// Cambios mínimos: solo lo que cambia, ya normalizado
const c = (cambio: Partial<FichaForm>, op = o) => cambiosDe(base, { ...base, ...cambio }, op)
assert.deepEqual(c({ nombre: '  Ana   María ' }), { nombre: 'Ana María' }, 'espacios normalizados')
assert.deepEqual(c({ nombre: ' Ana ' }), {}, 'un espacio de más no es un cambio')
assert.deepEqual(c({ email: ' ANA@X.TEST ' }), {}, 'mayúsculas y espacios del mismo correo no cambian nada')
assert.deepEqual(c({ email: 'Nueva@X.test' }), { email: 'nueva@x.test' })
assert.deepEqual(c({ email: '' }), { email: null }, 'vaciar un dato lo deja en nulo, no en texto vacío')
assert.deepEqual(c({ telefono: '' }), { telefono: null })
assert.deepEqual(c({ fecha_nacimiento: '' }), { fecha_nacimiento: null })
assert.deepEqual(c({ casa_oracion_id: '' }), { casa_oracion_id: null }, 'quitar de la casa')
assert.deepEqual(c({ casa_oracion_id: 'c2' }), { casa_oracion_id: 'c2' })
assert.deepEqual(c({ notas: 'Visita en 2025' }), { notas: 'Visita en 2025' })
assert.deepEqual(c({ activo: false }), { activo: false })
assert.deepEqual(c({ nivel_compromiso: 'maduro', telefono: '+34 600 999 000' }), { nivel_compromiso: 'maduro', telefono: '+34 600 999 000' })
assert.deepEqual(c({ notas: '   ' }), {}, 'notas en blanco igual que sin notas')
// Una ficha cuyas notas ya existían: espacios finales no la tocan
const conNotas = aFormulario({ ...fila, notas: 'Registrado por QR' })
assert.deepEqual(cambiosDe(conNotas, { ...conNotas, notas: 'Registrado por QR  ' }, o), {})
// Modo alias: nunca se envía apellido ni correo, aunque el formulario los traiga
const base2 = aFormulario({ nombre: 'Roble-01', apellido: '', email: null, telefono: null, nivel_compromiso: 'nuevo', activo: true })
assert.deepEqual(cambiosDe(base2, { ...base2, nombre: 'Roble-02', apellido: 'Intruso', email: 'x@y.z' }, alias), { nombre: 'Roble-02' })
// El resultado nunca contiene campos que no son del formulario
assert.deepEqual(Object.keys(cambiosDe(base, { ...base, nombre: 'Z', apellido: 'Y', email: 'a@b.cd', telefono: '', fecha_nacimiento: '', nivel_compromiso: 'lider', casa_oracion_id: '', notas: 'n', activo: false }, o)).sort(),
  ['activo', 'apellido', 'casa_oracion_id', 'email', 'fecha_nacimiento', 'nivel_compromiso', 'nombre', 'notas', 'telefono'])
assert.ok(!('puntos' in cambiosDe(base, { ...base, nombre: 'Z' }, o)))
console.log('Ficha: todo correcto')
