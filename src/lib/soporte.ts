// Soporte dentro de la aplicación de la iglesia: tickets, novedades y avisos. Reglas puras (las mismas que aplica la base de datos), para avisar antes de enviar y con un
// texto claro, y la lectura de los avisos que llegan a la iglesia.
export const PRIORIDADES = ['baja', 'normal', 'alta', 'urgente'] as const
export type Prioridad = typeof PRIORIDADES[number]
export type EstadoTicket = 'abierto' | 'respondido' | 'cerrado'
export const MAX_ASUNTO = 120
export const MAX_TEXTO = 4000

export interface BorradorTicket { asunto: string; prioridad: string; texto: string }
export type ErroresTicket = Partial<Record<'asunto' | 'prioridad' | 'texto', string>>

/** Devuelve, por campo, la clave de traducción del error (soporte.errores.*). Vacío si el ticket es válido. */
export function validarTicket(b: BorradorTicket): ErroresTicket {
  const e: ErroresTicket = {}
  const asunto = (b.asunto ?? '').trim()
  if (asunto.length < 3) e.asunto = 'soporte.errores.asuntoCorto'
  else if (asunto.length > MAX_ASUNTO) e.asunto = 'soporte.errores.asuntoLargo'
  if (!(PRIORIDADES as readonly string[]).includes(b.prioridad)) e.prioridad = 'soporte.errores.prioridad'
  const texto = (b.texto ?? '').trim()
  if (!texto) e.texto = 'soporte.errores.textoVacio'
  else if (texto.length > MAX_TEXTO) e.texto = 'soporte.errores.textoLargo'
  return e
}

export const validarMensaje = (texto: string): string | null => {
  const t = (texto ?? '').trim()
  return !t ? 'soporte.errores.textoVacio' : t.length > MAX_TEXTO ? 'soporte.errores.textoLargo' : null
}

/** Traduce un error de la base a una clave de traducción (soporte.errores.*). Lo que no se reconoce se muestra genérico. */
export function errorDeSoporte(err: { message?: string; code?: string } | null | undefined): string {
  const t = `${err?.message ?? ''} ${err?.code ?? ''}`
  if (t.includes('ADN_DEMASIADOS_TICKETS')) return 'soporte.errores.demasiados'
  if (t.includes('ADN_TICKET_CERRADO')) return 'soporte.errores.cerrado'
  if (t.includes('ADN_TICKET_LLENO')) return 'soporte.errores.lleno'
  if (t.includes('42501') || t.toLowerCase().includes('row-level security') || t.toLowerCase().includes('permission denied')) return 'soporte.errores.permiso'
  return 'soporte.errores.generico'
}

export interface EntregaAviso {
  aviso_id: string; leido_en: string | null; descartado_en: string | null
  aviso: { id: string; tipo: string; titulo: string; texto: string } | { id: string; tipo: string; titulo: string; texto: string }[] | null
}
const ORDEN_TIPO: Record<string, number> = { alerta: 0, mantenimiento: 1, actualizacion: 2 }

/** Los avisos que se enseñan: los que llegaron, no están descartados y siguen vigentes (la base devuelve null si caducaron o se retiraron). Las alertas primero. */
export function avisosVisibles(filas: EntregaAviso[] | null | undefined) {
  return (filas ?? [])
    .filter(f => !f.descartado_en)
    .map(f => ({ entrega: f, aviso: Array.isArray(f.aviso) ? (f.aviso[0] ?? null) : f.aviso }))
    .filter((x): x is { entrega: EntregaAviso; aviso: NonNullable<typeof x.aviso> } => !!x.aviso)
    .sort((a, b) => (ORDEN_TIPO[a.aviso.tipo] ?? 9) - (ORDEN_TIPO[b.aviso.tipo] ?? 9))
    .map(x => ({ id: x.aviso.id, tipo: x.aviso.tipo, titulo: x.aviso.titulo, texto: x.aviso.texto, leido: !!x.entrega.leido_en }))
}
