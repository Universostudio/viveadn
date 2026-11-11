// Envío de los avisos del sistema por correo (Bird) con los topes aprobados en docs/COSTE-ENVIO.md. Sin dependencias, para probarlo aparte
// con `npm run test:envio`. Este archivo es idéntico en `plataforma` y en `datos-iglesia` (la prueba lo comprueba).
// Reglas: apagado por defecto (ADN_ENVIO_ACTIVO=si lo enciende); solo a direcciones ya registradas; el tope se reserva ANTES de enviar y
// se devuelve si el proveedor no acepta el correo; cualquier fallo se devuelve como resultado, nunca se lanza: un aviso no rompe la operación.

export type TipoEnvio = 'purga' | 'baja' | 'confirmacion'
export type Idioma = 'es' | 'en' | 'fr' | 'pt-BR'
export const IDIOMAS: Idioma[] = ['es', 'en', 'fr', 'pt-BR']

// Topes aprobados por Gerencia. El global depende del plan del proveedor: el gratuito de Bird admite 50 al día, y se queda en 40 para que
// el servicio falle de forma limpia, con margen, y no a medias.
export const TOPE_GLOBAL_GRATUITO = 40
export const TOPE_GLOBAL_PAGO = 5000
export const TOPES = { purgaDia: 1, bajaIglesia: 2, confirmacionIglesia: 200, confirmacionPlataforma: 2000 } as const

export interface ConfigEnvio {
  activo: boolean
  plan: 'gratuito' | 'pago'
  claveBird: string | null
  soporte: string
  topeGlobal: number
}

export function leerConfig(env: (k: string) => string | undefined): ConfigEnvio {
  const plan = env('ADN_ENVIO_PLAN')?.trim().toLowerCase() === 'pago' ? 'pago' : 'gratuito'
  const maximo = plan === 'pago' ? TOPE_GLOBAL_PAGO : TOPE_GLOBAL_GRATUITO
  const pedido = Number(env('ADN_ENVIO_TOPE_GLOBAL'))
  // Una variable solo puede BAJAR el tope, nunca subirlo por encima del máximo del plan
  const topeGlobal = Number.isInteger(pedido) && pedido >= 0 && env('ADN_ENVIO_TOPE_GLOBAL')?.trim() ? Math.min(pedido, maximo) : maximo
  return {
    activo: env('ADN_ENVIO_ACTIVO')?.trim().toLowerCase() === 'si',
    plan,
    claveBird: env('BIRD_API_KEY')?.trim() || null,
    soporte: env('ADN_EMAIL_SOPORTE')?.trim() || 'soporte@viveadn.com',
    topeGlobal,
  }
}

export type ResultadoEnvio =
  | { estado: 'enviado' }
  | { estado: 'apagado' }
  | { estado: 'sin_clave' }
  | { estado: 'destino_no_valido' }
  | { estado: 'tope'; cual: string }
  | { estado: 'fallo' }

export interface Aviso {
  tipo: TipoEnvio
  iglesia: string | null
  destino: string
  /** Verdadero solo si el llamador comprobó que la dirección ya está registrada (perfil del propietario o dirección de alertas configurada) */
  destinoRegistrado: boolean
  asunto: string
  texto: string
  html: string
  idempotencia: string
}

export interface Dependencias {
  config: ConfigEnvio
  reservar: (tipo: TipoEnvio, iglesia: string | null, topeIglesia: number | null, topeTipo: number | null, topeGlobal: number) => Promise<string>
  liberar: (tipo: TipoEnvio, iglesia: string | null) => Promise<void>
  fetchFn: typeof fetch
  log?: (...a: unknown[]) => void
}

const EMAIL_RE = /^[^\s@<>"',;]+@[^\s@<>"',;]+\.[^\s@<>"',;]+$/

function topesDe(tipo: TipoEnvio): { iglesia: number | null; tipo: number | null } {
  if (tipo === 'purga') return { iglesia: null, tipo: TOPES.purgaDia }
  if (tipo === 'baja') return { iglesia: TOPES.bajaIglesia, tipo: null }
  return { iglesia: TOPES.confirmacionIglesia, tipo: TOPES.confirmacionPlataforma }
}

