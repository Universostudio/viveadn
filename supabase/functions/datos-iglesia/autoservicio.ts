// Piezas puras de la función `datos-iglesia` (autoservicio del propietario): traducción de los errores de la base y validación
// de lo que llega del navegador. Sin dependencias, para probarlas aparte con `npm run test:autoservicio`.

export interface RespuestaError { estado: number; mensaje: string }

// Traduce el error de una de las funciones adn_autoservicio_* de la base a una respuesta para la pantalla del propietario
export function errorDeAutoservicio(mensaje: string | undefined): RespuestaError {
  const m = mensaje ?? ''
  if (/ADN_NO_PROPIETARIO/.test(m)) return { estado: 403, mensaje: 'Solo el propietario de la iglesia puede hacerlo' }
  if (/ADN_LIMITE_DESCARGAS/.test(m)) return { estado: 429, mensaje: 'Ya se hicieron 6 descargas completas en la última hora. Vuelve a intentarlo más tarde' }
  if (/ADN_YA_BORRADA/.test(m)) return { estado: 409, mensaje: 'La baja ya está pedida' }
  if (/ADN_NO_BORRADA/.test(m)) return { estado: 409, mensaje: 'No hay ninguna baja pedida' }
  if (/ADN_BAJA_DE_PLATAFORMA/.test(m)) return { estado: 403, mensaje: 'Esta baja la abrió la plataforma: escribe a soporte si quieres recuperarla' }
  if (/ADN_PLAZO_VENCIDO/.test(m)) return { estado: 409, mensaje: 'El plazo de 30 días ya venció: la iglesia ya no se puede recuperar' }
  return { estado: 500, mensaje: 'No se pudo completar la operación' }
}

export interface PeticionPagina { tabla: string; formato: 'json' | 'csv'; despues: string[] | null; limite: number }

// Valida una petición de página. Devuelve la petición limpia o el motivo del rechazo
export function validarPagina(body: Record<string, unknown>): { ok: true; pagina: PeticionPagina } | { ok: false; error: string } {
  if (typeof body.tabla !== 'string' || !/^[a-z][a-z0-9_]{0,62}$/.test(body.tabla)) return { ok: false, error: 'Tabla no valida' }
  if (body.formato !== 'json' && body.formato !== 'csv') return { ok: false, error: 'Formato no valido' }
  const despues = body.despues ?? null
  if (despues !== null && (!Array.isArray(despues) || despues.length === 0 || despues.length > 8
      || !despues.every((v: unknown) => typeof v === 'string' && v.length <= 200))) return { ok: false, error: 'Cursor no valido' }
  const limite = Number.isInteger(body.limite) ? Math.min(Math.max(body.limite as number, 1), 5000) : 1000
  return { ok: true, pagina: { tabla: body.tabla, formato: body.formato, despues: despues as string[] | null, limite } }
}

// La baja exige escribir la dirección de la iglesia, como en el panel de plataforma. El motivo es opcional y se recorta
export function validarBaja(body: Record<string, unknown>, slug: string): { ok: true; motivo: string | null } | { ok: false; error: string } {
  if (typeof body.confirmar !== 'string' || body.confirmar.trim() !== slug) return { ok: false, error: 'La confirmación no coincide con la dirección de la iglesia' }
  const motivo = String(body.motivo ?? '').trim().slice(0, 500)
  return { ok: true, motivo: motivo || null }
}
