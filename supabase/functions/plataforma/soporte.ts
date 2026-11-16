// Soporte de la plataforma: validación de lo que escribe quien opera la plataforma y forma de lo que se le devuelve. Funciones puras, sin red ni base,
// para probarlas con `npm run test:soporte-funcion`. La lista de tickets lleva cifras y asunto; el texto solo sale al abrir un ticket concreto.

export const PRIORIDADES = ['baja', 'normal', 'alta', 'urgente'] as const
export const TIPOS_AVISO = ['actualizacion', 'mantenimiento', 'alerta'] as const
export const ESTADOS_TICKET = ['abierto', 'respondido', 'cerrado'] as const
export const ETAPAS = ['onboarding', 'prueba', 'activa', 'receso', 'suspendida']
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const texto = (v: unknown, max: number) => String(v ?? '').trim().slice(0, max)
export const esUuid = (v: unknown): v is string => typeof v === 'string' && UUID_RE.test(v)

export type Validado<T> = ({ ok: true } & T) | { ok: false; error: string }

export function validarRespuesta(body: Record<string, unknown>): Validado<{ id: string; texto: string }> {
  if (!esUuid(body.id)) return { ok: false, error: 'Identificador de ticket no valido' }
  const t = texto(body.texto, 4000)
  if (!t) return { ok: false, error: 'Escribe la respuesta' }
  return { ok: true, id: body.id, texto: t }
}

export function validarNovedad(body: Record<string, unknown>): Validado<{ version: string; titulo: string; texto: string }> {
  const version = texto(body.version, 30), titulo = texto(body.titulo, 120), t = texto(body.texto, 4000)
  if (!version) return { ok: false, error: 'Falta la version' }
  if (titulo.length < 3) return { ok: false, error: 'El titulo necesita al menos 3 letras' }
  if (!t) return { ok: false, error: 'Falta el texto de la novedad' }
  return { ok: true, version, titulo, texto: t }
}

export interface AvisoValidado {
  tipo: typeof TIPOS_AVISO[number]; titulo: string; texto: string
  destino: { todas?: true; planes?: string[]; estados?: string[] }
  incluir_demo: boolean; desde: string; hasta: string | null; por_correo: boolean
}

export function validarAviso(body: Record<string, unknown>, ahora = Date.now()): Validado<{ aviso: AvisoValidado }> {
  if (!(TIPOS_AVISO as readonly string[]).includes(String(body.tipo))) return { ok: false, error: 'Tipo de aviso no valido' }
  const titulo = texto(body.titulo, 120), t = texto(body.texto, 2000)
  if (titulo.length < 3) return { ok: false, error: 'El titulo necesita al menos 3 letras' }
  if (!t) return { ok: false, error: 'Falta el texto del aviso' }
  const d = (body.destino ?? {}) as Record<string, unknown>
  const destino: AvisoValidado['destino'] = {}
  if (d.todas === true) destino.todas = true
  else {
    if (d.planes !== undefined) {
      if (!Array.isArray(d.planes) || d.planes.length < 1 || d.planes.length > 20 || d.planes.some(p => typeof p !== 'string' || !/^[a-z0-9_-]{1,40}$/.test(p))) return { ok: false, error: 'Planes de destino no validos' }
      destino.planes = [...new Set(d.planes as string[])]
    }
    if (d.estados !== undefined) {
      if (!Array.isArray(d.estados) || d.estados.length < 1 || d.estados.some(e => !ETAPAS.includes(String(e)))) return { ok: false, error: 'Estados de destino no validos' }
      destino.estados = [...new Set(d.estados as string[])]
    }
    if (!destino.planes && !destino.estados) return { ok: false, error: 'Elige a quien va dirigido el aviso' }
  }
  let hasta: string | null = null
  if (body.hasta !== undefined && body.hasta !== null && body.hasta !== '') {
    const h = new Date(String(body.hasta))
    if (Number.isNaN(h.getTime())) return { ok: false, error: 'La fecha de fin no es valida' }
    if (h.getTime() <= ahora) return { ok: false, error: 'La fecha de fin ya paso' }
    hasta = h.toISOString()
  }
  return { ok: true, aviso: { tipo: body.tipo as AvisoValidado['tipo'], titulo, texto: t, destino, incluir_demo: body.incluir_demo === true, desde: new Date(ahora).toISOString(), hasta, por_correo: body.por_correo === true } }
}

