// Validacion de lo que recibe la verificacion publica de certificados. Sin dependencias, para poder probarla aparte.

// El codigo del certificado: 32 caracteres hexadecimales, de una sola vez azarosa. No se puede adivinar ni enumerar.
export const CODIGO_RE = /^[0-9a-f]{32}$/

export function codigoDe(cuerpo: unknown): string | null {
  if (typeof cuerpo !== 'object' || cuerpo === null || Array.isArray(cuerpo)) return null
  const c = (cuerpo as Record<string, unknown>).codigo
  return typeof c === 'string' && CODIGO_RE.test(c) ? c : null
}

// Lo unico que sale de la base hacia el visitante: estado, iglesia, programa, fecha y, si es valido, el titular reducido
export function respuestaDe(info: unknown): { status: number; cuerpo: Record<string, unknown> } {
  if (typeof info !== 'object' || info === null) return { status: 404, cuerpo: { error: 'no_valido' } }
  const i = info as Record<string, unknown>
  if (i.estado !== 'valido' && i.estado !== 'revocado') return { status: 404, cuerpo: { error: 'no_valido' } }
  const salida: Record<string, unknown> = { estado: i.estado, iglesia: i.iglesia, programa: i.programa, emitido_en: i.emitido_en }
  if (i.estado === 'valido') salida.titular = i.titular
  return { status: 200, cuerpo: salida }
}
