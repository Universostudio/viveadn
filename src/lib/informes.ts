// Construcción de los tres informes (miembros, asistencia y crecimiento) a partir de los datos de la base.
// Funciones puras: reciben un traductor y devuelven el modelo común que convierten en PDF y en Excel.
import type { Columna, Informe, Seccion } from './informeTipos.ts'

export type Traductor = (clave: string, params?: Record<string, unknown>) => string
export interface Contexto { t: Traductor; locale: string; iglesia: string; ahora: Date }

export interface ResumenMiembros {
  total: number; activos: number; inactivos: number; bautizados: number; con_correo: number; con_telefono: number; sin_casa: number
  por_nivel: Record<string, number>
}
export interface FilaMiembro {
  crm_id: string; nombre: string; apellido: string; email: string | null; telefono: string | null; fecha_nacimiento: string | null
  genero: string | null; casa: string | null; nivel_compromiso: string | null; bautizado: boolean; fecha_conversion: string | null
  activo: boolean; registrado: string | null
}
export interface DatosAsistencia {
  desde: string; hasta: string
  casas: { registros: number; presentes: number; semanal: { semana: string; registros: number; presentes: number }[]; por_casa: { casa: string; registros: number; presentes: number; personas: number }[] }
  eventos: { registros: number; presentes: number; lista: { titulo: string; tipo: string | null; inicia_en: string; registros: number; presentes: number }[] }
}
export interface FilaCrecimiento {
  mes: string; nuevos_miembros: number; miembros_acumulados: number; conversiones: number; bautizos: number
  consolidaciones_iniciadas: number; consolidaciones_completadas: number
}

const NIVELES = ['nuevo', 'en_crecimiento', 'maduro', 'lider', 'multiplicador']

const fechaLarga = (d: Date, locale: string) => new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }).format(d)
const fechaCorta = (iso: string, locale: string) => new Intl.DateTimeFormat(locale, { day: '2-digit', month: 'short', timeZone: 'UTC' }).format(new Date(`${iso.slice(0, 10)}T00:00:00Z`))
const mesCorto = (iso: string, locale: string) => new Intl.DateTimeFormat(locale, { month: 'short', year: '2-digit', timeZone: 'UTC' }).format(new Date(`${iso.slice(0, 10)}T00:00:00Z`))
const razon = (parte: number, total: number): number | null => (total > 0 ? parte / total : null)
const pct = (parte: number, total: number, locale: string) => (total > 0 ? new Intl.NumberFormat(locale, { style: 'percent', maximumFractionDigits: 1 }).format(parte / total) : '—')

function base(c: Contexto, claveTitulo: string, detalle: string): Pick<Informe, 'titulo' | 'subtitulo' | 'pie' | 'generado' | 'textoPagina' | 'locale'> {
  const titulo = c.t(claveTitulo)
  return {
    titulo,
    subtitulo: [c.iglesia, detalle, c.t('informes.generadoEl', { fecha: fechaLarga(c.ahora, c.locale) })].filter(Boolean).join(' · '),
    pie: c.t('informes.pie', { informe: titulo }),
    generado: c.ahora,
    textoPagina: c.t('informes.pagina', { n: '{n}', total: '{total}' }),
    locale: c.locale,
  }
}

