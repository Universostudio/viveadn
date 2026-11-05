// Validacion de lo que envia la pagina publica de registro de iglesias. Sin dependencias, para poder probarla aparte.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/
// Caracteres de control y de formato invisibles (cero ancho, direccion de texto), que no tienen sitio en un nombre
const RARO_RE = /[\u0000-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2060\ufeff]/
// Sin letras ambiguas (0/O, 1/I): se leen y dictan bien
export const CODIGO_RE = /^ADN-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/

export interface DatosRegistro {
  iglesia: { nombre: string; slug: string; pais: string; ciudad: string }
  propietario: { nombre: string; apellido: string; email: string }
  codigo: string
}

export type Resultado =
  | { ok: true; datos: DatosRegistro }
  | { ok: false; error: 'bot' | 'consentimiento' | 'datos' | 'codigo_formato' }

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
  const todos = [iglesia.nombre, iglesia.slug, iglesia.pais, iglesia.ciudad, propietario.nombre, propietario.apellido, propietario.email]
  if (todos.some(t => RARO_RE.test(t))) return { ok: false, error: 'datos' }
  const codigo = normalizarCodigo(b.codigo)
  if (requiereCodigo && !CODIGO_RE.test(codigo)) return { ok: false, error: 'codigo_formato' }
  return { ok: true, datos: { iglesia, propietario, codigo } }
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
    default: return { status: 400, cuerpo: { error: 'datos' } }
  }
}
