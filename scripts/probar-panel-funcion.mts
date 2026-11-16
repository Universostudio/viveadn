// Prueba de las lecturas del Panel Maestro en la función de borde: conteos, actividad, historial, envío y la barrera de privacidad.
// Uso: npm run test:panel-funcion
import assert from 'node:assert/strict'
import { clavesPersonales, conteosPorIglesia, envioDelDia, eventosDeActividad, faltaLaFuncion, historialDeIglesia, salidaSegura } from '../supabase/functions/plataforma/panel.ts'

// Barrera de privacidad: cualquier clave personal, a cualquier profundidad, hace fallar la respuesta
assert.deepEqual(clavesPersonales({ iglesias: [{ id: 'x', nombre: 'Casa', slug: 'casa', miembros: 3 }], planes: [] }), [])
for (const clave of ['email', 'correo', 'telefono', 'phone', 'apellido', 'nombre_propietario_email', 'password', 'token', 'secret', 'fecha_nacimiento', 'Email']) {
  assert.ok(clavesPersonales({ a: { b: [{ [clave]: 'x' }] } }).length > 0, `«${clave}» debe detectarse`)
  assert.throws(() => salidaSegura({ ok: true, lista: [{ [clave]: 'x' }] }), /ADN_DATOS_PERSONALES_EN_PANEL/, `«${clave}» bloquea la respuesta`)
}
assert.deepEqual(salidaSegura({ ok: true, n: 1 }), { ok: true, n: 1 }, 'una respuesta limpia pasa sin cambios')
assert.deepEqual(clavesPersonales(null), []); assert.deepEqual(clavesPersonales('texto'), []); assert.deepEqual(clavesPersonales([]), [])
// El nombre de una iglesia es un valor, no una clave: no dispara la barrera aunque se parezca a una palabra vigilada
assert.deepEqual(clavesPersonales({ nombre: 'Iglesia del email', slug: 'telefono' }), [])

// Conteos
assert.deepEqual(conteosPorIglesia([{ iglesia_id: 'a', miembros: '5', usuarios: 2 }, { iglesia_id: 'b', miembros: 0, usuarios: 0 }]), { a: { miembros: 5, usuarios: 2 }, b: { miembros: 0, usuarios: 0 } }, 'los bigint llegan como texto y se convierten')
assert.deepEqual(conteosPorIglesia(null), {}); assert.deepEqual(conteosPorIglesia([{ iglesia_id: 'a', miembros: 'x', usuarios: null as any }]), { a: { miembros: 0, usuarios: 0 } }, 'un valor raro cuenta como 0, no NaN')

// Actividad: solo tipo, acción, iglesia y fecha; el detalle jamás pasa aunque la fila lo trajera
const filas = [
  { tipo: 'alta', accion: 'crear_iglesia', iglesia_id: 'a', iglesia_nombre: 'Casa', fecha: '2026-11-16T10:00:00+00:00', detalle: { email: 'x@y.z' } },
  { tipo: 'raro', accion: 'cambiar_plan', iglesia_id: null, iglesia_nombre: null, fecha: '2026-11-16T09:00:00Z' },
] as any
const ev = eventosDeActividad(filas)
assert.deepEqual(ev[0], { tipo: 'alta', accion: 'crear_iglesia', iglesia_id: 'a', iglesia: 'Casa', fecha: '2026-11-16T10:00:00.000Z' })
assert.equal(ev[1].tipo, 'accion', 'un tipo desconocido se trata como acción')
assert.equal(ev[1].iglesia, null)
assert.ok(!JSON.stringify(ev).includes('x@y.z'), 'el detalle no sale')
salidaSegura({ eventos: ev })
assert.deepEqual(eventosDeActividad(undefined), [])
assert.deepEqual(historialDeIglesia([{ accion: 'etapa_iglesia', fecha: '2026-11-16T09:00:00Z', detalle: 'x' } as any]), [{ accion: 'etapa_iglesia', fecha: '2026-11-16T09:00:00.000Z' }])

// Envío: solo estado y cifras
const e = envioDelDia([{ tipo: 'baja', n: 2 }, { tipo: 'purga', n: 1 }, { tipo: 'baja', n: 1 }, { tipo: 'raro', n: 9 }], { activo: false, topeGlobal: 40 })
assert.deepEqual(e, { activo: false, hoy: 4, por_tipo: { purga: 1, baja: 3, confirmacion: 0 }, tope_global: 40 }, 'suma por tipo e ignora tipos desconocidos')
assert.deepEqual(envioDelDia(null, { activo: true, topeGlobal: 5000 }), { activo: true, hoy: 0, por_tipo: { purga: 0, baja: 0, confirmacion: 0 }, tope_global: 5000 })
salidaSegura({ envio: e })

// Detección de «la función aún no existe» (migración sin aplicar)
assert.ok(faltaLaFuncion({ code: '42883', message: 'function public.adn_plataforma_resumen() does not exist' }))
assert.ok(faltaLaFuncion({ code: 'PGRST202', message: 'Could not find the function public.adn_plataforma_resumen' }))
assert.ok(!faltaLaFuncion({ code: '57014', message: 'canceling statement due to statement timeout' }), 'un fallo real no se disfraza de migración pendiente')
assert.ok(!faltaLaFuncion(null))

console.log('Panel Maestro (función de borde): todo correcto')

// Decisión de Gerencia (informe 41, A1): la plataforma no exporta datos de personas. Las tres acciones de exportación quedan cerradas con 403 y la función no llama a ninguna exportación.
import { readFileSync } from 'node:fs'
const fuente = readFileSync(new URL('../supabase/functions/plataforma/index.ts', import.meta.url), 'utf8')
assert.match(fuente, /case 'exportar':\s*case 'exportar_plan':\s*case 'exportar_pagina':\s*return json\(\{ error: [^\n]*\}, 403\)/, 'las tres exportaciones devuelven 403')
assert.doesNotMatch(fuente, /adn_exportar|adn_tablas_exportables|construirPaquete/, 'la función de plataforma no llama a ninguna exportación de datos')
console.log('Plataforma: sin exportación de datos de personas')
