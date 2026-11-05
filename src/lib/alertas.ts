import type { AlertaColor } from '@/lib/supabase'

// El color de una consolidacion depende de las horas desde la conversion, asi que se calcula al leer.
// La columna estado_alerta de la base solo se actualiza al escribir y envejece sola: no se usa para mostrar ni para filtrar.
export function alertaDe(conversion: string | Date, completado: boolean | null | undefined, ahora = Date.now()): AlertaColor {
  if (completado) return 'verde'
  const horas = (ahora - new Date(conversion).getTime()) / 3_600_000
  if (horas <= 24) return 'verde'
  if (horas <= 48) return 'amarillo'
  if (horas <= 72) return 'naranja'
  return 'rojo'
}

// Fecha limite ISO de hace N horas: lo que lleva mas tiempo convertido queda por debajo de ella
export const haceHoras = (horas: number, ahora = Date.now()) => new Date(ahora - horas * 3_600_000).toISOString()

export const conAlerta = <T extends { fecha_conversion: string; completado?: boolean | null }>(fila: T): T & { estado_alerta: AlertaColor } =>
  ({ ...fila, estado_alerta: alertaDe(fila.fecha_conversion, fila.completado) })
