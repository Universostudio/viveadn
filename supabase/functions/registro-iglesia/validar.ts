// Validacion de lo que envia la pagina publica de registro de iglesias. Sin dependencias, para poder probarla aparte.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/
// Caracteres de control y de formato invisibles (cero ancho, direccion de texto), que no tienen sitio en un nombre
const RARO_RE = /[\u0000-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2060\ufeff]/
// Sin letras ambiguas (0/O, 1/I): se leen y dictan bien
export const CODIGO_RE = /^ADN-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/

const CLAVE_RE = /^[a-z0-9_]{1,40}$/
const PLAN_RE = /^[a-z0-9_]{1,30}$/
export const TIPOS_ESTRUCTURA = ['unica', 'con_sedes', 'red'] as const
export const MAX_ADMINISTRADORES = 5
export const MAX_MODULOS = 30
export const MAX_PERSONAS = 1_000_000
export const MAX_SEDES = 200

// Monedas con lista de precios propia. La base interna es USD: un pais sin lista propia paga en USD. Debe coincidir con src/lib/cotizador.ts
// (lo comprueba npm run test:registro). Zona euro y los micro-estados que usan el euro.
export const MONEDAS = ['USD', 'EUR'] as const
export type Moneda = (typeof MONEDAS)[number]
export const PAISES_EURO = ['AD', 'AT', 'BE', 'BG', 'CY', 'DE', 'EE', 'ES', 'FI', 'FR', 'GR', 'HR', 'IE', 'IT', 'LT', 'LU', 'LV', 'MC', 'ME', 'MT', 'NL', 'PT', 'SI', 'SK', 'SM', 'VA']
export const monedaDePais = (iso: string | null): Moneda => (iso !== null && PAISES_EURO.includes(iso) ? 'EUR' : 'USD')
const ISO_RE = /^[A-Z]{2}$/

export interface Persona { nombre: string; apellido: string; email: string }
export interface DatosRegistro {
  iglesia: { nombre: string; slug: string; pais: string; ciudad: string }
  paisIso: string | null   // ISO 3166-1 alfa-2 si el navegador lo manda; de el sale la moneda
  moneda: Moneda
  propietario: Persona
  codigo: string
  // Asistente de alta. Si el navegador manda el formato antiguo (sin estos campos) se usan los valores de antes: plan semilla, sin modulos
  plan: string
  estructura: { tipo: (typeof TIPOS_ESTRUCTURA)[number]; personas: number | null; sedes: number }
  modulos: string[]
  administradores: Persona[]
}

export type Resultado =
  | { ok: true; datos: DatosRegistro }
  | { ok: false; error: 'bot' | 'consentimiento' | 'datos' | 'codigo_formato' }

const entero = (v: unknown, min: number, max: number): number | null =>
  typeof v === 'number' && Number.isInteger(v) && v >= min && v <= max ? v : null

const texto = (v: unknown, max: number) => (typeof v === 'string' ? v.normalize('NFC').replace(/\s+/g, ' ').trim().slice(0, max + 1) : '')

export const normalizarCodigo = (v: unknown) => (typeof v === 'string' ? v.normalize('NFC').replace(/\s+/g, '').toUpperCase() : '')

