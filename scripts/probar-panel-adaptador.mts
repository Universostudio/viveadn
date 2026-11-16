// Prueba del adaptador y del filtrado del Panel Maestro, sin navegador ni red.
// Uso: npm run test:panel-adaptador
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { viva, aInquilino, alertasGlobales, kpisDe, resumir, vistaDe, incluirDemoPorDefecto, situacionDe, etapaDe, diasDePrueba, pruebaPorVencer, pruebaVencida, borradoVencido, eventosParaPanel, saludDe, DIA } from '../src/views/plataforma/adaptador.ts'
import { filtrarInquilinos, contarPorFiltro } from '../src/panel-maestro/filtros.ts'
import { textoDeAccion } from '../src/views/plataforma/acciones.ts'

const AHORA = Date.UTC(2026, 10, 16, 12)
const iso = (d: number) => new Date(AHORA + d * DIA).toISOString()
// Traductor de prueba: devuelve la clave y los valores, para comprobar qué se pide
const t = (clave: string, valores?: Record<string, unknown>, plural?: number) => `${clave}${valores ? JSON.stringify(valores) : ''}${plural !== undefined ? `#${plural}` : ''}`
const fecha = (i: string) => i.slice(0, 10)

const base = (o: any) => ({ id: 'x', nombre: 'N', slug: 's', plan: 'premium', activa: true, etapa: 'activa', prueba_hasta: null, borrado_programado_en: null, adn_borrada_en: null,
  es_demo: false, ciudad: null, created_at: iso(-100), iglesia_madre_id: null, miembros: 0, usuarios: 0, addons: [], ...o })
const cat = { planes: [{ clave: 'premium', nombre: 'Premium' }], modulos: [{ clave: 'm', nombre: 'Miembros', tipo: 'nucleo' }, { clave: 'e', nombre: 'Eventos', tipo: 'opcional' }, { clave: 'c', nombre: 'Comunicación', tipo: 'opcional' }], planModulos: [{ plan: 'premium', modulo: 'c' }] }

// Días de prueba y bordes
assert.equal(diasDePrueba(base({ prueba_hasta: iso(3) }), AHORA), 3)
assert.equal(diasDePrueba(base({ prueba_hasta: iso(0.2) }), AHORA), 1, 'se redondea hacia arriba: queda un día')
assert.equal(diasDePrueba(base({ prueba_hasta: null }), AHORA), null)
assert.ok(pruebaPorVencer(base({ etapa: 'prueba', prueba_hasta: iso(7) }), AHORA), 'a 7 días vence pronto')
assert.ok(!pruebaPorVencer(base({ etapa: 'prueba', prueba_hasta: iso(8) }), AHORA), 'a 8 días aún no')
assert.ok(pruebaPorVencer(base({ etapa: 'prueba', prueba_hasta: iso(3), es_demo: true }), AHORA), 'la demo cuenta igual que las demás: el interruptor decide si entra en la lista (vistaDe), no cada cifra')
assert.ok(pruebaVencida(base({ etapa: 'prueba', prueba_hasta: iso(-1) }), AHORA))
assert.ok(!pruebaVencida(base({ etapa: 'activa', prueba_hasta: iso(-1) }), AHORA), 'solo las que están en etapa de prueba')
assert.ok(borradoVencido(base({ borrado_programado_en: iso(-1) }), AHORA))
assert.ok(!borradoVencido(base({ borrado_programado_en: iso(1) }), AHORA))

// Resumen: las demos no cuentan en los totales reales
const lista = [
  base({ id: 'a', miembros: 100, created_at: iso(-10) }),
  base({ id: 'b', etapa: 'prueba', prueba_hasta: iso(2), miembros: 20, created_at: iso(-40) }),
  base({ id: 'c', etapa: 'prueba', prueba_hasta: iso(-3), miembros: 5 }),
  base({ id: 'd', activa: false, etapa: 'suspendida', miembros: 50 }),
  base({ id: 'e', es_demo: true, miembros: 300, created_at: iso(-3) }),
  base({ id: 'f', etapa: 'receso', borrado_programado_en: iso(-2), miembros: 7 }),
]
const r = resumir(vistaDe(lista, false), AHORA, 1)
assert.deepEqual({ ...r }, { activas: 1, prueba: 2, porVencer: 1, vencidas: 1, suspendidas: 1, receso: 0, baja: 1, proximaPurgaDias: -2, demos: 1, demosDentro: 0, miembros: 182, altasMes: 1, altasMesAnterior: 1 }, 'sin demostraciones: las cifras de antes, y la demo se cuenta aparte; la iglesia en receso con borrado vencido cuenta solo como «en baja»')

