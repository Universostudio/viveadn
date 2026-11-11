// Validacion de lo que envia la pagina publica de registro por QR. Sin dependencias, para poder probarla aparte.

export const TOKEN_RE = /^[0-9a-f]{64}$/
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const TEL_RE = /^[+\d][\d\s().\-]{5,29}$/
// Caracteres de control y de formato invisibles (cero ancho, direccion de texto), que no tienen sitio en un nombre
const RARO_RE = /[\u0000-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2060\ufeff]/

export interface Datos {
  nombre: string
  apellido: string
  telefono: string
  email: string
  /** Versión del texto de consentimiento que mostraba la página y su idioma; vacíos si no constan o no son válidos */
  textoVersion: string
  idioma: string
  /** Canales de comunicación cuya casilla marcó la persona (cada una por separado, sin marcar de antemano) */
  canales: string[]
}

export type Resultado =
  | { ok: true; datos: Datos }
  | { ok: false; error: 'bot' | 'consentimiento' | 'datos' }

const VERSION_RE = /^[a-z0-9._-]{1,20}$/
const IDIOMAS = ['es', 'en', 'fr', 'pt-BR']
const CANALES = ['email', 'whatsapp', 'sms']

const texto = (v: unknown, max: number) => (typeof v === 'string' ? v.normalize('NFC').replace(/\s+/g, ' ').trim().slice(0, max + 1) : '')

export function validarRegistro(b: Record<string, unknown>): Resultado {
  // Campo trampa: las personas no lo ven; si trae algo, es un robot
  if (typeof b.web === 'string' && b.web.trim() !== '') return { ok: false, error: 'bot' }
  if (b.consentimiento !== true || b.mayor14 !== true) return { ok: false, error: 'consentimiento' }
  const nombre = texto(b.nombre, 100)
  const apellido = texto(b.apellido, 100)
  const telefono = texto(b.telefono, 30)
  const email = texto(b.email, 254).toLowerCase()
  // El apellido puede venir vacio: en una iglesia con modo alias no existe. Si la iglesia lo exige, lo rechaza la base de datos
  if (!nombre || nombre.length > 100 || apellido.length > 100) return { ok: false, error: 'datos' }
  if (RARO_RE.test(nombre) || RARO_RE.test(apellido) || RARO_RE.test(telefono) || RARO_RE.test(email)) return { ok: false, error: 'datos' }
  if (!TEL_RE.test(telefono) || telefono.replace(/\D/g, '').length < 7) return { ok: false, error: 'datos' }
  if (email && (email.length > 254 || !EMAIL_RE.test(email))) return { ok: false, error: 'datos' }
  // La versión del texto la afirma la página; la base la contrasta con su tabla de textos y, si no consta, no la da por buena
  const textoVersion = typeof b.texto_version === 'string' && VERSION_RE.test(b.texto_version) ? b.texto_version : ''
  const idioma = typeof b.idioma === 'string' && IDIOMAS.includes(b.idioma) ? b.idioma : ''
  // Solo cuenta una casilla que llega exactamente como true. Marcar el correo sin escribir un correo es un dato incompleto.
  const marcadas = typeof b.canales === 'object' && b.canales !== null && !Array.isArray(b.canales) ? (b.canales as Record<string, unknown>) : {}
  const canales = CANALES.filter(c => marcadas[c] === true)
  if (canales.includes('email') && !email) return { ok: false, error: 'datos' }
  return { ok: true, datos: { nombre, apellido, telefono, email, textoVersion, idioma, canales } }
}

// Respuesta al visitante segun lo que devuelve la base de datos. Nuevo y existente se responden igual.
export function respuestaDe(estado: string): { status: number; cuerpo: Record<string, unknown> } {
  switch (estado) {
    case 'ok_nuevo':
    case 'ok_existente': return { status: 200, cuerpo: { ok: true } }
    case 'cerrado': return { status: 409, cuerpo: { error: 'cerrado' } }
    case 'lleno': return { status: 409, cuerpo: { error: 'lleno' } }
    case 'limite': return { status: 429, cuerpo: { error: 'limite' } }
    case 'datos': return { status: 400, cuerpo: { error: 'datos' } }
    default: return { status: 404, cuerpo: { error: 'no_valido' } }
  }
}
