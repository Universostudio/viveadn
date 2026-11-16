// Prueba de las reglas de líderes: quién es candidato, códigos de zona y recuento de casas por zona. Sin red ni navegador.
// Uso: npm run test:lideres
import assert from 'node:assert/strict'
import { candidatos, casasPorZona, codigoDeZonaValido, normalizarCodigoZona } from '../src/lib/lideres.ts'

const roles = [
  { clave: 'propietario', es_propietario: true, rol_permisos: [] },
  { clave: 'lider_zona', rol_permisos: [{ permiso: 'casas.ver_zona' }, { permiso: 'zonas.ver' }] },
  { clave: 'lider_casa', rol_permisos: [{ permiso: 'casas.ver_propia' }] },
  { clave: 'miembro', rol_permisos: [{ permiso: 'eventos.ver' }] },
]
const perfiles = [
  { id: 'p', nombre: 'Pro', apellido: 'Pietario', rol: 'propietario', activo: true },
  { id: 'z', nombre: 'Zona', apellido: 'Uno', rol: 'lider_zona', activo: true },
  { id: 'z2', nombre: 'Zona', apellido: 'Baja', rol: 'lider_zona', activo: false },
  { id: 'c', nombre: 'Casa', apellido: 'Uno', rol: 'lider_casa', activo: true },
  { id: 'm', nombre: 'Mi', apellido: 'Embro', rol: 'miembro', activo: true },
  { id: 'x', nombre: 'Rol', apellido: 'Raro', rol: 'inventado', activo: true },
]
assert.deepEqual(candidatos(roles, perfiles, 'casas.ver_zona').map(p => p.id), ['p', 'z'], 'líder de zona: rol con ver_zona y el propietario; no el inactivo')
assert.deepEqual(candidatos(roles, perfiles, 'casas.ver_propia').map(p => p.id), ['p', 'c'], 'líder de casa: rol con ver_propia y el propietario')
assert.deepEqual(candidatos(roles, perfiles, 'consolidacion.registrar_contacto').map(p => p.id), ['p'], 'sin ningún rol con el permiso, solo el propietario')
assert.deepEqual(candidatos([], perfiles, 'casas.ver_zona'), [], 'sin roles cargados no se inventa nadie')
assert.deepEqual(candidatos(roles, [], 'casas.ver_zona'), [])
assert.ok(!candidatos(roles, perfiles, 'casas.ver_zona').some(p => p.rol === 'miembro' || p.rol === 'inventado'), 'un rol sin el permiso nunca es candidato')

assert.ok(codigoDeZonaValido('NORTE')); assert.ok(codigoDeZonaValido('Z1')); assert.ok(codigoDeZonaValido('ZONA12345'))
assert.ok(!codigoDeZonaValido('N')); assert.ok(!codigoDeZonaValido('norte')); assert.ok(!codigoDeZonaValido('ZONA-1')); assert.ok(!codigoDeZonaValido('ABCDEFGHIJK')); assert.ok(!codigoDeZonaValido(''))
assert.equal(normalizarCodigoZona('  zona-norte 1 '), 'ZONANORTE1', 'se pasan a mayúsculas y se quitan símbolos')

assert.deepEqual(casasPorZona([{ zona_id: 'a' }, { zona_id: 'a' }, { zona_id: 'b' }, { zona_id: null }]), { porZona: { a: 2, b: 1 }, sinZona: 1 })
assert.deepEqual(casasPorZona([]), { porZona: {}, sinZona: 0 })

console.log('Líderes: todo correcto')
