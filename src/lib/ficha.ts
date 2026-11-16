// Edición de la ficha de una persona: normaliza y valida lo escrito y calcula solo lo que cambió, para no pisar datos que nadie tocó.
// Pura y probada en Node (scripts/probar-ficha.mts). La base aplica sus propios permisos: esto evita enviar datos inválidos y cambios vacíos.

export interface FichaForm {
  nombre: string
  apellido: string
  email: string
  telefono: string
  fecha_nacimiento: string
  nivel_compromiso: string
  casa_oracion_id: string
  notas: string
  activo: boolean
}

export interface FichaOpciones {
  /** Iglesia en modo alias: no existe apellido ni correo, y no se tocan */
  alias: boolean
  /** Niveles de compromiso válidos */
  niveles: readonly string[]
  /** Hoy en AAAA-MM-DD, para no aceptar una fecha de nacimiento futura */
  hoy: string
}

export type CampoFicha = keyof FichaForm
export type ErroresFicha = Partial<Record<CampoFicha, string>>

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const TEL_RE = /^[+(\d][\d\s().\-]{5,29}$/
// Caracteres de control y de formato invisibles, que no tienen sitio en un nombre
const RARO_RE = /[\u0000-\u001f\u007f​-‏‪-‮⁠﻿]/
const FECHA_RE = /^(\d{4})-(\d{2})-(\d{2})$/

const limpia = (v: unknown) => (typeof v === 'string' ? v.normalize('NFC').replace(/\s+/g, ' ').trim() : '')

/** De la fila de la base al formulario: los nulos pasan a texto vacío */
export function aFormulario(m: Record<string, unknown>): FichaForm {
  const s = (v: unknown) => (typeof v === 'string' ? v : '')
  return {
    nombre: s(m.nombre), apellido: s(m.apellido), email: s(m.email), telefono: s(m.telefono),
    fecha_nacimiento: s(m.fecha_nacimiento).slice(0, 10), nivel_compromiso: s(m.nivel_compromiso) || 'nuevo',
    casa_oracion_id: s(m.casa_oracion_id), notas: s(m.notas), activo: m.activo !== false,
  }
}

function fechaValida(f: string, hoy: string): boolean {
  const m = FECHA_RE.exec(f)
  if (!m) return false
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])]
  const dt = new Date(Date.UTC(y, mo - 1, d))
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return false
  return y >= 1900 && f <= hoy
}

/** Cada error es una clave de traducción; sin errores, el formulario se puede guardar */
export function validarFicha(f: FichaForm, o: FichaOpciones): ErroresFicha {
  const e: ErroresFicha = {}
  const nombre = limpia(f.nombre)
  if (!nombre) e.nombre = 'ficha.errores.nombre'
  else if (nombre.length > 100 || RARO_RE.test(nombre)) e.nombre = 'ficha.errores.nombreInvalido'
  if (!o.alias) {
    const apellido = limpia(f.apellido)
    if (!apellido) e.apellido = 'ficha.errores.apellido'
    else if (apellido.length > 100 || RARO_RE.test(apellido)) e.apellido = 'ficha.errores.apellidoInvalido'
    const email = limpia(f.email).toLowerCase()
    if (email && (email.length > 254 || !EMAIL_RE.test(email) || RARO_RE.test(email))) e.email = 'ficha.errores.email'
  }
  const tel = limpia(f.telefono)
  if (tel && (!TEL_RE.test(tel) || tel.replace(/\D/g, '').length < 7 || RARO_RE.test(tel))) e.telefono = 'ficha.errores.telefono'
  const nac = f.fecha_nacimiento.trim()
  if (nac && !fechaValida(nac, o.hoy)) e.fecha_nacimiento = 'ficha.errores.fechaNacimiento'
  if (f.notas.length > 2000) e.notas = 'ficha.errores.notas'
  if (!o.niveles.includes(f.nivel_compromiso)) e.nivel_compromiso = 'ficha.errores.nivel'
  return e
}

/** Valor normalizado de cada campo tal como se guarda: vacío pasa a nulo (salvo el apellido, que la base exige como texto) */
function normalizado(f: FichaForm, o: FichaOpciones): Record<string, unknown> {
  const nul = (v: string) => (v === '' ? null : v)
  const r: Record<string, unknown> = {
    nombre: limpia(f.nombre),
    telefono: nul(limpia(f.telefono)),
    fecha_nacimiento: nul(f.fecha_nacimiento.trim()),
    nivel_compromiso: f.nivel_compromiso,
    casa_oracion_id: nul(f.casa_oracion_id),
    notas: nul(f.notas.trim()),
    activo: f.activo,
  }
  if (!o.alias) { r.apellido = limpia(f.apellido); r.email = nul(limpia(f.email).toLowerCase()) }
  return r
}

/** Solo las columnas que cambian respecto a lo que había; vacío si no hay nada que guardar. Se compara ya normalizado, así un espacio de más no cuenta como cambio. */
export function cambiosDe(original: FichaForm, nuevo: FichaForm, o: FichaOpciones): Record<string, unknown> {
  const a = normalizado(original, o), b = normalizado(nuevo, o)
  const cambios: Record<string, unknown> = {}
  for (const k of Object.keys(b)) if (a[k] !== b[k]) cambios[k] = b[k]
  return cambios
}