/** Qué se anota del correo de un aviso: el correo masivo no se envía; solo se registra si se pidió y si el interruptor general está apagado */
export function correoDeAviso(porCorreo: boolean, envioActivo: boolean): 'no_pedido' | 'apagado' | 'pendiente' {
  if (!porCorreo) return 'no_pedido'
  return envioActivo ? 'pendiente' : 'apagado'
}

export interface FilaTicket {
  id: string; iglesia_id: string; asunto: string; prioridad: string; estado: string; created_at: string; updated_at: string; cerrado_en: string | null
  iglesias?: { nombre?: string } | { nombre?: string }[] | null; mensajes?: { count?: number }[] | null
}

const unico = <T,>(v: T | T[] | null | undefined): T | null => Array.isArray(v) ? (v[0] ?? null) : (v ?? null)

/** La lista de tickets que ve la plataforma: iglesia, asunto, prioridad, estado, fechas y número de mensajes. Nunca el texto. */
export function listaDeTickets(filas: FilaTicket[] | null | undefined) {
  return (filas ?? []).map(f => ({
    id: f.id, iglesia_id: f.iglesia_id, iglesia: unico(f.iglesias)?.nombre ?? null, asunto: f.asunto, prioridad: f.prioridad, estado: f.estado,
    creado: f.created_at, actualizado: f.updated_at, cerrado: f.cerrado_en, mensajes: Number(unico(f.mensajes)?.count) || 0,
  }))
}

export interface FilaMensaje { id: number | string; autor_tipo: string; texto: string; created_at: string }
/** Un ticket abierto por la plataforma: su conversación completa, sin identificadores de personas */
export function ticketAbierto(t: FilaTicket, mensajes: FilaMensaje[] | null | undefined) {
  return {
    ...listaDeTickets([t])[0],
    conversacion: (mensajes ?? []).map(m => ({ id: Number(m.id), de: m.autor_tipo === 'plataforma' ? 'plataforma' : 'iglesia', texto: m.texto, fecha: m.created_at })),
  }
}

/** Cifras de soporte para la portada del soporte y el contador del menú */
export function resumenDeSoporte(tickets: { estado: string; prioridad: string }[] | null, novedades: { version: string; publicada_en: string }[] | null,
  avisos: { id: string }[] | null, entregas: { aviso_id: string; leido_en: string | null; descartado_en: string | null }[] | null) {
  const t = tickets ?? []
  const porEstado = (e: string) => t.filter(x => x.estado === e).length
  const nov = novedades ?? []
  const ent = entregas ?? []
  return {
    tickets: { abiertos: porEstado('abierto'), respondidos: porEstado('respondido'), cerrados: porEstado('cerrado'), urgentes: t.filter(x => x.estado !== 'cerrado' && x.prioridad === 'urgente').length },
    novedades: { total: nov.length, ultima: nov.length ? { version: nov[0].version, publicada_en: nov[0].publicada_en } : null },
    avisos: { vigentes: (avisos ?? []).length, entregas: ent.length, leidos: ent.filter(e => e.leido_en).length, descartados: ent.filter(e => e.descartado_en).length },
  }
}

/** Registro de entrega, lectura y descarte de cada aviso */
export function estadisticasDeAvisos(entregas: { aviso_id: string; leido_en: string | null; descartado_en: string | null }[] | null | undefined) {
  const porAviso: Record<string, { entregas: number; leidos: number; descartados: number }> = {}
  for (const e of entregas ?? []) {
    const f = (porAviso[e.aviso_id] ??= { entregas: 0, leidos: 0, descartados: 0 })
    f.entregas++; if (e.leido_en) f.leidos++; if (e.descartado_en) f.descartados++
  }
  return porAviso
}
