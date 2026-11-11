// Estructura de los textos legales. Cada idioma tiene un archivo con los cuatro documentos y la misma forma:
// scripts/verificar-legal.mts comprueba que los cuatro idiomas tienen las mismas secciones, el mismo número de
// párrafos y listas y los mismos marcadores, y que ningún texto cambia sin una versión nueva.

/** Datos de configuración que se sustituyen en el texto. Nunca se inventan: si falta uno, se ve un aviso. */
export type ClaveConfig = 'titular' | 'nif' | 'domicilio' | 'emailLegal' | 'emailSoporte' | 'registro' | 'regionDatos'

/** Un párrafo puede mostrarse solo si hay un dato configurado (por ejemplo, los datos del Registro Mercantil) */
export type Parrafo = string | { texto: string; si: ClaveConfig }

export interface Seccion {
  /** Estable entre idiomas: sirve de ancla y de comparación */
  id: string
  titulo: string
  parrafos: Parrafo[]
  /** Lista que se muestra después de los párrafos */
  lista?: string[]
  /** Párrafos que se muestran después de la lista */
  cierre?: Parrafo[]
}

export interface Documento {
  titulo: string
  /** Una frase que resume de qué trata */
  resumen: string
  secciones: Seccion[]
}

export type ClaveDocumento = 'privacidad' | 'terminos' | 'aviso' | 'cookies'
export type TextosLegales = Record<ClaveDocumento, Documento>

/** Rutas públicas de cada documento */
export const RUTAS_LEGALES: Record<ClaveDocumento, string> = {
  privacidad: '/privacidad',
  terminos: '/terminos',
  aviso: '/aviso-legal',
  cookies: '/cookies',
}
export const CLAVES_LEGALES = Object.keys(RUTAS_LEGALES) as ClaveDocumento[]
