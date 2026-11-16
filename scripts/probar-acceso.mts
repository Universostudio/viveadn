// Prueba del menú y de los accesos por rol, con los permisos REALES de cada rol de sistema. Sin red ni navegador.
// Uso: npm run test:acceso
// Los permisos de cada rol son los que siembra la base (esquema base y migración 20261030000000). supabase/tests/adn_roles_permisos.sql comprueba la misma huella md5
// en la base: si alguien cambia los permisos de un rol, fallan los dos y hay que actualizar esta tabla y el mapa docs/MAPA-ACCESOS.md.
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { tarjetasDeInicio } from '../src/lib/panelInicio.ts'
import { REQUISITOS_RUTA, aterrizajeDe, cumple, esLiderDeCasa, itemsVisibles, type ContextoAcceso } from '../src/lib/acceso.ts'

const ROLES: Record<string, { md5: string; permisos: string[] }> = {
"administrador": {
  md5: "94f21315898a062f51439b534f8990c5",
  permisos: [
    "asistencia.registrar",
    "asistencia.registrar_propia",
    "asistencia.ver",
    "asistencia.ver_propia",
    "asistencia.ver_zona",
    "casas.crear",
    "casas.editar",
    "casas.eliminar",
    "casas.ver",
    "casas.ver_propia",
    "casas.ver_zona",
    "comunicacion.enviar",
    "comunicacion.ver",
    "consolidacion.crear",
    "consolidacion.editar",
    "consolidacion.eliminar",
    "consolidacion.reasignar",
    "consolidacion.registrar_contacto",
    "consolidacion.ver",
    "consolidacion.ver_asignados",
    "consolidacion.ver_casa",
    "consolidacion.ver_propios",
    "consolidacion.ver_zona",
    "eventos.gestionar",
    "eventos.ver",
    "formacion.actualizar",
    "formacion.certificar",
    "formacion.programas",
    "formacion.ver",
    "gamificacion.gestionar",
    "gamificacion.ver",
    "miembros.crear",
    "miembros.editar",
    "miembros.eliminar",
    "miembros.exportar",
    "miembros.importar",
    "miembros.ver",
    "miembros.ver_asignados",
    "miembros.ver_propios",
    "miembros.ver_zona",
    "reportes.ver",
    "usuarios.gestionar",
    "usuarios.ver",
    "zonas.gestionar",
    "zonas.ver"
  ]
},
"coadministrador": {
  md5: "280bd9da3c8d9f210221bd0286847eda",
  permisos: [
    "asistencia.registrar",
    "asistencia.ver",
    "casas.crear",
    "casas.editar",
    "casas.eliminar",
    "casas.ver",
    "comunicacion.enviar",
    "comunicacion.ver",
    "consolidacion.crear",
    "consolidacion.editar",
    "consolidacion.eliminar",
    "consolidacion.reasignar",
    "consolidacion.ver",
    "eventos.gestionar",
    "eventos.ver",
    "formacion.actualizar",
    "formacion.certificar",
    "formacion.programas",
    "formacion.ver",
    "gamificacion.gestionar",
    "gamificacion.ver",
    "miembros.crear",
    "miembros.editar",
    "miembros.eliminar",
    "miembros.exportar",
    "miembros.importar",
    "miembros.ver",
    "reportes.ver",
    "usuarios.ver",
    "zonas.gestionar",
    "zonas.ver"
  ]
},
"colaborador": {
  md5: "28bdeb85339d0a520fff40c52bbfcfbc",
  permisos: [
    "asistencia.registrar",
    "asistencia.ver_propia",
    "casas.ver",
    "consolidacion.crear",
    "consolidacion.ver_propios",
    "eventos.ver",
    "miembros.crear",
    "miembros.ver_propios",
    "zonas.ver"
  ]
},
"consolidador": {
  md5: "4416dc8d48acd52a09d250e0ad8ffae5",
  permisos: [
    "consolidacion.registrar_contacto",
    "consolidacion.ver_asignados",
    "eventos.ver",
    "miembros.ver_asignados",
    "usuarios.ver",
    "zonas.ver"
  ]
},
"lider_casa": {
  md5: "ea7edaf4267bfde9028b96471cafb529",
  permisos: [
    "asistencia.registrar_propia",
    "casas.ver_propia",
    "consolidacion.ver_casa",
    "eventos.ver",
    "miembros.ver_asignados",
    "usuarios.ver",
    "zonas.ver"
  ]
},
"lider_escuela": {
  md5: "8cda70fc2cb1a1e452c2b6665932ef7b",
  permisos: [
    "eventos.ver",
    "formacion.actualizar",
    "formacion.certificar",
    "formacion.programas",
    "formacion.ver",
    "gamificacion.ver",
    "miembros.ver",
    "usuarios.ver",
    "zonas.ver"
  ]
},
"lider_zona": {
  md5: "1e565d6c7c5747edd5b0d0f8332662f1",
  permisos: [
    "asistencia.ver_zona",
    "casas.ver_zona",
    "consolidacion.ver_zona",
    "eventos.ver",
    "gamificacion.ver",
    "miembros.ver_zona",
    "reportes.ver",
    "usuarios.ver",
    "zonas.ver"
  ]
},
"miembro": {
  md5: "9bb5ce6c79fb6454d037f4cead6b5dfb",
  permisos: [
    "eventos.ver"
  ]
},
"propietario": {
  md5: "d41d8cd98f00b204e9800998ecf8427e",
  permisos: []
}
}

