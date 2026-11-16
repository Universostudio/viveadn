// Panel de inicio honesto: qué tarjetas ve cada rol (y si cuentan todo o solo lo suyo) y cómo se muestra un dato que no cargó.
// Pura y probada en Node (scripts/probar-panel-inicio.mts). La base ya limita los datos por rol; esto evita enseñar un 0 que en realidad es «no pude leerlo» o «no te toca verlo».

/** 'todo': ve el total de la iglesia. 'acotado': ve solo lo que tiene a su cargo (su casa, su zona, sus asignados). null: no ve la tarjeta. */
export type Alcance = 'todo' | 'acotado' | null

const alcanceDe = (can: (...c: string[]) => boolean, amplio: string[], acotado: string[]): Alcance =>
  can(...amplio) ? 'todo' : can(...acotado) ? 'acotado' : null

export interface TarjetasInicio {
  personas: Alcance
  casas: Alcance
  seguimiento: Alcance
  nuevaPersona: boolean
}

export function tarjetasDeInicio(can: (...claves: string[]) => boolean): TarjetasInicio {
  return {
    personas: alcanceDe(can, ['miembros.ver'], ['miembros.ver_asignados', 'miembros.ver_zona', 'miembros.ver_propios']),
    casas: alcanceDe(can, ['casas.ver'], ['casas.ver_propia', 'casas.ver_zona']),
    seguimiento: alcanceDe(can, ['consolidacion.ver'], ['consolidacion.ver_asignados', 'consolidacion.ver_casa', 'consolidacion.ver_zona', 'consolidacion.ver_propios']),
    nuevaPersona: can('miembros.crear'),
  }
}

/** Un número leído de la base: valor null y fallo true si la consulta falló (no se muestra como 0) */
export interface Medida { valor: number | null; fallo: boolean }

export function medida(res: { count?: number | null; error?: unknown } | null | undefined): Medida {
  if (!res || res.error || typeof res.count !== 'number') return { valor: null, fallo: true }
  return { valor: res.count, fallo: false }
}

/** Texto de una medida: el número, o un guion largo si no se pudo leer */
export const textoMedida = (m: Medida): string => (m.valor === null ? '—' : String(m.valor))

/** ¿Hay más filas de las mostradas? Sin dato del total no se afirma nada */
export const hayMas = (mostradas: number, total: number | null): boolean => total !== null && total > mostradas
