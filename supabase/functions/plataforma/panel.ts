// Lecturas del Panel Maestro: solo conteos, estados, nombres de iglesia, acciones y fechas. Nunca datos de personas.
// Funciones puras, para poder probarlas sin red ni base (scripts/probar-panel-funcion.mts).

// Claves que nunca deben salir hacia el Panel Maestro. Si una respuesta nueva las trae, la función falla antes de enviarla.
const CLAVES_PERSONALES = /(email|correo|mail|telefono|phone|movil|apellido|password|contrasena|token|secret|direccion_postal|fecha_nacimiento|documento)/i

export function clavesPersonales(valor: unknown, ruta = ''): string[] {
  if (valor === null || typeof valor !== 'object') return []
  if (Array.isArray(valor)) return valor.flatMap((v, i) => clavesPersonales(v, `${ruta}[${i}]`))
  return Object.entries(valor as Record<string, unknown>).flatMap(([k, v]) =>
    (CLAVES_PERSONALES.test(k) ? [`${ruta}.${k}`] : []).concat(clavesPersonales(v, `${ruta}.${k}`)))
}

/** Lanza si la respuesta contiene alguna clave de datos personales; devuelve la misma respuesta si está limpia */
export function salidaSegura<T>(cuerpo: T): T {
  const halladas = clavesPersonales(cuerpo)
  if (halladas.length) throw new Error(`ADN_DATOS_PERSONALES_EN_PANEL: ${halladas.join(', ')}`)
  return cuerpo
}

export interface FilaConteo { iglesia_id: string; miembros: number | string; usuarios: number | string }

export function conteosPorIglesia(filas: FilaConteo[] | null | undefined): Record<string, { miembros: number; usuarios: number }> {
  return Object.fromEntries((filas ?? []).map(f => [f.iglesia_id, { miembros: Number(f.miembros) || 0, usuarios: Number(f.usuarios) || 0 }]))
}

export interface FilaActividad { tipo: string; accion: string; iglesia_id: string | null; iglesia_nombre: string | null; fecha: string }

export function eventosDeActividad(filas: FilaActividad[] | null | undefined) {
  return (filas ?? []).map(f => ({
    tipo: f.tipo === 'alta' ? 'alta' : 'accion',
    accion: String(f.accion),
    iglesia_id: f.iglesia_id ?? null,
    iglesia: f.iglesia_nombre ?? null,
    fecha: new Date(f.fecha).toISOString(),
  }))
}

export function historialDeIglesia(filas: { accion: string; fecha: string }[] | null | undefined) {
  return (filas ?? []).map(f => ({ accion: String(f.accion), fecha: new Date(f.fecha).toISOString() }))
}

export function envioDelDia(
  filas: { tipo: string; n: number }[] | null | undefined,
  config: { activo: boolean; topeGlobal: number },
) {
  const porTipo = { purga: 0, baja: 0, confirmacion: 0 } as Record<string, number>
  for (const f of filas ?? []) if (f.tipo in porTipo) porTipo[f.tipo] += Number(f.n) || 0
  const hoy = Object.values(porTipo).reduce((a, b) => a + b, 0)
  return { activo: config.activo, hoy, por_tipo: porTipo, tope_global: config.topeGlobal }
}

/** Una función o tabla de base de datos que aún no existe (migración sin aplicar): la función de borde sigue funcionando con la ruta antigua.
 *  Se reconoce por el código de error (42883 función, 42P01 tabla, PGRST202/205 del servicio) o por su mensaje exacto; un texto suelto como
 *  «does not exist» (una columna, un valor) NO basta: un fallo real no debe presentarse como «falta aplicar la migración». */
export function faltaLaFuncion(error: { code?: string; message?: string } | null | undefined): boolean {
  if (!error) return false
  if (/^(42883|42P01|PGRST202|PGRST205)$/.test(error.code ?? '')) return true
  const m = error.message ?? ''
  return /could not find the (function|table)/i.test(m) || /^(function|relation) \S+ does not exist/i.test(m)
}

export const MAX_LIBRO = 20
