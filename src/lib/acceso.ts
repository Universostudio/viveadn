// Quién ve qué: el menú de la aplicación de iglesia y la comprobación de acceso de cada ruta, con las mismas reglas.
// Son funciones puras para probarlas en Node con los permisos reales de cada rol (scripts/probar-acceso.mts). La base de datos aplica los
// permisos por su cuenta con políticas de nivel de fila: esto decide lo que se ofrece en pantalla y a dónde se redirige, no lo que se puede leer.

export interface ContextoAcceso {
  /** true si el rol (o la vista previa de otro rol) tiene alguno de los permisos y la iglesia tiene su módulo */
  can: (...claves: string[]) => boolean
  tieneModulo: (modulo: string) => boolean
  esPropietario: boolean
  tieneSedes: boolean
}

export interface Requisitos {
  /** Alguno de estos permisos. Vacío o ausente: cualquier persona con sesión */
  permisos?: string[]
  /** El plan de la iglesia debe incluir este módulo */
  modulo?: string
  soloPropietario?: boolean
  /** Con permisos: basta con tener alguno de ellos O ser propietario (por ejemplo, el soporte con la prueba vencida, cuando los permisos se cierran) */
  oPropietario?: boolean
  /** Solo si la iglesia tiene sedes (red de iglesias) */
  red?: boolean
  /** Líder de casa: ve su casa pero no todas */
  soloLiderDeCasa?: boolean
}

export function cumple(r: Requisitos, c: ContextoAcceso): boolean {
  if (r.soloPropietario && !c.esPropietario) return false
  if (r.red && !c.tieneSedes) return false
  if (r.modulo && !c.tieneModulo(r.modulo)) return false
  if (r.soloLiderDeCasa && !esLiderDeCasa(c)) return false
  if (r.permisos && r.permisos.length > 0 && !c.can(...r.permisos) && !(r.oPropietario && c.esPropietario)) return false
  return true
}

/** Quien ve solo su casa (ver_propia) y no todas (ver): su portada es «Mi panel» */
export const esLiderDeCasa = (c: Pick<ContextoAcceso, 'can'>) => c.can('casas.ver_propia') && !c.can('casas.ver')

export interface ItemMenu extends Requisitos { clave: string; to: string; etiqueta: string }

// Todos los permisos de ver, incluidos los acotados a la zona o a lo que registra la persona (ver_zona, ver_propios, ver_asignados)
export const ITEMS_MENU: ItemMenu[] = [
  { clave: 'miPanel', to: '/mi-panel', etiqueta: 'menu.miPanel', soloLiderDeCasa: true },
  { clave: 'inicio', to: '/', etiqueta: 'menu.dashboard' },
  { clave: 'miembros', to: '/miembros', etiqueta: 'menu.miembros', permisos: ['miembros.ver', 'miembros.ver_asignados', 'miembros.ver_zona', 'miembros.ver_propios'] },
  { clave: 'eventos', to: '/eventos', etiqueta: 'menu.eventos', modulo: 'eventos', permisos: ['eventos.ver'] },
  { clave: 'casas', to: '/casas', etiqueta: 'menu.casas', permisos: ['casas.ver', 'casas.ver_propia', 'casas.ver_zona'] },
  { clave: 'zonas', to: '/zonas', etiqueta: 'menu.zonas', permisos: ['zonas.gestionar', 'casas.ver_zona'] },
  { clave: 'consolidacion', to: '/consolidacion', etiqueta: 'menu.consolidacion', permisos: ['consolidacion.ver', 'consolidacion.ver_asignados', 'consolidacion.ver_casa', 'consolidacion.ver_zona', 'consolidacion.ver_propios'] },
  { clave: 'formacion', to: '/formacion', etiqueta: 'menu.formacion', permisos: ['formacion.ver'] },
  { clave: 'logros', to: '/logros', etiqueta: 'menu.logros', permisos: ['gamificacion.ver', 'gamificacion.gestionar'] },
  { clave: 'comunicacion', to: '/comunicacion', etiqueta: 'menu.comunicacion', modulo: 'comunicacion', permisos: ['comunicacion.ver', 'comunicacion.enviar'] },
  { clave: 'reportes', to: '/reportes', etiqueta: 'menu.reportes', permisos: ['reportes.ver'] },
  { clave: 'configuracion', to: '/configuracion', etiqueta: 'menu.configuracion', permisos: ['usuarios.gestionar', 'roles.gestionar', 'iglesia.configurar'] },
  { clave: 'red', to: '/red', etiqueta: 'menu.red', soloPropietario: true, red: true },
  // Novedades de la plataforma (todas las personas con sesión) y soporte (quien puede configurar la iglesia). Solo se ofrecen si la base ya tiene las tablas (AppLayout)
  { clave: 'novedades', to: '/novedades', etiqueta: 'menu.novedades' },
  { clave: 'soporte', to: '/soporte', etiqueta: 'menu.soporte', permisos: ['iglesia.configurar'], oPropietario: true },
]

export const itemsVisibles = (c: ContextoAcceso) => ITEMS_MENU.filter(i => cumple(i, c))

/** A dónde llega una persona al iniciar sesión */
export const aterrizajeDe = (c: Pick<ContextoAcceso, 'can'>): 'mi-panel' | 'dashboard' => esLiderDeCasa(c) ? 'mi-panel' : 'dashboard'

const deMenu = (clave: string): Requisitos => {
  const { permisos, modulo, soloPropietario, oPropietario, red, soloLiderDeCasa } = ITEMS_MENU.find(i => i.clave === clave)!
  return { permisos, modulo, soloPropietario, oPropietario, red, soloLiderDeCasa }
}

/** Requisitos de cada ruta de la aplicación de iglesia, por nombre de ruta. Una ruta que no está aquí solo pide sesión */
export const REQUISITOS_RUTA: Record<string, Requisitos> = {
  'mi-panel': deMenu('miPanel'),
  miembros: deMenu('miembros'),
  'miembro-detalle': deMenu('miembros'),
  eventos: deMenu('eventos'),
  'evento-detalle': deMenu('eventos'),
  casas: deMenu('casas'),
  zonas: deMenu('zonas'),
  consolidacion: deMenu('consolidacion'),
  formacion: deMenu('formacion'),
  'programas-formacion': { permisos: ['formacion.programas'] },
  logros: deMenu('logros'),
  comunicacion: deMenu('comunicacion'),
  consentimientos: deMenu('comunicacion'),
  reportes: deMenu('reportes'),
  configuracion: deMenu('configuracion'),
  red: deMenu('red'),
  soporte: deMenu('soporte'),
  // Descargar los datos y pedir la baja es del propietario; el propietario de una iglesia suspendida también entra
  'datos-iglesia': { soloPropietario: true },
}
