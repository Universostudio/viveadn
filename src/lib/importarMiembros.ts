// Lectura y validación de un archivo CSV de miembros. Son funciones puras, sin acceso a la red.
import type { NivelCompromiso } from '@/lib/supabase'

// Mismos valores que NIVELES_COMPROMISO; el compilador rechaza cualquiera que no sea un nivel válido.
// Se repiten aquí para que este archivo no cargue el cliente de Supabase y se pueda probar aparte.
const NIVELES = ['nuevo', 'en_crecimiento', 'maduro', 'lider', 'multiplicador'] satisfies readonly NivelCompromiso[]

export const MAX_FILAS = 2000
export const MAX_BYTES = 2_000_000

export const COLUMNAS = ['nombre', 'apellido', 'email', 'telefono', 'fecha_nacimiento', 'genero', 'nivel_compromiso', 'notas'] as const
export type Columna = typeof COLUMNAS[number]

// Códigos de error; el texto visible está en src/i18n (miembros.importar.error.<codigo>)
export type CodigoError = 'faltaNombre' | 'faltaApellido' | 'emailInvalido' | 'telefonoInvalido' | 'fechaInvalida' | 'nivelInvalido' | 'demasiadoLargo'

export interface DatosMiembro {
  nombre: string
  apellido: string
  email: string | null
  telefono: string | null
  fecha_nacimiento: string | null
  genero: string | null
  nivel_compromiso: string
  notas: string | null
}

export interface FilaImportar {
  linea: number
  datos: DatosMiembro
  errores: CodigoError[]
  duplicado: boolean
}

export type ErrorArchivo = 'vacio' | 'sinColumnas' | 'demasiadasFilas'

export interface Analisis {
  error?: ErrorArchivo
  filas: FilaImportar[]
  ignoradas: string[]
}

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[_\-.]+/g, ' ').replace(/\s+/g, ' ').trim()

// Nombres de columna aceptados, en español e inglés, ya normalizados
const ALIAS: Record<string, Columna> = {
  'nombre': 'nombre', 'nombres': 'nombre', 'first name': 'nombre', 'name': 'nombre',
  'apellido': 'apellido', 'apellidos': 'apellido', 'last name': 'apellido', 'surname': 'apellido',
  'email': 'email', 'e mail': 'email', 'correo': 'email', 'correo electronico': 'email',
  'telefono': 'telefono', 'movil': 'telefono', 'celular': 'telefono', 'phone': 'telefono', 'whatsapp': 'telefono',
  'fecha nacimiento': 'fecha_nacimiento', 'fecha de nacimiento': 'fecha_nacimiento', 'nacimiento': 'fecha_nacimiento', 'birthday': 'fecha_nacimiento', 'birth date': 'fecha_nacimiento',
  'genero': 'genero', 'sexo': 'genero', 'gender': 'genero',
  'nivel compromiso': 'nivel_compromiso', 'nivel de compromiso': 'nivel_compromiso', 'nivel': 'nivel_compromiso',
  'notas': 'notas', 'observaciones': 'notas', 'notes': 'notas',
}

// Convierte el texto en filas de celdas. Detecta coma, punto y coma o tabulador, y respeta las comillas.
export function parseCsv(texto: string): string[][] {
  const t = texto.replace(/^﻿/, '')
  const primera = t.split(/\r?\n/, 1)[0] ?? ''
  const conteo = (c: string) => primera.split(c).length - 1
  const sep = [';', '\t', ','].reduce((mejor, c) => (conteo(c) > conteo(mejor) ? c : mejor), ',')
  const filas: string[][] = []
  let fila: string[] = []
  let celda = ''
  let comillas = false
  for (let i = 0; i < t.length; i++) {
    const c = t[i]
    if (comillas) {
      if (c === '"') {
        if (t[i + 1] === '"') { celda += '"'; i++ } else comillas = false
      } else celda += c
    } else if (c === '"') comillas = true
    else if (c === sep) { fila.push(celda); celda = '' }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && t[i + 1] === '\n') i++
      fila.push(celda); celda = ''
      filas.push(fila); fila = []
    } else celda += c
  }
  if (celda !== '' || fila.length) { fila.push(celda); filas.push(fila) }
  return filas.filter(f => f.some(c => c.trim() !== ''))
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const TEL_RE = /^[+\d][\d\s().\-]{5,29}$/

