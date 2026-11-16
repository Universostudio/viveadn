// Quién puede ser líder: personas activas con cuenta cuyo rol tiene el permiso que hace útil el cargo (o es propietario).
// Un líder nombrado con un rol sin ese permiso no vería nada, así que no se ofrece como candidato. Funciones puras, probadas en Node.

export interface RolConPermisos { clave: string; es_propietario?: boolean; rol_permisos?: { permiso: string }[] }
export interface PerfilBasico { id: string; nombre: string; apellido: string; rol: string; activo?: boolean }

export function candidatos(roles: RolConPermisos[], perfiles: PerfilBasico[], permiso: string): PerfilBasico[] {
  const validos = new Set(roles.filter(r => r.es_propietario || (r.rol_permisos ?? []).some(x => x.permiso === permiso)).map(r => r.clave))
  return perfiles.filter(p => p.activo !== false && validos.has(p.rol))
}

/** Código de zona: letras y números en mayúsculas, de 2 a 10 caracteres */
export function codigoDeZonaValido(codigo: string): boolean {
  return /^[A-Z0-9]{2,10}$/.test(codigo)
}
export const normalizarCodigoZona = (c: string) => c.trim().toUpperCase().replace(/[^A-Z0-9]/g, '')

/** Cuenta las casas de cada zona y las que no tienen zona */
export function casasPorZona(casas: { zona_id: string | null }[]): { porZona: Record<string, number>; sinZona: number } {
  const porZona: Record<string, number> = {}
  let sinZona = 0
  for (const c of casas) { if (c.zona_id) porZona[c.zona_id] = (porZona[c.zona_id] ?? 0) + 1; else sinZona++ }
  return { porZona, sinZona }
}