export async function enviarAviso(a: Aviso, d: Dependencias): Promise<ResultadoEnvio> {
  const log = d.log ?? (() => {})
  if (!d.config.activo) return { estado: 'apagado' }
  if (!a.destinoRegistrado || !EMAIL_RE.test(a.destino) || a.destino.length > 254) return { estado: 'destino_no_valido' }
  if (!d.config.claveBird) return { estado: 'sin_clave' }
  const t = topesDe(a.tipo)
  let reserva: string
  try { reserva = await d.reservar(a.tipo, a.iglesia, t.iglesia, t.tipo, d.config.topeGlobal) }
  catch (e) { log('reserva de envio fallida', e instanceof Error ? e.message : e); return { estado: 'fallo' } }  // sin contador no se envía
  if (reserva !== 'ok') return { estado: 'tope', cual: reserva }
  const liberar = async () => { try { await d.liberar(a.tipo, a.iglesia) } catch (e) { log('no se pudo devolver la reserva', e instanceof Error ? e.message : e) } }
  try {
    const region = /^bk_([a-z0-9]+)_/.exec(d.config.claveBird)?.[1] ?? 'eu1'
    const r = await d.fetchFn(`https://${region}.platform.bird.com/v1/email/messages`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${d.config.claveBird}`, 'Content-Type': 'application/json', 'Idempotency-Key': a.idempotencia.slice(0, 200) },
      body: JSON.stringify({
        from: { email: 'no-responder@viveadn.com', name: 'Vive ADN' },
        to: [{ email: a.destino }],
        reply_to: [{ email: d.config.soporte, name: 'Soporte Vive ADN' }],
        subject: a.asunto, html: a.html, text: a.texto,
        category: 'transactional', track_clicks: false, track_opens: false,
      }),
    })
    if (!r.ok) { log('bird', r.status); await liberar(); return { estado: 'fallo' } }
    return { estado: 'enviado' }
  } catch (e) {
    log('bird', e instanceof Error ? e.message : e)
    await liberar()
    return { estado: 'fallo' }
  }
}

const esc = (s: string) => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
const caja = (titulo: string, lineas: string[]) =>
  `<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;color:#1f2937"><h2 style="color:#00523c;margin:0 0 16px">Vive ADN</h2><p><strong>${esc(titulo)}</strong></p>${lineas.map(l => `<p>${esc(l)}</p>`).join('')}</div>`

const TEXTOS_BAJA: Record<Idioma, { pedida: (i: string, f: string) => [string, string[]]; cancelada: (i: string) => [string, string[]]; ayuda: (c: string) => string }> = {
  es: {
    pedida: (i, f) => [`Baja pedida para ${i}`, [`Se ha pedido la baja de ${i}. La cuenta queda suspendida y se borrará por completo el ${f}.`, 'Hasta esa fecha el propietario puede cancelar la baja y descargar todos los datos desde Configuración, pestaña Seguridad, «Datos y baja».', 'Si no fuiste tú, cancela la baja ahora y cambia tu contraseña.']],
    cancelada: i => [`Baja cancelada para ${i}`, [`Se ha cancelado la baja de ${i}. La cuenta vuelve a estar activa y no se borrará nada.`, 'Si no fuiste tú, cambia tu contraseña.']],
    ayuda: c => `Este es un mensaje automático. Para recibir ayuda escribe a ${c}.`,
  },
  en: {
    pedida: (i, f) => [`Cancellation requested for ${i}`, [`Cancellation of ${i} has been requested. The account is suspended and will be deleted completely on ${f}.`, 'Until then the owner can undo the cancellation and download all the data from Settings, Security tab, "Data and cancellation".', 'If it was not you, undo the cancellation now and change your password.']],
    cancelada: i => [`Cancellation undone for ${i}`, [`The cancellation of ${i} has been undone. The account is active again and nothing will be deleted.`, 'If it was not you, change your password.']],
    ayuda: c => `This is an automated message. For help, write to ${c}.`,
  },
  fr: {
    pedida: (i, f) => [`Résiliation demandée pour ${i}`, [`La résiliation de ${i} a été demandée. Le compte est suspendu et sera entièrement supprimé le ${f}.`, 'Jusqu\'à cette date, le propriétaire peut annuler la résiliation et télécharger toutes les données depuis Paramètres, onglet Sécurité, « Données et résiliation ».', 'Si ce n\'était pas vous, annulez la résiliation maintenant et changez votre mot de passe.']],
    cancelada: i => [`Résiliation annulée pour ${i}`, [`La résiliation de ${i} a été annulée. Le compte est de nouveau actif et rien ne sera supprimé.`, 'Si ce n\'était pas vous, changez votre mot de passe.']],
    ayuda: c => `Ceci est un message automatique. Pour obtenir de l'aide, écrivez à ${c}.`,
  },
  'pt-BR': {
    pedida: (i, f) => [`Cancelamento pedido para ${i}`, [`Foi pedido o cancelamento de ${i}. A conta fica suspensa e será apagada por completo em ${f}.`, 'Até essa data o proprietário pode desfazer o cancelamento e baixar todos os dados em Configurações, aba Segurança, «Dados e cancelamento».', 'Se não foi você, desfaça o cancelamento agora e troque sua senha.']],
    cancelada: i => [`Cancelamento desfeito para ${i}`, [`O cancelamento de ${i} foi desfeito. A conta voltou a ficar ativa e nada será apagado.`, 'Se não foi você, troque sua senha.']],
    ayuda: c => `Esta é uma mensagem automática. Para obter ajuda, escreva para ${c}.`,
  },
}

/** Cuerpo del aviso de baja pedida o cancelada. `fecha` ya viene formateada para quien lo lee */
export function avisoBaja(accion: 'pedida' | 'cancelada', o: { idioma: string; iglesia: string; fecha?: string; soporte: string }): { asunto: string; texto: string; html: string } {
  const t = TEXTOS_BAJA[(IDIOMAS as string[]).includes(o.idioma) ? (o.idioma as Idioma) : 'es']
  const [asunto, lineas] = accion === 'pedida' ? t.pedida(o.iglesia, o.fecha ?? '') : t.cancelada(o.iglesia)
  const pie = t.ayuda(o.soporte)
  return { asunto, texto: `${lineas.join('\n\n')}\n\n${pie}`, html: caja(asunto, [...lineas, pie]) }
}

/** Cuerpo de la alerta de purga atrasada: solo cifras, nunca nombres de iglesias ni de personas */
export function avisoPurga(e: { vencidas: number; horas_mas_atrasada: number; en_borrado: number }): { asunto: string; texto: string; html: string } {
  const asunto = 'Vive ADN: la purga programada va atrasada'
  const lineas = [
    `Hay ${e.vencidas} iglesia(s) con el plazo de borrado vencido y la más atrasada espera desde hace ${e.horas_mas_atrasada} horas.`,
    `En borrado suave hay ${e.en_borrado} en total.`,
    'Revisa la tarjeta «Purga programada» del panel de plataforma y la tarea programada (docs/PURGA.md).',
  ]
  return { asunto, texto: lineas.join('\n\n'), html: caja(asunto, lineas) }
}
