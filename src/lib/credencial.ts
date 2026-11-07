// El QR de una credencial lleva solo un prefijo y el token aleatorio: ningun dato de la persona y ninguna direccion web,
// de modo que escanearlo con una camara cualquiera no abre nada ni revela nada.
export const PREFIJO_CREDENCIAL = 'ADN1:'
const TOKEN_RE = /^[0-9a-f]{32}$/

export const textoQr = (token: string) => PREFIJO_CREDENCIAL + token

// Acepta lo que lee la camara o un lector USB (que teclea el texto, a veces con espacios o un salto de linea al final)
export function tokenDeQr(texto: string): string | null {
  const limpio = texto.trim().toLowerCase()
  const token = limpio.startsWith(PREFIJO_CREDENCIAL.toLowerCase()) ? limpio.slice(PREFIJO_CREDENCIAL.length) : limpio
  return TOKEN_RE.test(token) ? token : null
}
