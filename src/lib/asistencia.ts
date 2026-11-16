// Pasar lista en una casa de oración: qué filas de asistencia hay que crear y cuáles actualizar para una fecha, sin duplicar las que ya existen.
// Pura y probada en Node (scripts/probar-asistencia.mts).

export interface FilaAsistencia { id: string; miembro_id: string; presente: boolean | null }
export interface PlanAsistencia {
  insertar: { casa_oracion_id: string; miembro_id: string; fecha: string; presente: boolean }[]
  actualizar: { id: string; presente: boolean }[]
}

/** miembros: quienes están en la casa; existentes: lo ya guardado para esa fecha; marcados: ids presentes ahora en pantalla */
export function planDeAsistencia(casaId: string, fecha: string, miembros: string[], existentes: FilaAsistencia[], marcados: Set<string>): PlanAsistencia {
  const porMiembro = new Map(existentes.map(e => [e.miembro_id, e]))
  const plan: PlanAsistencia = { insertar: [], actualizar: [] }
  for (const m of miembros) {
    const presente = marcados.has(m)
    const previa = porMiembro.get(m)
    if (!previa) plan.insertar.push({ casa_oracion_id: casaId, miembro_id: m, fecha, presente })
    else if (Boolean(previa.presente) !== presente) plan.actualizar.push({ id: previa.id, presente })
  }
  return plan
}

/** Fecha local de hoy en formato AAAA-MM-DD (la que usa la columna date) */
export function hoyLocal(ahora = new Date()): string {
  const d = new Date(ahora.getTime() - ahora.getTimezoneOffset() * 60000)
  return d.toISOString().slice(0, 10)
}

/** Resumen por fecha de las últimas asistencias: presentes y total registrado */
export function resumenPorFecha(filas: { fecha: string; presente: boolean | null }[]): { fecha: string; presentes: number; total: number }[] {
  const mapa = new Map<string, { presentes: number; total: number }>()
  for (const f of filas) {
    const r = mapa.get(f.fecha) ?? { presentes: 0, total: 0 }
    r.total++; if (f.presente) r.presentes++
    mapa.set(f.fecha, r)
  }
  return [...mapa.entries()].map(([fecha, r]) => ({ fecha, ...r })).sort((a, b) => b.fecha.localeCompare(a.fecha))
}