// UNA regla para todas las cifras: entorno, vista, resumen, filtros y listado salen de la misma lista
assert.equal(incluirDemoPorDefecto('pruebas'), true, 'en pruebas las demostraciones entran por defecto')
assert.equal(incluirDemoPorDefecto('produccion'), false, 'en producción no')
assert.equal(incluirDemoPorDefecto('lo-que-sea'), true)
assert.equal(vistaDe(lista, true).length, 6); assert.equal(vistaDe(lista, false).length, 5)
for (const incluir of [true, false]) {
  const vista = vistaDe(lista, incluir)
  const rr = resumir(vista, AHORA, lista.filter(i => i.es_demo).length)
  const filas = vista.map(l => aInquilino(l as any, cat, t, fecha, AHORA))
  const cuentas = contarPorFiltro(filas)
  const k = Object.fromEntries(kpisDe(rr, [], t, n => String(n)).map(x => [x.clave, x]))
  // Equivalencia: lo que dice la portada, lo que dicen los filtros y lo que hay en el listado es lo mismo
  assert.equal(String(cuentas.activas), k.activas.valor, `incluir=${incluir}: «Activas» de la portada y del filtro coinciden`)
  assert.equal(cuentas.prueba, rr.prueba, `incluir=${incluir}: pruebas de la portada y del filtro coinciden`)
  assert.equal(cuentas.suspendidas, rr.suspendidas)
  assert.equal(cuentas.todas, vista.length, `incluir=${incluir}: el filtro «Todas» es el número de filas`)
  assert.equal(filas.filter(f => f.estado === 'activa').length, rr.activas, 'y el listado tiene tantas activas como dice la portada')
  assert.equal(filas.reduce((n, f) => n + f.miembros, 0), rr.miembros, `incluir=${incluir}: los miembros de la portada son la suma del listado`)
  assert.equal(k.demos.valor, '1', 'las demostraciones se cuentan aparte, estén dentro o fuera')
  assert.equal(rr.demosDentro, incluir ? 1 : 0)
}
const conDemo = resumir(vistaDe(lista, true), AHORA, 1)
assert.deepEqual({ activas: conDemo.activas, miembros: conDemo.miembros, prueba: conDemo.prueba }, { activas: 2, miembros: 482, prueba: 2 }, 'con demostraciones: la demo activa y sus 300 personas entran en las cifras')
assert.match(kpisDe(conDemo, [], t, String).find(x => x.clave === 'demos')!.nota!, /demosDentro/)
assert.match(kpisDe(r, [], t, String).find(x => x.clave === 'demos')!.nota!, /demosFuera/)

