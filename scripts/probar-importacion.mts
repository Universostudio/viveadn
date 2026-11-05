// Pruebas de la lectura y validación del CSV de miembros. Uso: npm run test:importacion
import assert from 'node:assert/strict'
const lib = await import('../src/lib/importarMiembros.ts')
const { parseCsv, fechaIso, analizarCsv, marcarDuplicados, claveMiembro, PLANTILLA_CSV } = lib
// separadores y comillas
assert.deepEqual(parseCsv('a;b;c\n1;"x;y";3'), [['a','b','c'],['1','x;y','3']])
assert.deepEqual(parseCsv('a,b\r\n"di ""hola""","l1\nl2"\r\n'), [['a','b'],['di "hola"','l1\nl2']])
assert.deepEqual(parseCsv('﻿a\tb\n1\t2'), [['a','b'],['1','2']])
assert.equal(parseCsv('a,b\n\n,\n1,2').length, 2)
// fechas
assert.equal(fechaIso('1990-05-21'), '1990-05-21'); assert.equal(fechaIso('21/05/1990'), '1990-05-21'); assert.equal(fechaIso('1-2-2000'), '2000-02-01')
assert.equal(fechaIso('31/02/2000'), null); assert.equal(fechaIso('2999-01-01'), null); assert.equal(fechaIso('1850-01-01'), null); assert.equal(fechaIso('abc'), null)
// plantilla correcta
const p = analizarCsv(PLANTILLA_CSV); assert.equal(p.filas.length, 1); assert.deepEqual(p.filas[0].errores, []); assert.equal(p.filas[0].datos.nivel_compromiso, 'en_crecimiento'); assert.equal(p.filas[0].datos.fecha_nacimiento, '1990-05-21')
// alias, acentos, columnas ignoradas, errores
const a = analizarCsv('Nombres;Apellidos;Correo electrónico;Teléfono;Fecha de nacimiento;Extra\nAna;Pérez;ANA@X.ES;600 123 456;05/03/1985;zz\n;Ruiz;mal;abc;2000-13-40;')
assert.deepEqual(a.ignoradas, ['Extra'])
assert.equal(a.filas[0].datos.email, 'ana@x.es'); assert.deepEqual(a.filas[0].errores, [])
assert.deepEqual(a.filas[1].errores.sort(), ['emailInvalido','faltaNombre','fechaInvalida','telefonoInvalido'].sort())
assert.equal(a.filas[1].linea, 3)
// errores de archivo
assert.equal(analizarCsv('').error, 'vacio'); assert.equal(analizarCsv('nombre,apellido').error, 'vacio'); assert.equal(analizarCsv('foo,bar\n1,2').error, 'sinColumnas')
assert.equal(analizarCsv('nombre,apellido\n' + Array.from({length: 2001}, (_, i) => `a${i},b`).join('\n')).error, 'demasiadasFilas')
// nivel y largo
assert.deepEqual(analizarCsv('nombre,apellido,nivel\nA,B,Líder').filas[0].errores, []); assert.equal(analizarCsv('nombre,apellido,nivel\nA,B,Líder').filas[0].datos.nivel_compromiso, 'lider')
assert.deepEqual(analizarCsv('nombre,apellido,nivel\nA,B,jefe').filas[0].errores, ['nivelInvalido'])
assert.deepEqual(analizarCsv('nombre,apellido\n' + 'x'.repeat(101) + ',B').filas[0].errores, ['demasiadoLargo'])
// duplicados: existentes, dentro del archivo, y filas con error no cuentan
const f = analizarCsv('nombre,apellido,email\nA,B,a@x.es\nC,D,A@X.ES\nE,F,\ne,f,\nG,H,g@x.es\nI,,\n').filas
const d = marcarDuplicados(f, new Set(['e:g@x.es']))
assert.deepEqual(d.map(x => x.duplicado), [false, true, false, true, true, false])
assert.equal(claveMiembro({nombre:'José', apellido:'Núñez', email:null}), claveMiembro({nombre:'jose', apellido:'NUNEZ', email:null}))
console.log('OK: todas las pruebas de importación pasan')