export function validarRegistro(b: Record<string, unknown>, requiereCodigo: boolean): Resultado {
  // Campo trampa: las personas no lo ven; si trae algo, es un robot
  if (typeof b.web === 'string' && b.web.trim() !== '') return { ok: false, error: 'bot' }
  if (b.consentimiento !== true) return { ok: false, error: 'consentimiento' }
  const ig = (typeof b.iglesia === 'object' && b.iglesia !== null ? b.iglesia : {}) as Record<string, unknown>
  const pr = (typeof b.propietario === 'object' && b.propietario !== null ? b.propietario : {}) as Record<string, unknown>
  const iglesia = { nombre: texto(ig.nombre, 80), slug: texto(ig.slug, 40).toLowerCase(), pais: texto(ig.pais, 80), ciudad: texto(ig.ciudad, 80) }
  const propietario = { nombre: texto(pr.nombre, 60), apellido: texto(pr.apellido, 60), email: texto(pr.email, 254).toLowerCase() }
  if (iglesia.nombre.length < 2 || iglesia.nombre.length > 80) return { ok: false, error: 'datos' }
  if (!SLUG_RE.test(iglesia.slug) || iglesia.slug.length < 3 || iglesia.slug.length > 40) return { ok: false, error: 'datos' }
  if (!iglesia.pais || !iglesia.ciudad || iglesia.pais.length > 80 || iglesia.ciudad.length > 80) return { ok: false, error: 'datos' }
  if (!propietario.nombre || !propietario.apellido || propietario.nombre.length > 60 || propietario.apellido.length > 60) return { ok: false, error: 'datos' }
  if (propietario.email.length > 254 || !EMAIL_RE.test(propietario.email)) return { ok: false, error: 'datos' }
  let paisIso: string | null = null
  if (ig.pais_iso !== undefined && ig.pais_iso !== null) {
    if (typeof ig.pais_iso !== 'string' || !ISO_RE.test(ig.pais_iso)) return { ok: false, error: 'datos' }
    paisIso = ig.pais_iso
  }
  const todos = [iglesia.nombre, iglesia.slug, iglesia.pais, iglesia.ciudad, propietario.nombre, propietario.apellido, propietario.email]
  if (todos.some(t => RARO_RE.test(t))) return { ok: false, error: 'datos' }
  const codigo = normalizarCodigo(b.codigo)
  if (requiereCodigo && !CODIGO_RE.test(codigo)) return { ok: false, error: 'codigo_formato' }

  // Plan: solo una clave con forma de clave; que exista y cubra el tamano lo decide decidirAlta con el catalogo
  let plan = 'semilla'
  if (b.plan !== undefined) {
    if (typeof b.plan !== 'string' || !PLAN_RE.test(b.plan)) return { ok: false, error: 'datos' }
    plan = b.plan
  }
  // Estructura: si viene, tipo y personas son obligatorios; las sedes solo cuentan si hay sedes
  let estructura: DatosRegistro['estructura'] = { tipo: 'unica', personas: null, sedes: 0 }
  if (b.estructura !== undefined) {
    if (typeof b.estructura !== 'object' || b.estructura === null || Array.isArray(b.estructura)) return { ok: false, error: 'datos' }
    const e = b.estructura as Record<string, unknown>
    if (typeof e.tipo !== 'string' || !(TIPOS_ESTRUCTURA as readonly string[]).includes(e.tipo)) return { ok: false, error: 'datos' }
    const tipo = e.tipo as DatosRegistro['estructura']['tipo']
    const personas = entero(e.personas, 1, MAX_PERSONAS)
    if (personas === null) return { ok: false, error: 'datos' }
    let sedes = 0
    if (e.sedes !== undefined && e.sedes !== null) {
      const s = entero(e.sedes, 0, MAX_SEDES)
      if (s === null || (tipo === 'unica' && s !== 0)) return { ok: false, error: 'datos' }
      sedes = s
    }
    estructura = { tipo, personas, sedes }
  }
  // Modulos: lista corta de claves, sin repetidos
  let modulos: string[] = []
  if (b.modulos !== undefined) {
    if (!Array.isArray(b.modulos) || b.modulos.length > MAX_MODULOS) return { ok: false, error: 'datos' }
    if (b.modulos.some(m => typeof m !== 'string' || !CLAVE_RE.test(m))) return { ok: false, error: 'datos' }
    modulos = [...new Set(b.modulos as string[])]
  }
  // Administradores propuestos: no reciben nada al registrarse; solo se guardan como sugerencia para el propietario
  const administradores: Persona[] = []
  if (b.administradores !== undefined) {
    if (!Array.isArray(b.administradores) || b.administradores.length > MAX_ADMINISTRADORES) return { ok: false, error: 'datos' }
    const vistos = new Set<string>([propietario.email])
    for (const a of b.administradores) {
      if (typeof a !== 'object' || a === null || Array.isArray(a)) return { ok: false, error: 'datos' }
      const x = a as Record<string, unknown>
      const p = { nombre: texto(x.nombre, 60), apellido: texto(x.apellido, 60), email: texto(x.email, 254).toLowerCase() }
      if (!p.nombre || !p.apellido || p.nombre.length > 60 || p.apellido.length > 60) return { ok: false, error: 'datos' }
      if (p.email.length > 254 || !EMAIL_RE.test(p.email) || vistos.has(p.email)) return { ok: false, error: 'datos' }
      if ([p.nombre, p.apellido, p.email].some(t => RARO_RE.test(t))) return { ok: false, error: 'datos' }
      vistos.add(p.email)
      administradores.push(p)
    }
  }
  return { ok: true, datos: { iglesia, paisIso, moneda: monedaDePais(paisIso), propietario, codigo, plan, estructura, modulos, administradores } }
}

export interface PlanCatalogo { clave: string; max_miembros: number | null }
export interface ModuloCatalogo { clave: string; tipo: string }

// Decide con el catalogo real si el alta es posible. El navegador solo propone: el plan debe existir y cubrir el tamano,
// y cada modulo debe existir y poder contratarse. Devuelve los modulos que el plan no incluye, que se dan como cortesia.
export function decidirAlta(
  d: Pick<DatosRegistro, 'estructura' | 'modulos'>,
  plan: PlanCatalogo | null,
  modulos: ModuloCatalogo[],
  incluidosEnPlan: string[],
): { ok: true; extras: string[] } | { ok: false; error: 'plan' | 'modulos' } {
  if (!plan) return { ok: false, error: 'plan' }
  const p = d.estructura.personas
  if (p !== null && plan.max_miembros !== null && p > plan.max_miembros) return { ok: false, error: 'plan' }
  const porClave = new Map(modulos.map(m => [m.clave, m]))
  const incluidos = new Set(incluidosEnPlan)
  const extras: string[] = []
  for (const clave of d.modulos) {
    const m = porClave.get(clave)
    if (!m || m.tipo === 'nucleo') return { ok: false, error: 'modulos' }
    if (!incluidos.has(clave)) extras.push(clave)
  }
  return { ok: true, extras }
}

// Respuesta al visitante segun el motivo del rechazo; el texto lo pone la pagina en su idioma
export function respuestaDeError(error: string): { status: number; cuerpo: Record<string, unknown> } {
  switch (error) {
    case 'consentimiento': return { status: 400, cuerpo: { error: 'consentimiento' } }
    case 'codigo_formato':
    case 'codigo': return { status: 403, cuerpo: { error: 'codigo' } }
    case 'cerrado': return { status: 403, cuerpo: { error: 'cerrado' } }
    case 'limite': return { status: 429, cuerpo: { error: 'limite' } }
    case 'slug': return { status: 409, cuerpo: { error: 'slug' } }
    case 'plan': return { status: 400, cuerpo: { error: 'plan' } }
    case 'modulos': return { status: 400, cuerpo: { error: 'modulos' } }
    default: return { status: 400, cuerpo: { error: 'datos' } }
  }
}