// Ciclo de vida: suspendidas, en receso y en baja no se solapan y su suma con activas, prueba y alta cubre toda la lista
const DIAS30 = 30
const ciclo = [
  base({ id: 'c1' }),
  base({ id: 'c2', etapa: 'prueba', prueba_hasta: iso(5) }),
  base({ id: 'c3', activa: false, etapa: 'suspendida' }),
  base({ id: 'c4', activa: false, etapa: 'receso' }),
  base({ id: 'c5', activa: false, etapa: 'suspendida', adn_borrada_en: iso(-1), borrado_programado_en: iso(DIAS30 - 1) }),
  base({ id: 'c6', activa: false, etapa: 'receso', borrado_programado_en: iso(10) }),
  base({ id: 'c7', etapa: 'onboarding' }),
]
const rc = resumir(ciclo, AHORA, 0)
assert.deepEqual({ a: rc.activas, p: rc.prueba, s: rc.suspendidas, r: rc.receso, b: rc.baja }, { a: 1, p: 1, s: 1, r: 1, b: 2 })
assert.equal(rc.proximaPurgaDias, 10, 'la próxima purga es la más cercana de las iglesias en baja')
assert.equal(rc.activas + rc.prueba + rc.suspendidas + rc.receso + rc.baja + ciclo.filter(i => etapaDe(i) === 'onboarding').length, ciclo.length, 'cada iglesia cuenta una sola vez')
assert.equal(resumir(ciclo.slice(0, 4), AHORA, 0).proximaPurgaDias, null, 'sin iglesias en baja no hay próxima purga')
const filasCiclo = ciclo.map(l => aInquilino(l as any, cat, t, fecha, AHORA))
const cc = contarPorFiltro(filasCiclo)
assert.deepEqual({ s: cc.suspendidas, r: cc.receso, b: cc.baja }, { s: 1, r: 1, b: 2 }, 'los filtros cuentan lo mismo que la portada')
assert.equal(filtrarInquilinos(filasCiclo, 'baja', '').length, 2)
assert.equal(aInquilino(ciclo[4] as any, cat, t, fecha, AHORA).diasParaPurga, 29)
assert.match(aInquilino(ciclo[4] as any, cat, t, fecha, AHORA).detalleEstado!, /estado\.baja\{"fecha":"[^"]+","n":29\}#29/, 'el detalle dice cuántos días faltan')
assert.match(aInquilino(ciclo[5] as any, cat, t, fecha, AHORA).detalleEstado!, /estado\.bajaProgramada/)
assert.equal(aInquilino(ciclo[0] as any, cat, t, fecha, AHORA).enBaja, false)
const kb = Object.fromEntries(kpisDe(rc, [], t, String).map(k => [k.clave, k]))
assert.equal(kb.baja.valor, '2'); assert.match(kb.baja.nota!, /bajaProxima\{"n":10\}#10/); assert.equal(kb.receso.valor, '1')
assert.match(kpisDe(r, [], t, String).find(k => k.clave === 'baja')!.nota!, /bajaVencida/, 'una purga vencida se dice')
assert.match(kpisDe(resumir(ciclo.slice(0, 2), AHORA, 0), [], t, String).find(k => k.clave === 'baja')!.nota!, /bajaNinguna/)
// Situación que explica la ficha
assert.deepEqual(ciclo.map(i => situacionDe(i as any, AHORA)), ['activa', 'prueba', 'suspendida', 'receso', 'baja_suave', 'baja_programada', 'onboarding'])
assert.equal(situacionDe(base({ etapa: 'suspendida', activa: false, adn_borrada_en: iso(-31), borrado_programado_en: iso(-1) }) as any, AHORA), 'baja_vencida')
assert.equal(situacionDe(base({ etapa: 'raro' }) as any, AHORA), 'activa', 'una etapa desconocida no rompe')

// Alertas: solo cifras y rutas, sin nombres de personas
const alertas = alertasGlobales(lista, { atrasada: true, en_borrado: 1, vencidas: 1, horas_mas_atrasada: 60 }, t, AHORA)
assert.deepEqual(alertas.map(a => a.clave), ['purga', 'pruebasVencidas', 'borradoVencido'])
assert.match(alertas[1].texto, /pruebasVencidas\{"n":1\}#1/, 'el plural lleva el número')
assert.equal(alertasGlobales(lista.slice(0, 1), { atrasada: false, en_borrado: 0, vencidas: 0, horas_mas_atrasada: 0 }, t, AHORA).length, 0, 'sin problemas no hay alertas')
assert.equal(alertasGlobales(lista.slice(0, 1), null, t, AHORA).length, 0, 'si la purga no responde no se inventa una alerta')

// KPIs: nada inventado
const kpis = kpisDe(r, alertas, t, n => String(n))
const porClave = Object.fromEntries(kpis.map(k => [k.clave, k]))
assert.deepEqual(kpis.map(k => k.clave), ['activas', 'prueba', 'suspendidas', 'receso', 'baja', 'demos', 'miembros', 'facturacion', 'alertas'])
assert.equal(porClave.facturacion.valor, null, 'la facturación no tiene datos: sin cifra')
assert.ok(porClave.facturacion.sinConectar, 'y dice qué falta')
assert.equal(porClave.miembros.valor, '182')
assert.equal(porClave.alertas.valor, '3')
assert.equal(porClave.prueba.tono, 'alerta')

// Adaptador: solo lleva a la tabla los campos permitidos, nunca datos de personas aunque la entrada los trajera
const sucia = base({ id: 'z', nombre: 'Casa', slug: 'casa', ciudad: 'Madrid', miembros: 12, plan: 'premium', addons: [{ modulo: 'e', activo: true }],
  email: 'a@b.c', telefono: '600', apellido: 'Gómez', propietario: 'Ana', notas: 'secreto' })
const inq = aInquilino(sucia as any, cat, t, fecha, AHORA)
const salida = JSON.stringify(inq)
for (const prohibido of ['a@b.c', '600', 'Gómez', 'Ana', 'secreto', 'email', 'telefono', 'apellido', 'propietario']) assert.ok(!salida.includes(prohibido), `no debe filtrarse «${prohibido}»`)
assert.deepEqual(inq.modulos.map(m => [m.clave, m.activo]), [['e', true], ['c', true]], 'módulos opcionales: contratado aparte e incluido por el plan; el núcleo no se lista')
assert.equal(inq.subtitulo, 'casa · Madrid')
assert.equal(inq.miembros, 12)
assert.equal(aInquilino(base({ plan: 'desconocido' }) as any, cat, t, fecha, AHORA).plan?.nombre, 'desconocido', 'un plan fuera del catálogo se muestra tal cual y no rompe')
assert.equal(aInquilino(base({ miembros: undefined }) as any, cat, t, fecha, AHORA).miembros, 0, 'sin conteo: 0 y no NaN')

// Estado con días restantes
assert.match(aInquilino(base({ etapa: 'prueba', prueba_hasta: iso(3) }) as any, cat, t, fecha, AHORA).detalleEstado!, /diasRestantes\{"n":3\}#3/)
assert.equal(aInquilino(base({ etapa: 'prueba', prueba_hasta: iso(0) }) as any, cat, t, fecha, AHORA).detalleEstado, 'plataformaPanel.estado.venceHoy')
assert.equal(aInquilino(base({ etapa: 'prueba', prueba_hasta: iso(-2) }) as any, cat, t, fecha, AHORA).detalleUrgente, true)

// Filtros y búsqueda
const inqs = lista.map(l => aInquilino({ ...l, nombre: l.id === 'a' ? 'Iglesia Álamo' : l.id, ciudad: l.id === 'a' ? 'Málaga' : null } as any, cat, t, fecha, AHORA))
assert.deepEqual(contarPorFiltro(inqs), { todas: 6, activas: 2, prueba: 2, suspendidas: 1, receso: 0, baja: 1, demo: 1 }, 'las demostraciones que están en la lista cuentan en su estado y también en «Demo»')
assert.equal(filtrarInquilinos(inqs, 'todas', 'alamo').length, 1, 'sin acentos ni mayúsculas')
assert.equal(filtrarInquilinos(inqs, 'todas', 'MALAGA').length, 1, 'la ciudad también busca')
assert.equal(filtrarInquilinos(inqs, 'prueba', 'alamo').length, 0, 'filtro y búsqueda se combinan')
assert.equal(filtrarInquilinos(inqs, 'todas', '   ').length, 6, 'una búsqueda en blanco no filtra')
assert.equal(filtrarInquilinos([], 'todas', 'x').length, 0)

// Textos de la auditoría: una acción desconocida cae a un texto genérico (nunca se muestra el detalle)
const existe = (c: string) => c === 'plataformaPanel.accionAuditoria.cambiar_plan'
assert.equal(textoDeAccion('cambiar_plan', t as any, existe), 'plataformaPanel.accionAuditoria.cambiar_plan')
assert.equal(textoDeAccion('algo_nuevo', t as any, existe), 'plataformaPanel.accionAuditoria.otra')

// Actividad global: alta, acción con iglesia, acción sin iglesia y acción desconocida; nunca el detalle ni claves internas
const exAcc = (c: string) => c === 'plataformaPanel.accionAuditoria.cambiar_plan'
const evs = eventosParaPanel([
  { tipo: 'alta', accion: 'crear_iglesia', iglesia_id: 'a', iglesia: 'Casa', fecha: '2026-11-16T10:00:00.000Z' },
  { tipo: 'accion', accion: 'cambiar_plan', iglesia_id: 'a', iglesia: 'Casa', fecha: '2026-11-16T09:00:00.000Z' },
  { tipo: 'accion', accion: 'cambiar_plan', iglesia_id: null, iglesia: null, fecha: '2026-11-16T08:00:00.000Z' },
  { tipo: 'accion', accion: 'rara', iglesia_id: 'b', iglesia: 'Otra', fecha: '2026-11-16T07:00:00.000Z' },
], t, exAcc)
assert.match(evs[0].texto, /actividad\.alta\{"iglesia":"Casa"\}/)
assert.match(evs[1].texto, /actividad\.evento/); assert.match(evs[1].texto, /accionAuditoria\.cambiar_plan/)
assert.match(evs[2].texto, /actividad\.sinIglesia/)
assert.match(evs[3].texto, /accionAuditoria\.otra/); assert.ok(!evs[3].texto.includes('rara'), 'la clave interna desconocida no se muestra')
assert.equal(new Set(evs.map(e => e.id)).size, 4, 'cada evento tiene identificador distinto')

// Salud: solo lo que se conoce; la disponibilidad por servicio siempre «sin conectar»
const purgaOk = { atrasada: false, en_borrado: 0, vencidas: 0, horas_mas_atrasada: 0 }
let sal = saludDe(purgaOk, { activo: false, hoy: 0, tope_global: 40, contadores: true }, t)
assert.deepEqual(sal.map(s => [s.clave, s.situacion]), [['purga', 'ok'], ['envio', 'apagado'], ['disponibilidad', 'sin_conectar']])
sal = saludDe({ ...purgaOk, atrasada: true, horas_mas_atrasada: 60 }, { activo: true, hoy: 10, tope_global: 40, contadores: true }, t)
assert.equal(sal[0].situacion, 'alerta'); assert.equal(sal[1].situacion, 'ok'); assert.equal(sal[1].porcentaje, 25)
assert.equal(saludDe(purgaOk, { activo: true, hoy: 100, tope_global: 40, contadores: true }, t)[1].porcentaje, 100, 'la barra no pasa de 100')
assert.equal(saludDe(purgaOk, { activo: true, hoy: 5, tope_global: 0, contadores: true }, t)[1].porcentaje, undefined, 'con tope 0 no hay barra (sin dividir entre cero)')
sal = saludDe(null, null, t)
assert.deepEqual(sal.map(s => s.situacion), ['sin_conectar', 'sin_conectar', 'sin_conectar'], 'si no responden, se dice y no se inventa un estado sano')

console.log('Panel Maestro (adaptador y filtros): todo correcto')

// M4: criterio único de «miembros»: las iglesias en borrado suave no suman en ninguna pantalla (portada, reportes y facturación comparten `viva`)
{
  const conBorrada = [base({ id: 'x', miembros: 10 }), base({ id: 'y', miembros: 90, adn_borrada_en: iso(-1), borrado_programado_en: iso(20) })]
  assert.ok(viva(conBorrada[0]) && !viva(conBorrada[1]))
  assert.equal(resumir(conBorrada, AHORA).miembros, 10, 'la portada no suma los miembros de una iglesia en borrado suave')
}
// M4: con el interruptor encendido, una demo en prueba cuenta en «por vencer» y en «prueba»; apagado, en ninguna
{
  const l = [base({ id: 'p', etapa: 'prueba', prueba_hasta: iso(3) }), base({ id: 'q', etapa: 'prueba', prueba_hasta: iso(2), es_demo: true })]
  assert.deepEqual([resumir(vistaDe(l, true), AHORA).prueba, resumir(vistaDe(l, true), AHORA).porVencer], [2, 2])
  assert.deepEqual([resumir(vistaDe(l, false), AHORA).prueba, resumir(vistaDe(l, false), AHORA).porVencer], [1, 1])
}

// M4: la portada no recorta la lista a 8 antes de filtrar: los contadores y los filtros usan todas las iglesias de la lista que se ve
{
  const portada = readFileSync(new URL('../src/views/plataforma/PortadaView.vue', import.meta.url), 'utf8')
  assert.ok(!/\.slice\(0, 8\)/.test(portada), 'la portada ya no recorta con slice(0, 8)')
  assert.match(portada, /:limite-inicial="8"/)
  const tabla = readFileSync(new URL('../src/panel-maestro/TablaInquilinos.vue', import.meta.url), 'utf8')
  assert.match(tabla, /contarPorFiltro\(props\.inquilinos\)/)
  const layout = readFileSync(new URL('../src/views/plataforma/PlataformaLayout.vue', import.meta.url), 'utf8')
  const pruebas = readFileSync(new URL('../src/views/plataforma/PruebasView.vue', import.meta.url), 'utf8')
  assert.ok(!/contadorPruebas[^\n]*es_demo/.test(layout) && !/es_demo/.test(pruebas), 'Pruebas y su contador obedecen al interruptor, sin excluir demos por su cuenta')
  assert.match(layout, /watch\(\(\) => pm\.incluirDemo/)
  console.log('Panel (inicio): portada con contadores reales y un solo interruptor de demostraciones')
}
