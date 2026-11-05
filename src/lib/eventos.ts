// Tipos de evento y cálculo de series semanales. Funciones puras, sin red.
export const TIPOS_EVENTO = ['culto', 'casa_oracion', 'formacion', 'especial', 'otro'] as const
export type TipoEvento = typeof TIPOS_EVENTO[number]
export const MAX_SERIE = 52
// Sin hora de fin, un evento se considera en curso durante 3 horas desde que empieza
export const DURACION_POR_DEFECTO_MS = 3 * 3600_000

// Fechas de una serie semanal. Se suma por día natural y no por 7 x 24 horas, para que la hora
// local no cambie al pasar por un cambio de horario (verano e invierno).
export function fechasDeSerie(inicio: Date, fin: Date | null, veces: number): { inicio: Date; fin: Date | null }[] {
  const salida: { inicio: Date; fin: Date | null }[] = []
  for (let i = 0; i < veces; i++) {
    const a = new Date(inicio)
    a.setDate(a.getDate() + 7 * i)
    let b: Date | null = null
    if (fin) {
      b = new Date(fin)
      b.setDate(b.getDate() + 7 * i)
    }
    salida.push({ inicio: a, fin: b })
  }
  return salida
}