export function informeMiembros(resumen: ResumenMiembros, filas: FilaMiembro[], c: Contexto): Informe {
  const t = c.t
  const si = t('informes.si'), no = t('informes.no')
  const niveles = [...NIVELES.filter(n => n in resumen.por_nivel), ...Object.keys(resumen.por_nivel).filter(n => !NIVELES.includes(n))]
  const secciones: Seccion[] = [
    { tipo: 'pares', titulo: t('informes.miembros.resumen'), pares: [
      [t('informes.miembros.total'), resumen.total], [t('informes.miembros.activos'), resumen.activos], [t('informes.miembros.inactivos'), resumen.inactivos],
      [t('informes.miembros.bautizados'), resumen.bautizados], [t('informes.miembros.conCorreo'), resumen.con_correo],
      [t('informes.miembros.conTelefono'), resumen.con_telefono], [t('informes.miembros.sinCasa'), resumen.sin_casa],
    ] },
    { tipo: 'pares', titulo: t('informes.miembros.porNivel'), pares: niveles.map(n => [t(`compromiso.${n}`), resumen.por_nivel[n] ?? 0] as [string, number]) },
    { tipo: 'tabla', titulo: t('informes.miembros.lista'), hoja: t('informes.miembros.hoja'),
      columnas: [
        { titulo: t('informes.miembros.col.codigo'), ancho: 12 }, { titulo: t('informes.miembros.col.nombre'), ancho: 18 }, { titulo: t('informes.miembros.col.apellido'), ancho: 18 },
        { titulo: t('informes.miembros.col.correo'), ancho: 26 }, { titulo: t('informes.miembros.col.telefono'), ancho: 16 }, { titulo: t('informes.miembros.col.nacimiento'), tipo: 'fecha', ancho: 13 },
        { titulo: t('informes.miembros.col.casa'), ancho: 19 }, { titulo: t('informes.miembros.col.nivel'), ancho: 12 }, { titulo: t('informes.miembros.col.bautizado'), ancho: 11 },
        { titulo: t('informes.miembros.col.conversion'), tipo: 'fecha', ancho: 13 }, { titulo: t('informes.miembros.col.activo'), ancho: 8 }, { titulo: t('informes.miembros.col.registrado'), tipo: 'fecha', ancho: 13 },
      ] satisfies Columna[],
      filas: filas.map(f => [
        f.crm_id, f.nombre, f.apellido, f.email, f.telefono, f.fecha_nacimiento, f.casa, f.nivel_compromiso ? t(`compromiso.${f.nivel_compromiso}`) : null,
        f.bautizado ? si : no, f.fecha_conversion, f.activo ? si : no, f.registrado,
      ]) },
  ]
  return { ...base(c, 'informes.miembros.titulo', ''), secciones, apaisado: true, hojaResumen: t('informes.hojaResumen') }
}

export function informeAsistencia(d: DatosAsistencia, c: Contexto): Informe {
  const t = c.t
  const periodo = t('informes.asistencia.periodo', { desde: fechaCorta(d.desde, c.locale), hasta: fechaCorta(d.hasta, c.locale) })
  const secciones: Seccion[] = [
    { tipo: 'pares', titulo: t('informes.asistencia.resumen'), pares: [
      [t('informes.asistencia.casasRegistros'), d.casas.registros], [t('informes.asistencia.casasPresentes'), d.casas.presentes], [t('informes.asistencia.casasPorcentaje'), pct(d.casas.presentes, d.casas.registros, c.locale)],
      [t('informes.asistencia.eventosRegistros'), d.eventos.registros], [t('informes.asistencia.eventosPresentes'), d.eventos.presentes], [t('informes.asistencia.eventosPorcentaje'), pct(d.eventos.presentes, d.eventos.registros, c.locale)],
    ] },
  ]
  if (d.casas.semanal.length) secciones.push({ tipo: 'barras', titulo: t('informes.asistencia.graficoSemanal'), etiquetas: d.casas.semanal.map(s => fechaCorta(s.semana, c.locale)), valores: d.casas.semanal.map(s => s.presentes) })
  secciones.push(
    { tipo: 'tabla', titulo: t('informes.asistencia.porSemana'), hoja: t('informes.asistencia.hojaSemanal'), columnas: [
      { titulo: t('informes.asistencia.col.semana'), tipo: 'fecha', ancho: 14 }, { titulo: t('informes.asistencia.col.registros'), tipo: 'entero', ancho: 16 },
      { titulo: t('informes.asistencia.col.presentes'), tipo: 'entero', ancho: 12 }, { titulo: t('informes.asistencia.col.porcentaje'), tipo: 'porcentaje', ancho: 12 } ],
      filas: d.casas.semanal.map(s => [s.semana, s.registros, s.presentes, razon(s.presentes, s.registros)]) },
    { tipo: 'tabla', titulo: t('informes.asistencia.porCasa'), hoja: t('informes.asistencia.hojaCasas'), columnas: [
      { titulo: t('informes.asistencia.col.casa'), ancho: 28 }, { titulo: t('informes.asistencia.col.registros'), tipo: 'entero', ancho: 16 }, { titulo: t('informes.asistencia.col.presentes'), tipo: 'entero', ancho: 12 },
      { titulo: t('informes.asistencia.col.personas'), tipo: 'entero', ancho: 20 }, { titulo: t('informes.asistencia.col.porcentaje'), tipo: 'porcentaje', ancho: 12 } ],
      filas: d.casas.por_casa.map(h => [h.casa, h.registros, h.presentes, h.personas, razon(h.presentes, h.registros)]) },
    { tipo: 'tabla', titulo: t('informes.asistencia.porEvento'), hoja: t('informes.asistencia.hojaEventos'), columnas: [
      { titulo: t('informes.asistencia.col.fecha'), tipo: 'fecha', ancho: 12 }, { titulo: t('informes.asistencia.col.evento'), ancho: 28 }, { titulo: t('informes.asistencia.col.tipo'), ancho: 14 },
      { titulo: t('informes.asistencia.col.registros'), tipo: 'entero', ancho: 16 }, { titulo: t('informes.asistencia.col.presentes'), tipo: 'entero', ancho: 12 }, { titulo: t('informes.asistencia.col.porcentaje'), tipo: 'porcentaje', ancho: 12 } ],
      filas: d.eventos.lista.map(e => [e.inicia_en, e.titulo, e.tipo ? t(`eventos.tipo.${e.tipo}`) : null, e.registros, e.presentes, razon(e.presentes, e.registros)]) },
  )
  return { ...base(c, 'informes.asistencia.titulo', periodo), secciones, hojaResumen: t('informes.hojaResumen') }
}

