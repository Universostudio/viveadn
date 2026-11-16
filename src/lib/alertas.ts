import type { AlertaColor } from '@/lib/supabase'

// Los números de un método de seguimiento: plazo total y desde cuántas horas empieza cada color (verde hasta el amarillo, amarillo hasta el naranja,
// naranja hasta el plazo, rojo después). OP72 es la plantilla de siempre y el valor por defecto: así todo lo que no trae método se comporta como antes.
export interface MetodoSeguimiento { plazo_horas: number; umbral_amarillo_horas: number; umbral_naranja_horas: number }
export const METODO_OP72: MetodoSeguimiento = { plazo_horas: 72, umbral_amarillo_horas: 24, umbral_naranja_horas: 48 }
/** Para pedirlo junto a cada proceso: la fila trae su método en `metodo` (solo si la base ya tiene los métodos; ver el almacén de seguimiento) */
export const SELECT_METODO = 'metodo:adn_seguimiento_metodos(plazo_horas, umbral_amarillo_horas, umbral_naranja_horas)'

// El color de una consolidacion depende de las horas desde la conversion, asi que se calcula al leer.
// La columna estado_alerta de la base solo se actualiza al escribir y envejece sola: no se usa para mostrar ni para filtrar.
export function alertaDe(conversion: string | Date, completado: boolean | null | undefined, ahora = Date.now(), metodo: MetodoSeguimiento = METODO_OP72): AlertaColor {
  if (completado) return 'verde'
  const horas = (ahora - new Date(conversion).getTime()) / 3_600_000
  if (horas <= metodo.umbral_amarillo_horas) return 'verde'
  if (horas <= metodo.umbral_naranja_horas) return 'amarillo'
  if (horas <= metodo.plazo_horas) return 'naranja'
  return 'rojo'
}

// Fecha limite ISO de hace N horas: lo que lleva mas tiempo convertido queda por debajo de ella
export const haceHoras = (horas: number, ahora = Date.now()) => new Date(ahora - horas * 3_600_000).toISOString()

type ConMetodo = { metodo?: MetodoSeguimiento | null }
export const metodoDe = (fila: ConMetodo): MetodoSeguimiento => fila.metodo ?? METODO_OP72
/** Plazo en horas del proceso: el de su método, o 72 si la fila no trae método */
export const plazoDe = (fila: ConMetodo): number => metodoDe(fila).plazo_horas

export const conAlerta = <T extends { fecha_conversion: string; completado?: boolean | null } & ConMetodo>(fila: T): T & { estado_alerta: AlertaColor } =>
  ({ ...fila, estado_alerta: alertaDe(fila.fecha_conversion, fila.completado, Date.now(), metodoDe(fila)) })
