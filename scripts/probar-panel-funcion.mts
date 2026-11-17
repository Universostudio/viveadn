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
// B10: un texto suelto «does not exist» (columna, valor, rol) ya no se presenta como migración pendiente
assert.ok(!faltaLaFuncion({ code: '42703', message: 'column "etapa" does not exist' }), 'una columna que falta es un fallo real, no una migración pendiente')
assert.ok(!faltaLaFuncion({ message: 'role "x" does not exist' }))
assert.ok(!faltaLaFuncion({ code: 'XX000', message: 'Something does not exist' }))
assert.ok(faltaLaFuncion({ code: '42P01', message: 'relation "public.adn_tickets" does not exist' }), 'la tabla que falta sí')
assert.ok(faltaLaFuncion({ message: 'function public.adn_plataforma_resumen() does not exist' }), 'el mensaje exacto de la función que falta, aunque no traiga código')
assert.ok(faltaLaFuncion({ code: 'PGRST205', message: "Could not find the table 'public.adn_avisos' in the schema cache" }))

console.log('Panel Maestro (función de borde): todo correcto')

// Decisión de Gerencia (informe 41, A1): la plataforma no exporta datos de personas. Las tres acciones de exportación quedan cerradas con 403 y la función no llama a ninguna exportación.
import { readFileSync } from 'node:fs'
const fuente = readFileSync(new URL('../supabase/functions/plataforma/index.ts', import.meta.url), 'utf8')
assert.match(fuente, /case 'exportar':\s*case 'exportar_plan':\s*case 'exportar_pagina':\s*return json\(\{ error: [^\n]*\}, 403\)/, 'las tres exportaciones devuelven 403')
assert.doesNotMatch(fuente, /adn_exportar|adn_tablas_exportables|construirPaquete/, 'la función de plataforma no llama a ninguna exportación de datos')
console.log('Plataforma: sin exportación de datos de personas')

// M6: ninguna lectura de la función lleva un select sin paginar sobre tablas que crecen, y los agregados salen de SQL con alternativa si falta la migración
{
  const { readFileSync } = await import('node:fs')
  const f = readFileSync(new URL('../supabase/functions/plataforma/index.ts', import.meta.url), 'utf8')
  for (const rpc of ['adn_plataforma_facturacion', 'adn_soporte_resumen', 'adn_avisos_estadisticas']) assert.ok(f.includes(`rpc('${rpc}'`), `${rpc} se usa`)
  assert.ok(!/from\('iglesias'\)\.select\('plan, activa, etapa, es_demo, adn_borrada_en'\)\s*,/.test(f), 'la facturación ya no lee iglesias sin paginar')
  assert.ok(!/from\('adn_tickets'\)\.select\('(iglesia_id, )?estado, prioridad'\)\s*,/.test(f), 'el soporte ya no lee todos los tickets sin paginar')
  const listar = f.slice(f.indexOf("case 'listar'"), f.indexOf("case 'actividad'"))
  assert.ok(/leerTodo[^\n]*from\('iglesias'\)/.test(listar) && /leerTodo[^\n]*from\('iglesia_modulos'\)/.test(listar) && /leerTodo[^\n]*adn_plataforma_resumen/.test(listar), 'listar lee iglesias, complementos y conteos por páginas')
  console.log('Panel (función): agregados en SQL y lecturas por páginas')
}

// B13 y B14: código de registro y correo de aviso, por código fuente de la función
{
  const { readFileSync } = await import('node:fs')
  const f = readFileSync(new URL('../supabase/functions/plataforma/index.ts', import.meta.url), 'utf8')
  const c = f.slice(f.indexOf("case 'codigo_crear'"), f.indexOf("case 'codigo_estado'"))
  assert.match(c, /usos_max !== undefined && !Number\.isInteger\(body\.usos_max\)\) return json\(\{ error: [^}]*\}, 400\)/, 'usos_max que no es entero se rechaza')
  assert.match(c, /dias !== undefined && !Number\.isInteger\(body\.dias\)\) return json\(\{ error: [^}]*\}, 400\)/, 'dias que no es entero se rechaza')
  assert.match(c, /dias < 1 \|\| dias > 365\) return json/, 'dias = 0 (sin vencimiento) se rechaza')
  assert.ok(!/dias > 0 \?/.test(c), 'ya no hay códigos sin vencimiento')
  const a = f.slice(f.indexOf("case 'aviso_crear'"), f.indexOf("case 'aviso_retirar'"))
  assert.match(a, /correo === 'sin_envio'\) return json\(\{ error: [^}]*\}, 409\)/, 'con el envío encendido y nadie que lo envíe, el aviso con correo se rechaza')
  console.log('Panel (función): códigos y avisos con correo se validan sin cambiar valores en silencio')
}

// Cuerpo de la petición: tope de 32 KB y solo un objeto JSON
{
  const { leerCuerpoJson, MAX_CUERPO } = await import('../supabase/functions/plataforma/panel.ts')
  assert.equal(MAX_CUERPO, 32768)
  assert.deepEqual(leerCuerpoJson('{"accion":"listar"}', '19'), { ok: true, body: { accion: 'listar' } })
  assert.deepEqual(leerCuerpoJson('', null), { ok: true, body: {} }, 'un cuerpo vacío es un objeto vacío')
  assert.deepEqual(leerCuerpoJson('{}', null), { ok: true, body: {} })
  const grande = JSON.stringify({ accion: 'x', relleno: 'a'.repeat(MAX_CUERPO) })
  assert.deepEqual(leerCuerpoJson(grande, null), { ok: false, status: 413, error: 'Cuerpo demasiado grande' }, 'el texto real pasa del tope')
  assert.equal((leerCuerpoJson('{}', String(MAX_CUERPO + 1)) as any).status, 413, 'el tamaño declarado pasa del tope aunque el texto sea corto')
  assert.equal((leerCuerpoJson('ñ'.repeat(MAX_CUERPO / 2 + 1), null) as any).status, 413, 'se cuentan bytes, no caracteres')
  for (const mal of ['[]', '"x"', '5', 'null', 'true', '{no es json']) assert.equal((leerCuerpoJson(mal, null) as any).status, 400, mal)
  const { readFileSync } = await import('node:fs')
  const f = readFileSync(new URL('../supabase/functions/plataforma/index.ts', import.meta.url), 'utf8')
  assert.ok(!/req\.json\(\)/.test(f), 'la función ya no lee el cuerpo con req.json() sin tope')
  assert.match(f, /Number\(declarado\) > MAX_CUERPO/, 'rechaza con 413 por el tamaño declarado antes de leer')
  console.log('Panel (función): cuerpo con tope de 32 KB y solo un objeto JSON')
}
