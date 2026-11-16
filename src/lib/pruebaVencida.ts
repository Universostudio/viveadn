// Prueba vencida: el núcleo sigue en SOLO LECTURA (la base lo aplica en private.tiene_permiso; esto es el mismo criterio para la interfaz).
// Solo se conceden los permisos de lectura de los módulos del núcleo. Lo de pago, lo incluido y todo lo que escribe queda cerrado.
export const PERMISO_DE_LECTURA = /\.(ver|ver_asignados|ver_casa|ver_propia|exportar)$/

export const esPermisoDeLectura = (clave: string) => PERMISO_DE_LECTURA.test(clave)

/** Una iglesia en prueba cuya fecha de fin ya pasó */
export function pruebaVencida(ig: { etapa?: string | null; prueba_hasta?: string | null; activa?: boolean } | null | undefined, ahora = Date.now()): boolean {
  if (!ig || ig.etapa !== 'prueba' || ig.activa === false || !ig.prueba_hasta) return false
  return new Date(ig.prueba_hasta).getTime() <= ahora
}

/** Módulos que siguen disponibles con la prueba vencida: los del núcleo que ya tenía. `tipos` es el catálogo (clave a tipo). */
export function modulosEnPruebaVencida(activos: Set<string>, tipos: Record<string, string>): Set<string> {
  return new Set([...activos].filter(m => tipos[m] === 'nucleo'))
}

/** ¿Puede esta persona hacer esto con la prueba vencida? Solo lecturas. */
export const permitidoConPruebaVencida = (clave: string) => esPermisoDeLectura(clave)
