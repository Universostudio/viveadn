// Tipos de enlace para dar; el orden es el de los botones. La etiqueta visible está en src/i18n (dar.<tipo>)
export const TIPOS_DAR = ['diezmo', 'ofrenda', 'donacion'] as const
export type TipoDar = typeof TIPOS_DAR[number]

export interface EnlaceDar {
  tipo: TipoDar
  url: string
  activo: boolean
}

// Solo se aceptan direcciones https sin espacios, igual que la restricción de la base
export function urlDarValida(url: string): boolean {
  if (url.length > 500 || /\s/.test(url)) return false
  try {
    return new URL(url).protocol === 'https:'
  } catch {
    return false
  }
}
