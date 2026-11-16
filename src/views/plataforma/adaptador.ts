// Adaptador de Vive ADN: traduce lo que devuelve la función «plataforma» a los tipos genéricos de src/panel-maestro.
// Es puro (sin Vue ni red) para poder probarlo en Node. Solo maneja conteos, estados y nombres de iglesias: nunca datos de personas.
import type { EstadoServicio, EventoActividad, Inquilino, Kpi, ModuloInquilino } from '../../panel-maestro/tipos.ts'
import { textoDeAccion } from './acciones.ts'

export type Traductor = (clave: string, valores?: Record<string, unknown>, plural?: number) => string

export interface IglesiaFila {
  id: string; nombre: string; slug: string; plan: string; activa: boolean; etapa: string | null
  prueba_hasta: string | null; borrado_programado_en: string | null; adn_borrada_en: string | null
  es_demo: boolean; pais?: string | null; ciudad?: string | null; created_at: string
  iglesia_madre_id: string | null; red_acceso?: string
  miembros?: number; usuarios?: number
  addons?: { modulo: string; activo: boolean }[]
}
export interface Catalogo {
  planes: { clave: string; nombre: string; max_miembros?: number | null }[]
  modulos: { clave: string; nombre: string; tipo: string }[]
  planModulos: { plan: string; modulo: string }[]
}

export const DIA = 86_400_000
export const DIAS_POR_VENCER = 7

export const etapaDe = (ig: IglesiaFila) => ig.etapa ?? (ig.activa ? 'activa' : 'suspendida')

/** Días enteros hasta el fin de la prueba; negativo si ya venció; null si no hay fecha */
export function diasDePrueba(ig: IglesiaFila, ahora = Date.now()): number | null {
  if (!ig.prueba_hasta) return null
  return Math.ceil((new Date(ig.prueba_hasta).getTime() - ahora) / DIA)
}

export const pruebaPorVencer = (ig: IglesiaFila, ahora = Date.now()) => {
  const d = diasDePrueba(ig, ahora)
  return etapaDe(ig) === 'prueba' && !ig.es_demo && d !== null && d >= 0 && d <= DIAS_POR_VENCER
}
export const pruebaVencida = (ig: IglesiaFila, ahora = Date.now()) => {
  const d = diasDePrueba(ig, ahora)
  return etapaDe(ig) === 'prueba' && !ig.es_demo && d !== null && d < 0
}
/** Está en baja: tiene una purga (borrado suave) o un borrado programado. Suspendidas, en receso y en baja no se solapan. */
export const enBaja = (ig: IglesiaFila) => !!ig.borrado_programado_en

/** Días enteros hasta la purga; negativo si el plazo ya venció; null si no está en baja */
export function diasParaPurga(ig: IglesiaFila, ahora = Date.now()): number | null {
  if (!ig.borrado_programado_en) return null
  return Math.ceil((new Date(ig.borrado_programado_en).getTime() - ahora) / DIA)
}

/** En qué situación de vida está la iglesia, con la que se elige el texto que se la explica a quien opera la plataforma */
export type Situacion = 'onboarding' | 'prueba' | 'activa' | 'receso' | 'suspendida' | 'baja_suave' | 'baja_programada' | 'baja_vencida'
export function situacionDe(ig: IglesiaFila, ahora = Date.now()): Situacion {
  if (ig.borrado_programado_en) return borradoVencido(ig, ahora) ? 'baja_vencida' : ig.adn_borrada_en ? 'baja_suave' : 'baja_programada'
  const e = etapaDe(ig)
  return (['onboarding', 'prueba', 'activa', 'receso', 'suspendida'].includes(e) ? e : 'activa') as Situacion
}

export const borradoVencido = (ig: IglesiaFila, ahora = Date.now()) =>
  !!ig.borrado_programado_en && new Date(ig.borrado_programado_en).getTime() <= ahora

/** Módulos que no son del núcleo, con su estado en la iglesia: incluidos por el plan o contratados aparte */
export function modulosDe(ig: IglesiaFila, c: Catalogo): (ModuloInquilino & { delPlan: boolean })[] {
  return c.modulos.filter(m => m.tipo !== 'nucleo').map(m => {
    const delPlan = c.planModulos.some(pm => pm.plan === ig.plan && pm.modulo === m.clave)
    const extra = (ig.addons ?? []).some(a => a.modulo === m.clave && a.activo)
    return { clave: m.clave, nombre: m.nombre, activo: delPlan || extra, delPlan }
  })
}