for (const [r, { md5, permisos }] of Object.entries(ROLES)) assert.equal(createHash('md5').update([...permisos].sort().join(',')).digest('hex'), md5, `la huella de ${r} no coincide: ¿cambiaron sus permisos?`)

// Contexto de un rol: el propietario lo puede todo; el resto, lo que tiene; con todos los módulos del plan activos salvo que se diga otra cosa
function ctxDe(rol: string, { modulos = new Set(['eventos', 'comunicacion']), sedes = false } = {}): ContextoAcceso {
  const propietario = rol === 'propietario'
  const perms = new Set(ROLES[rol].permisos)
  return { can: (...c) => c.some(x => propietario || perms.has(x)), tieneModulo: m => modulos.has(m), esPropietario: propietario, tieneSedes: sedes }
}
const menuCompleto = (rol: string, o?: Parameters<typeof ctxDe>[1]) => itemsVisibles(ctxDe(rol, o)).map(i => i.clave)
// Novedades y soporte se comprueban aparte: el menú de trabajo no cambia con ellos
const menuDe = (rol: string, o?: Parameters<typeof ctxDe>[1]) => menuCompleto(rol, o).filter(c => c !== 'novedades' && c !== 'soporte')

// Tarjetas del panel de inicio por rol, con los permisos reales: amplio cuenta todo, acotado cuenta lo suyo, sin permiso no hay tarjeta
const tarjetas = (rol: string) => tarjetasDeInicio(ctxDe(rol).can)
for (const r of ['propietario', 'administrador', 'coadministrador']) assert.deepEqual(tarjetas(r), { personas: 'todo', casas: 'todo', seguimiento: 'todo', nuevaPersona: true }, r)
assert.deepEqual(tarjetas('lider_zona'), { personas: 'acotado', casas: 'acotado', seguimiento: 'acotado', nuevaPersona: false }, 'el líder de zona cuenta lo de su zona')
assert.deepEqual(tarjetas('lider_casa'), { personas: 'acotado', casas: 'acotado', seguimiento: 'acotado', nuevaPersona: false }, 'el líder de casa cuenta lo suyo')
assert.equal(tarjetas('consolidador').seguimiento, 'acotado'); assert.equal(tarjetas('consolidador').casas, null, 'el consolidador no ve casas')
assert.deepEqual(tarjetas('miembro'), { personas: null, casas: null, seguimiento: null, nuevaPersona: false }, 'el miembro no recibe estadísticas')
assert.equal(tarjetas('lider_escuela').seguimiento, null)