// Acepta AAAA-MM-DD, DD/MM/AAAA y DD-MM-AAAA; devuelve AAAA-MM-DD o null si no es una fecha real
export function fechaIso(v: string, hoy = new Date()): string | null {
  let a: number, m: number, d: number
  let r = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(v)
  if (r) { a = Number(r[1]); m = Number(r[2]); d = Number(r[3]) } else {
    r = /^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/.exec(v)
    if (!r) return null
    d = Number(r[1]); m = Number(r[2]); a = Number(r[3])
  }
  const f = new Date(Date.UTC(a, m - 1, d))
  if (f.getUTCFullYear() !== a || f.getUTCMonth() !== m - 1 || f.getUTCDate() !== d) return null
  if (a < 1900 || f > hoy) return null
  return `${a}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
}

const LIMITES: Record<Columna, number> = { nombre: 100, apellido: 100, email: 254, telefono: 30, fecha_nacimiento: 10, genero: 30, nivel_compromiso: 30, notas: 1000 }

// En modo alias el apellido no existe y el correo no se guarda: el alias va en la columna nombre
export function validarFila(celdas: Partial<Record<Columna, string>>, linea: number, alias = false): FilaImportar {
  const v = (c: Columna) => (celdas[c] ?? '').trim()
  const errores: CodigoError[] = []
  if (Object.entries(LIMITES).some(([c, max]) => v(c as Columna).length > max)) errores.push('demasiadoLargo')
  if (!v('nombre')) errores.push('faltaNombre')
  if (!alias && !v('apellido')) errores.push('faltaApellido')
  const email = alias ? '' : v('email').toLowerCase()
  if (email && !EMAIL_RE.test(email)) errores.push('emailInvalido')
  const tel = v('telefono')
  if (tel && !TEL_RE.test(tel)) errores.push('telefonoInvalido')
  let nacimiento: string | null = null
  if (v('fecha_nacimiento')) {
    nacimiento = fechaIso(v('fecha_nacimiento'))
    if (!nacimiento) errores.push('fechaInvalida')
  }
  const nivel = normalizar(v('nivel_compromiso')).replace(/ /g, '_') || 'nuevo'
  if (!(NIVELES as readonly string[]).includes(nivel)) errores.push('nivelInvalido')
  return {
    linea,
    errores,
    duplicado: false,
    datos: {
      nombre: v('nombre'), apellido: alias ? '' : v('apellido'),
      email: email || null, telefono: tel || null, fecha_nacimiento: nacimiento,
      genero: v('genero') || null, nivel_compromiso: nivel, notas: v('notas') || null,
    },
  }
}

// Clave para detectar repetidos: el correo si existe; si no, nombre y apellido sin acentos
export const claveMiembro = (d: Pick<DatosMiembro, 'nombre' | 'apellido' | 'email'>) =>
  d.email ? `e:${d.email.toLowerCase()}` : `n:${normalizar(`${d.nombre} ${d.apellido}`)}`

// Marca como duplicadas las filas que ya existen en la iglesia o que se repiten dentro del archivo
export function marcarDuplicados(filas: FilaImportar[], existentes: Set<string>): FilaImportar[] {
  const vistos = new Set(existentes)
  return filas.map(f => {
    if (f.errores.length) return f
    const k = claveMiembro(f.datos)
    const duplicado = vistos.has(k)
    vistos.add(k)
    return { ...f, duplicado }
  })
}

export function analizarCsv(texto: string, alias = false): Analisis {
  const filas = parseCsv(texto)
  if (filas.length < 2) return { error: 'vacio', filas: [], ignoradas: [] }
  const cabecera = filas[0] ?? []
  const columnas = cabecera.map(h => ALIAS[normalizar(h)] as Columna | undefined)
  if (!columnas.includes('nombre') || (!alias && !columnas.includes('apellido'))) return { error: 'sinColumnas', filas: [], ignoradas: [] }
  if (filas.length - 1 > MAX_FILAS) return { error: 'demasiadasFilas', filas: [], ignoradas: [] }
  const ignoradas = cabecera.filter((_, i) => !columnas[i]).map(h => h.trim()).filter(Boolean)
  const vistas = new Set<Columna>()
  const cols = columnas.map(c => (c && !vistas.has(c) ? (vistas.add(c), c) : undefined))
  const resultado = filas.slice(1).map((celdas, i) => {
    const datos: Partial<Record<Columna, string>> = {}
    cols.forEach((c, j) => { if (c) datos[c] = celdas[j] ?? '' })
    return validarFila(datos, i + 2, alias)
  })
  return { filas: resultado, ignoradas }
}

export const PLANTILLA_CSV = '﻿nombre,apellido,email,telefono,fecha_nacimiento,genero,nivel_compromiso,notas\r\nMaría,García López,maria@ejemplo.com,+34 600 000 000,1990-05-21,Femenino,en_crecimiento,Llegó por una casa de oración\r\n'
