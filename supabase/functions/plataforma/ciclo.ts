// Piezas puras del ciclo de vida de la iglesia (borrado suave, recuperacion y purga). Sin dependencias,
// para poder probarlas aparte con `npm run test:ciclo`.

// Plazo de gracia fijo. Lo impone la base (adn_borrar_suave); aqui solo se muestra.
export const PLAZO_GRACIA_DIAS = 30

// Cuantas iglesias vencidas purga una sola llamada: cada purga borra archivos y cuentas una a una
export const PURGA_LOTE_MAX = 20
export const PURGA_LOTE_DEFECTO = 5

// Compara la clave de la tarea programada con la esperada, en tiempo constante. Si no hay clave
// configurada (secreto vacio), la via de la tarea programada queda cerrada.
export async function claveCronValida(recibida: string | null, esperada: string | undefined): Promise<boolean> {
  if (!recibida || !esperada || esperada.length < 32) return false
  const huella = async (t: string) => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(t)))
  const [a, b] = await Promise.all([huella(recibida), huella(esperada)])
  let dif = 0
  for (let i = 0; i < a.length; i++) dif |= a[i] ^ b[i]
  return dif === 0
}

// Cuantas iglesias purgar en esta llamada, siempre entre 1 y PURGA_LOTE_MAX
export function tamanoLote(pedido: unknown): number {
  const n = Number(pedido)
  if (!Number.isInteger(n) || n < 1) return PURGA_LOTE_DEFECTO
  return Math.min(n, PURGA_LOTE_MAX)
}

export interface RespuestaError { estado: number; mensaje: string }

// Traduce el error de una de las funciones adn_* de la base a una respuesta para el panel
export function errorDeCiclo(mensaje: string | undefined): RespuestaError {
  const m = mensaje ?? ''
  if (/ADN_YA_BORRADA/.test(m)) return { estado: 409, mensaje: 'La iglesia ya esta en borrado suave' }
  if (/ADN_NO_BORRADA/.test(m)) return { estado: 409, mensaje: 'La iglesia no esta en borrado suave' }
  if (/ADN_PLAZO_VENCIDO/.test(m)) return { estado: 409, mensaje: `El plazo de ${PLAZO_GRACIA_DIAS} dias ya vencio: la iglesia ya no se puede recuperar` }
  if (/BORRADO_NO_VENCIDO/.test(m)) return { estado: 409, mensaje: 'El plazo de gracia todavia no ha vencido' }
  if (/no existe/i.test(m)) return { estado: 404, mensaje: 'La iglesia no existe' }
  return { estado: 500, mensaje: 'No se pudo completar la operacion' }
}