export function detalleDeEstado(ig: IglesiaFila, t: Traductor, formatoFecha: (iso: string) => string, ahora = Date.now()): { texto?: string; urgente?: boolean } {
  if (ig.borrado_programado_en) {
    if (borradoVencido(ig, ahora)) return { texto: t('plataformaPanel.estado.borradoVencido'), urgente: true }
    const n = diasParaPurga(ig, ahora) ?? 0
    return { texto: t(ig.adn_borrada_en ? 'plataformaPanel.estado.baja' : 'plataformaPanel.estado.bajaProgramada', { fecha: formatoFecha(ig.borrado_programado_en), n }, n), urgente: n <= 3 }
  }
  if (etapaDe(ig) === 'prueba') {
    const d = diasDePrueba(ig, ahora)
    if (d === null) return {}
    if (d < 0) return { texto: t('plataformaPanel.estado.pruebaVencida'), urgente: true }
    if (d === 0) return { texto: t('plataformaPanel.estado.venceHoy'), urgente: true }
    return { texto: t('plataformaPanel.estado.diasRestantes', { n: d }, d), urgente: d <= DIAS_POR_VENCER }
  }
  return {}
}

export function aInquilino(ig: IglesiaFila, c: Catalogo, t: Traductor, formatoFecha: (iso: string) => string, ahora = Date.now()): Inquilino {
  const plan = c.planes.find(p => p.clave === ig.plan)
  const detalle = detalleDeEstado(ig, t, formatoFecha, ahora)
  return {
    id: ig.id,
    nombre: ig.nombre,
    subtitulo: [ig.slug, ig.ciudad].filter(Boolean).join(' · '),
    plan: plan ? { clave: plan.clave, nombre: plan.nombre } : (ig.plan ? { clave: ig.plan, nombre: ig.plan } : null),
    estado: etapaDe(ig),
    estadoEtiqueta: t('plataforma.etapa.' + etapaDe(ig)),
    detalleEstado: detalle.texto,
    detalleUrgente: detalle.urgente,
    demo: !!ig.es_demo,
    enBaja: enBaja(ig),
    diasParaPurga: diasParaPurga(ig, ahora),
    miembros: Number(ig.miembros) || 0,
    modulos: modulosDe(ig, c).map(({ clave, nombre, activo }) => ({ clave, nombre, activo })),
  }
}

export interface PurgaResumen { atrasada: boolean; en_borrado: number; vencidas: number; horas_mas_atrasada: number }

export interface Alerta { clave: string; texto: string; ruta: string }

/** Alertas críticas globales: solo cifras y estados, sin nombres de personas */
export function alertasGlobales(lista: IglesiaFila[], purga: PurgaResumen | null, t: Traductor, ahora = Date.now()): Alerta[] {
  const salida: Alerta[] = []
  if (purga?.atrasada) salida.push({ clave: 'purga', texto: t('plataformaPanel.alerta.purga', { horas: purga.horas_mas_atrasada }), ruta: '/plataforma/sistema' })
  const vencidas = lista.filter(i => pruebaVencida(i, ahora)).length
  if (vencidas) salida.push({ clave: 'pruebasVencidas', texto: t('plataformaPanel.alerta.pruebasVencidas', { n: vencidas }, vencidas), ruta: '/plataforma/pruebas' })
  const borrados = lista.filter(i => borradoVencido(i, ahora) && !i.adn_borrada_en).length
  if (borrados) salida.push({ clave: 'borradoVencido', texto: t('plataformaPanel.alerta.borradoVencido', { n: borrados }, borrados), ruta: '/plataforma/iglesias' })
  return salida
}