export function informeCrecimiento(filas: FilaCrecimiento[], c: Contexto): Informe {
  const t = c.t
  const suma = (k: keyof Omit<FilaCrecimiento, 'mes'>) => filas.reduce((a, f) => a + f[k], 0)
  const nuevos = suma('nuevos_miembros')
  const registrados = filas.length ? filas[filas.length - 1]!.miembros_acumulados : 0
  const periodo = t('informes.crecimiento.periodo', { n: filas.length })
  const secciones: Seccion[] = [
    { tipo: 'pares', titulo: t('informes.crecimiento.resumen'), pares: [
      [t('informes.crecimiento.registrados'), registrados], [t('informes.crecimiento.nuevos'), nuevos],
      [t('informes.crecimiento.promedio'), filas.length ? Math.round((nuevos / filas.length) * 10) / 10 : 0],
      [t('informes.crecimiento.conversiones'), suma('conversiones')], [t('informes.crecimiento.bautizos'), suma('bautizos')],
      [t('informes.crecimiento.iniciadas'), suma('consolidaciones_iniciadas')], [t('informes.crecimiento.completadas'), suma('consolidaciones_completadas')],
    ] },
    { tipo: 'barras', titulo: t('informes.crecimiento.grafico'), etiquetas: filas.map(f => mesCorto(f.mes, c.locale)), valores: filas.map(f => f.nuevos_miembros) },
    { tipo: 'tabla', titulo: t('informes.crecimiento.detalle'), hoja: t('informes.crecimiento.hoja'), columnas: [
      { titulo: t('informes.crecimiento.col.mes'), tipo: 'fecha', ancho: 12 }, { titulo: t('informes.crecimiento.col.nuevos'), tipo: 'entero', ancho: 12 },
      { titulo: t('informes.crecimiento.col.acumulados'), tipo: 'entero', ancho: 14 }, { titulo: t('informes.crecimiento.col.conversiones'), tipo: 'entero', ancho: 14 },
      { titulo: t('informes.crecimiento.col.bautizos'), tipo: 'entero', ancho: 11 }, { titulo: t('informes.crecimiento.col.iniciadas'), tipo: 'entero', ancho: 19 },
      { titulo: t('informes.crecimiento.col.completadas'), tipo: 'entero', ancho: 19 } ],
      filas: filas.map(f => [f.mes, f.nuevos_miembros, f.miembros_acumulados, f.conversiones, f.bautizos, f.consolidaciones_iniciadas, f.consolidaciones_completadas]) },
  ]
  return { ...base(c, 'informes.crecimiento.titulo', periodo), secciones, hojaResumen: t('informes.hojaResumen') }
}
