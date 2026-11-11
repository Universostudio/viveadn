// Lectura de la petición de baja. Dos formas de llegar:
//  * La página /baja/<secreto>: POST con JSON {"token": "..."}, después de que la persona pulse el botón de confirmar.
//  * La baja de un clic de los programas de correo (RFC 8058): POST a <función>?t=<secreto> con el cuerpo exacto
//    «List-Unsubscribe=One-Click». Es una acción explícita del programa de correo, no una vista previa, que solo hace GET.
// Sin dependencias, para poder probarla aparte.

export const TOKEN_RE = /^[0-9a-f]{64}$/
export type ModoBaja = 'json' | 'una_clic'

export function leerPeticion(url: string, contentType: string | null, cuerpo: string): { modo: ModoBaja; token: string } | null {
  let t: string | null = null
  try { t = new URL(url).searchParams.get('t') } catch { /* sin dirección válida */ }
  if (t !== null) {
    const forma = (contentType ?? '').toLowerCase().split(';')[0]!.trim() === 'application/x-www-form-urlencoded'
    const token = t.trim().toLowerCase()
    return forma && cuerpo.trim() === 'List-Unsubscribe=One-Click' && TOKEN_RE.test(token) ? { modo: 'una_clic', token } : null
  }
  let json: unknown = {}
  try { json = JSON.parse(cuerpo || '{}') } catch { return null }
  const token = String((json as { token?: unknown })?.token ?? '').trim().toLowerCase()
  return TOKEN_RE.test(token) ? { modo: 'json', token } : null
}
