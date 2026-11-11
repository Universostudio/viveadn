// Modelo común de un informe. Los generadores de PDF y de Excel lo reciben y nada más: son funciones puras.
export type Valor = string | number | boolean | null

export interface Columna {
  titulo: string
  /** fecha: texto AAAA-MM-DD o ISO, en Excel sale como fecha real; porcentaje: número de 0 a 1 */
  tipo?: 'texto' | 'entero' | 'decimal' | 'fecha' | 'porcentaje'
  /** Anchura relativa, en caracteres aproximados */
  ancho?: number
}

export type Seccion =
  | { tipo: 'pares'; titulo?: string; pares: [string, Valor][] }
  | { tipo: 'tabla'; titulo?: string; columnas: Columna[]; filas: Valor[][]; hoja?: string }
  | { tipo: 'barras'; titulo: string; etiquetas: string[]; valores: number[] }

export interface Informe {
  titulo: string
  subtitulo: string
  /** Texto del pie de cada página del PDF */
  pie: string
  /** Fecha de generación, para las propiedades del archivo */
  generado: Date
  secciones: Seccion[]
  apaisado?: boolean
  /** Nombre de la hoja de resumen en Excel */
  hojaResumen?: string
  /** Texto de "Página X de Y" con {n} y {total} */
  textoPagina?: string
  /** Idioma de los números (es, en, fr, pt-BR) */
  locale?: string
}
