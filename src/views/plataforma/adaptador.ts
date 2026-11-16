// Adaptador de Vive ADN: traduce lo que devuelve la función «plataforma» a los tipos genéricos de src/panel-maestro.
// Es puro (sin Vue ni red) para poder probarlo en Node. Solo maneja conteos, estados y nombres de iglesias: nunca datos de personas.
import type { Inquilino, Kpi, ModuloInquilino } from '../../panel-maestro/tipos.ts'

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
    return { texto: t(ig.adn_borrada_en ? 'plataforma.borradaSuave' : 'plataforma.borradoProgramado', { fecha: formatoFecha(ig.borrado_programado_en) }) }
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
  activas: number; prueba: number; porVencer: number; vencidas: number; suspendidas: number; demos: number; miembros: number
  altasMes: number; altasMesAnterior: number
}

export function resumir(lista: IglesiaFila[], ahora = Date.now()): Resumen {
  const reales = lista.filter(i => !i.es_demo)
  const e = (i: IglesiaFila) => etapaDe(i)
  const altas = (desde: number, hasta: number) => reales.filter(i => { const f = new Date(i.created_at).getTime(); return f > desde && f <= hasta }).length
  return {
    activas: reales.filter(i => e(i) === 'activa' && i.activa).length,
    prueba: reales.filter(i => e(i) === 'prueba').length,
    porVencer: reales.filter(i => pruebaPorVencer(i, ahora)).length,
    vencidas: reales.filter(i => pruebaVencida(i, ahora)).length,
    suspendidas: reales.filter(i => !i.activa).length,
    demos: lista.length - reales.length,
    miembros: reales.reduce((n, i) => n + (Number(i.miembros) || 0), 0),
    altasMes: altas(ahora - 30 * DIA, ahora),
    altasMesAnterior: altas(ahora - 60 * DIA, ahora - 30 * DIA),
  }
}

export function kpisDe(r: Resumen, alertas: Alerta[], t: Traductor, formatoNumero: (n: number) => string): Kpi[] {
  const delta = r.altasMes - r.altasMesAnterior
  return [
    { clave: 'activas', etiqueta: t('plataformaPanel.kpi.activas'), valor: formatoNumero(r.activas),
      nota: t('plataformaPanel.kpi.activasNota', { n: r.altasMes, delta: (delta > 0 ? '+' : '') + delta }, r.altasMes), tono: delta >= 0 ? 'bien' : 'normal' },
    { clave: 'prueba', etiqueta: t('plataformaPanel.kpi.prueba'), valor: formatoNumero(r.prueba),
      nota: t('plataformaPanel.kpi.pruebaNota', { n: r.porVencer }, r.porVencer), tono: r.porVencer ? 'alerta' : 'normal' },
    { clave: 'suspendidas', etiqueta: t('plataformaPanel.kpi.suspendidas'), valor: formatoNumero(r.suspendidas) },
    { clave: 'demos', etiqueta: t('plataformaPanel.kpi.demos'), valor: formatoNumero(r.demos) },
    { clave: 'miembros', etiqueta: t('plataformaPanel.kpi.miembros'), valor: formatoNumero(r.miembros), nota: t('plataformaPanel.kpi.miembrosNota') },
    { clave: 'facturacion', etiqueta: t('plataformaPanel.kpi.facturacion'), valor: null, sinConectar: t('plataformaPanel.faltaFacturacion') },
    { clave: 'alertas', etiqueta: t('plataformaPanel.kpi.alertas'), valor: formatoNumero(alertas.length),
      nota: alertas.length ? t('plataformaPanel.kpi.alertasHay') : t('plataformaPanel.kpi.alertasNinguna'), tono: alertas.length ? 'alerta' : 'bien' },
  ]
}