const COMPLETO = ['inicio', 'miembros', 'eventos', 'casas', 'zonas', 'consolidacion', 'formacion', 'logros', 'comunicacion', 'reportes', 'configuracion']
assert.deepEqual(menuDe('propietario'), COMPLETO)
assert.deepEqual(menuDe('propietario', { sedes: true }), [...COMPLETO, 'red'], 'la red solo con sedes')
assert.deepEqual(menuDe('administrador'), COMPLETO)
assert.deepEqual(menuDe('coadministrador'), COMPLETO.filter(c => c !== 'configuracion'))
assert.deepEqual(menuDe('lider_zona'), ['inicio', 'miembros', 'eventos', 'casas', 'zonas', 'consolidacion', 'logros', 'reportes'], 'el líder de zona ya ve miembros, casas y consolidación de su zona')
assert.deepEqual(menuDe('lider_casa'), ['miPanel', 'inicio', 'miembros', 'eventos', 'casas', 'consolidacion'])
assert.deepEqual(menuDe('lider_escuela'), ['inicio', 'miembros', 'eventos', 'formacion', 'logros'])
assert.deepEqual(menuDe('consolidador'), ['inicio', 'miembros', 'eventos', 'consolidacion'])
assert.deepEqual(menuDe('colaborador'), ['inicio', 'miembros', 'eventos', 'casas', 'consolidacion'], 'el colaborador ve lo que registra')
assert.deepEqual(menuDe('miembro'), ['inicio', 'eventos'])
// Sin el módulo en el plan, la sección no se ofrece aunque el rol tenga el permiso
assert.ok(!menuDe('administrador', { modulos: new Set() }).includes('eventos')); assert.ok(!menuDe('administrador', { modulos: new Set() }).includes('comunicacion'))
// Novedades de la plataforma las ve todo el que tiene sesión; soporte solo quien puede configurar la iglesia
for (const r of Object.keys(ROLES)) {
  assert.ok(menuCompleto(r).includes('novedades'), `novedades: ${r}`)
  assert.equal(menuCompleto(r).includes('soporte'), ctxDe(r).can('iglesia.configurar'), `soporte: ${r}`)
}
// Solo el líder de casa tiene «Mi panel»
for (const r of Object.keys(ROLES)) assert.equal(menuDe(r).includes('miPanel'), r === 'lider_casa', `miPanel: ${r}`)
assert.ok(esLiderDeCasa(ctxDe('lider_casa'))); assert.ok(!esLiderDeCasa(ctxDe('administrador'))); assert.ok(!esLiderDeCasa(ctxDe('propietario')))

// Aterrizaje
for (const r of Object.keys(ROLES)) assert.equal(aterrizajeDe(ctxDe(r)), r === 'lider_casa' ? 'mi-panel' : 'dashboard', `aterrizaje: ${r}`)

// El menú y la comprobación de la ruta usan las mismas reglas: lo que el menú ofrece, la ruta lo permite, y viceversa
const RUTA_DE_ITEM: Record<string, string> = { miPanel: 'mi-panel', miembros: 'miembros', eventos: 'eventos', casas: 'casas', zonas: 'zonas', consolidacion: 'consolidacion', formacion: 'formacion', logros: 'logros', comunicacion: 'comunicacion', reportes: 'reportes', configuracion: 'configuracion', red: 'red', soporte: 'soporte' }
for (const rol of Object.keys(ROLES)) for (const sedes of [false, true]) {
  const c = ctxDe(rol, { sedes }); const visibles = new Set(itemsVisibles(c).map(i => i.clave))
  for (const [item, ruta] of Object.entries(RUTA_DE_ITEM)) assert.equal(cumple(REQUISITOS_RUTA[ruta], c), visibles.has(item), `${rol}: el menú y la ruta ${ruta} deben coincidir`)
}
// Rutas que no están en el menú
assert.ok(cumple(REQUISITOS_RUTA['datos-iglesia'], ctxDe('propietario'))); assert.ok(!cumple(REQUISITOS_RUTA['datos-iglesia'], ctxDe('administrador')), 'datos y baja: solo el propietario')
assert.ok(cumple(REQUISITOS_RUTA['programas-formacion'], ctxDe('lider_escuela'))); assert.ok(!cumple(REQUISITOS_RUTA['programas-formacion'], ctxDe('lider_casa')))
assert.ok(cumple(REQUISITOS_RUTA['miembro-detalle'], ctxDe('lider_zona'))); assert.ok(!cumple(REQUISITOS_RUTA['miembro-detalle'], ctxDe('miembro')), 'un miembro no abre fichas')
assert.ok(!cumple(REQUISITOS_RUTA.configuracion, ctxDe('lider_zona'))); assert.ok(!cumple(REQUISITOS_RUTA.reportes, ctxDe('lider_casa')))
assert.ok(!cumple(REQUISITOS_RUTA['mi-panel'], ctxDe('administrador')), 'un administrador no tiene Mi panel de líder de casa')
// Una ruta sin requisitos solo pide sesión
assert.equal(REQUISITOS_RUTA.dashboard, undefined)

console.log('Acceso: todo correcto')