export interface Resumen {
  activas: number; prueba: number; porVencer: number; vencidas: number; miembros: number
  /** Ciclo de vida: no se solapan. Una iglesia en baja (con purga o borrado programado) cuenta solo como «en baja» */
  suspendidas: number; receso: number; baja: number
  /** Días hasta la purga más cercana de las iglesias en baja; negativo si ya venció; null si no hay ninguna */
  proximaPurgaDias: number | null
  altasMes: number; altasMesAnterior: number
  /** Demostraciones: las que hay en total (se cuentan aparte, estén o no dentro de las cifras) y cuántas de ellas entran en ellas */
  demos: number; demosDentro: number
}

/** UNA regla para todas las cifras del panel: con «incluir demostraciones» entran todas las iglesias; sin él, solo las reales.
 *  Portada, filtros, listado y contadores del menú salen de la lista que devuelve esta función. */
export function vistaDe(todas: IglesiaFila[], incluirDemo: boolean): IglesiaFila[] {
  return incluirDemo ? todas : todas.filter(i => !i.es_demo)
}

/** En pruebas las demostraciones entran por defecto; en producción, no */
export const incluirDemoPorDefecto = (entorno: string) => entorno !== 'produccion'

/** Cifras de la lista que se ve (ya filtrada con vistaDe). `totalDemos` son las demostraciones de toda la lista, para contarlas aparte. */
export function resumir(visibles: IglesiaFila[], ahora = Date.now(), totalDemos?: number): Resumen {
  const e = (i: IglesiaFila) => etapaDe(i)
  const altas = (desde: number, hasta: number) => visibles.filter(i => { const f = new Date(i.created_at).getTime(); return f > desde && f <= hasta }).length
  const dentro = visibles.filter(i => i.es_demo).length
  return {
    activas: visibles.filter(i => e(i) === 'activa' && i.activa).length,
    prueba: visibles.filter(i => e(i) === 'prueba').length,
    porVencer: visibles.filter(i => pruebaPorVencer(i, ahora)).length,
    vencidas: visibles.filter(i => pruebaVencida(i, ahora)).length,
    suspendidas: visibles.filter(i => etapaDe(i) === 'suspendida' && !enBaja(i)).length,
    receso: visibles.filter(i => etapaDe(i) === 'receso' && !enBaja(i)).length,
    baja: visibles.filter(enBaja).length,
    proximaPurgaDias: visibles.filter(enBaja).reduce<number | null>((m, i) => { const d = diasParaPurga(i, ahora)!; return m === null || d < m ? d : m }, null),
    miembros: visibles.reduce((n, i) => n + (Number(i.miembros) || 0), 0),
    altasMes: altas(ahora - 30 * DIA, ahora),
    altasMesAnterior: altas(ahora - 60 * DIA, ahora - 30 * DIA),
    demos: totalDemos ?? dentro,
    demosDentro: dentro,
  }
}

export function kpisDe(r: Resumen, alertas: Alerta[], t: Traductor, formatoNumero: (n: number) => string): Kpi[] {
  const delta = r.altasMes - r.altasMesAnterior
  return [
    { clave: 'activas', etiqueta: t('plataformaPanel.kpi.activas'), valor: formatoNumero(r.activas),
      nota: t('plataformaPanel.kpi.activasNota', { n: r.altasMes, delta: (delta > 0 ? '+' : '') + delta }, r.altasMes), tono: delta >= 0 ? 'bien' : 'normal' },
    { clave: 'prueba', etiqueta: t('plataformaPanel.kpi.prueba'), valor: formatoNumero(r.prueba),
      nota: t('plataformaPanel.kpi.pruebaNota', { n: r.porVencer }, r.porVencer), tono: r.porVencer ? 'alerta' : 'normal' },
    { clave: 'suspendidas', etiqueta: t('plataformaPanel.kpi.suspendidas'), valor: formatoNumero(r.suspendidas), nota: t('plataformaPanel.kpi.suspendidasNota') },
    { clave: 'receso', etiqueta: t('plataformaPanel.kpi.receso'), valor: formatoNumero(r.receso), nota: t('plataformaPanel.kpi.recesoNota') },
    { clave: 'baja', etiqueta: t('plataformaPanel.kpi.baja'), valor: formatoNumero(r.baja),
      nota: r.proximaPurgaDias === null ? t('plataformaPanel.kpi.bajaNinguna')
        : r.proximaPurgaDias < 0 ? t('plataformaPanel.kpi.bajaVencida') : t('plataformaPanel.kpi.bajaProxima', { n: r.proximaPurgaDias }, r.proximaPurgaDias),
      tono: r.proximaPurgaDias !== null && r.proximaPurgaDias <= 3 ? 'alerta' : 'normal' },
    { clave: 'demos', etiqueta: t('plataformaPanel.kpi.demos'), valor: formatoNumero(r.demos),
      nota: t(r.demosDentro > 0 || r.demos === 0 ? 'plataformaPanel.kpi.demosDentro' : 'plataformaPanel.kpi.demosFuera') },
    { clave: 'miembros', etiqueta: t('plataformaPanel.kpi.miembros'), valor: formatoNumero(r.miembros), nota: t('plataformaPanel.kpi.miembrosNota') },
    { clave: 'facturacion', etiqueta: t('plataformaPanel.kpi.facturacion'), valor: null, sinConectar: t('plataformaPanel.faltaFacturacion') },
    { clave: 'alertas', etiqueta: t('plataformaPanel.kpi.alertas'), valor: formatoNumero(alertas.length),
      nota: alertas.length ? t('plataformaPanel.kpi.alertasHay') : t('plataformaPanel.kpi.alertasNinguna'), tono: alertas.length ? 'alerta' : 'bien' },
  ]
}

