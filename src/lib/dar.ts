// Fondos y apariencia de la página de dar. Funciones puras, sin red.

// Los tres tipos originales: si no tienen nombre propio, su etiqueta está en src/i18n (dar.<tipo>)
export const TIPOS_DAR = ['diezmo', 'ofrenda', 'donacion'] as const
export type TipoDar = typeof TIPOS_DAR[number]

export const MAX_FONDOS = 20
export const PLANTILLAS = ['clasica', 'dia'] as const
export type Plantilla = typeof PLANTILLAS[number]
export const MODOS_CALCULADORA = ['dia', 'diezmo', 'ninguna'] as const
export type ModoCalculadora = typeof MODOS_CALCULADORA[number]
export const MONEDAS = ['EUR', 'USD', 'GBP', 'MXN', 'COP', 'ARS', 'CLP', 'PEN', 'BRL', 'CAD'] as const
export const PERIODOS = ['anual', 'mensual', 'semanal', 'personalizado'] as const
export type Periodo = typeof PERIODOS[number]

export interface Fondo {
  tipo: string
  url: string
  nombre: string | null
  descripcion: string | null
  orden: number
}

export interface ConfigDar {
  plantilla: Plantilla
  titulo: string | null
  subtitulo: string | null
  color_primario: string
  color_acento: string
  logo_url: string | null
  calculadora: ModoCalculadora
  moneda: string
}

export const CONFIG_POR_DEFECTO: ConfigDar = {
  plantilla: 'clasica', titulo: null, subtitulo: null, color_primario: '#00523c', color_acento: '#f5a623',
  logo_url: null, calculadora: 'dia', moneda: 'EUR',
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

export const colorValido = (c: string) => /^#[0-9a-fA-F]{6}$/.test(c)

// Color de texto legible (blanco o casi negro) sobre un fondo, según su luminosidad relativa (WCAG)
export function colorTextoSobre(fondo: string): '#ffffff' | '#111827' {
  if (!colorValido(fondo)) return '#ffffff'
  const canal = (i: number) => {
    const v = parseInt(fondo.slice(1 + i * 2, 3 + i * 2), 16) / 255
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
  }
  const luminosidad = 0.2126 * canal(0) + 0.7152 * canal(1) + 0.0722 * canal(2)
  return luminosidad > 0.4 ? '#111827' : '#ffffff'
}

// Clave de un fondo a partir de su nombre: minúsculas, sin acentos, solo letras, números y guion bajo.
// Si ya existe, se añade un número para que sea única.
export function claveFondo(nombre: string, usadas: Iterable<string>): string {
  const base = nombre.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 36) || 'fondo'
  const ocupadas = new Set(usadas)
  if (!ocupadas.has(base)) return base
  for (let i = 2; ; i++) {
    const c = `${base}_${i}`
    if (!ocupadas.has(c)) return c
  }
}

const DIAS: Record<Exclude<Periodo, 'personalizado'>, number> = { anual: 365, mensual: 30, semanal: 7 }

// Aporte sugerido a partir de lo que gana la persona.
//   dia:    el ingreso de un día (ingreso del periodo entre los días del periodo)
//   diezmo: el 10 % del ingreso del periodo
// En "personalizado" se usa directamente la cantidad escrita. El resultado se redondea a céntimos.
export function calcularAporte(ingreso: number, periodo: Periodo, modo: Exclude<ModoCalculadora, 'ninguna'>): number {
  if (!Number.isFinite(ingreso) || ingreso <= 0) return 0
  const x = Math.min(ingreso, 1e9)
  const bruto = periodo === 'personalizado' ? x : modo === 'dia' ? x / DIAS[periodo] : x * 0.1
  return Math.round((bruto + Number.EPSILON) * 100) / 100
}

export function formatoMoneda(monto: number, moneda: string, idioma: string): string {
  try {
    return new Intl.NumberFormat(idioma, { style: 'currency', currency: moneda }).format(monto)
  } catch {
    return `${monto.toFixed(2)} ${moneda}`
  }
}

// Texto de un número escrito por una persona: acepta coma o punto decimal y espacios; null si no es un importe
export function leerImporte(texto: string): number | null {
  const t = texto.trim().replace(/\s/g, '')
  if (!/^\d{1,9}([.,]\d{1,2})?$/.test(t)) return null
  const n = Number(t.replace(',', '.'))
  return Number.isFinite(n) ? n : null
}

// Símbolo de una moneda en un idioma (por ejemplo €, $ o R$); el propio código si no se conoce
export function simboloMoneda(moneda: string, idioma: string): string {
  try {
    return new Intl.NumberFormat(idioma, { style: 'currency', currency: moneda }).formatToParts(0).find(p => p.type === 'currency')?.value ?? moneda
  } catch {
    return moneda
  }
}

// Color intermedio de dos colores hexadecimales: sirve para elegir un texto legible sobre un degradado entre ambos
export function mezclarColores(a: string, b: string): string {
  if (!colorValido(a) || !colorValido(b)) return colorValido(a) ? a : colorValido(b) ? b : '#808080'
  const canal = (c: string, i: number) => parseInt(c.slice(1 + i * 2, 3 + i * 2), 16)
  const hex = (i: number) => Math.round((canal(a, i) + canal(b, i)) / 2).toString(16).padStart(2, '0')
  return `#${hex(0)}${hex(1)}${hex(2)}`
}