export interface EventoCrudo { tipo: 'alta' | 'accion'; accion: string; iglesia_id: string | null; iglesia: string | null; fecha: string }
export interface EnvioEstado { activo: boolean; hoy: number; tope_global: number; contadores: boolean }

/** Eventos de la actividad global: acción, iglesia y fecha. Ni el detalle de la auditoría ni datos de personas */
export function eventosParaPanel(eventos: EventoCrudo[], t: Traductor, existe: (clave: string) => boolean): EventoActividad[] {
  return eventos.map((e, i) => ({
    id: `${e.fecha}-${e.accion}-${e.iglesia_id ?? 'x'}-${i}`,
    fecha: e.fecha,
    texto: e.tipo === 'alta'
      ? t('plataformaPanel.actividad.alta', { iglesia: e.iglesia ?? '' })
      : e.iglesia
        ? t('plataformaPanel.actividad.evento', { accion: textoDeAccion(e.accion, t, existe), iglesia: e.iglesia })
        : t('plataformaPanel.actividad.sinIglesia', { accion: textoDeAccion(e.accion, t, existe) }),
  }))
}

/** Salud del sistema con lo que de verdad se conoce: la purga y el envío. La disponibilidad por servicio no tiene fuente: «sin conectar» */
export function saludDe(purga: PurgaResumen | null, envio: EnvioEstado | null, t: Traductor): EstadoServicio[] {
  const filas: EstadoServicio[] = []
  filas.push(purga
    ? { clave: 'purga', etiqueta: t('plataformaPanel.salud.purga'), situacion: purga.atrasada ? 'alerta' : 'ok',
        detalle: purga.atrasada ? t('plataformaPanel.salud.purgaAtraso', { horas: purga.horas_mas_atrasada }) : t('plataformaPanel.salud.purgaOk') }
    : { clave: 'purga', etiqueta: t('plataformaPanel.salud.purga'), situacion: 'sin_conectar', detalle: t('plataformaPanel.salud.noDisponible') })
  filas.push(envio
    ? { clave: 'envio', etiqueta: t('plataformaPanel.salud.envio'), situacion: envio.activo ? 'ok' : 'apagado',
        detalle: envio.activo ? t('plataformaPanel.sistema.envioHoy', { n: envio.hoy }) : t('plataformaPanel.salud.envioApagado'),
        ...(envio.activo && envio.tope_global > 0 ? { porcentaje: Math.min(100, Math.round((envio.hoy / envio.tope_global) * 100)) } : {}) }
    : { clave: 'envio', etiqueta: t('plataformaPanel.salud.envio'), situacion: 'sin_conectar', detalle: t('plataformaPanel.salud.noDisponible') })
  filas.push({ clave: 'disponibilidad', etiqueta: t('plataformaPanel.salud.disponibilidad'), situacion: 'sin_conectar', detalle: t('plataformaPanel.salud.faltaDisponibilidad') })
  return filas
}
