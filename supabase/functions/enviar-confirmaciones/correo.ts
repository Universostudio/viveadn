// Correo de confirmación de la suscripción: contenido, enlaces y cabeceras. Sin dependencias, para poder probarlo aparte.
// NO envía nada: solo construye el mensaje. El envío lo hace index.ts, y solo si la doble confirmación está encendida.

export type Idioma = 'es' | 'en' | 'fr' | 'pt-BR'
export const TOKEN_RE = /^[0-9a-f]{64}$/
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const IDIOMAS: Idioma[] = ['es', 'en', 'fr', 'pt-BR']

// Caracteres de control y de formato invisibles: no tienen sitio en un asunto ni en un nombre y permitirían inyectar cabeceras
const RARO_RE = /[\u0000-\u001f\u007f​-‏‪-‮⁠﻿]/g
export const limpiar = (s: string, max = 120) => s.replace(RARO_RE, ' ').replace(/\s+/g, ' ').trim().slice(0, max)
const esc = (s: string) => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))

interface Textos {
  asunto: (i: string) => string; hola: (n: string) => string; cuerpo: (i: string) => string; boton: string
  caduca: (dias: number) => string; noFuiste: string; baja: string; copia: string
}
const TEXTOS: Record<Idioma, Textos> = {
  es: { asunto: i => `Confirma que quieres recibir mensajes de ${i}`, hola: n => `Hola ${n},`,
    cuerpo: i => `Te registraste en ${i} y marcaste que quieres recibir sus mensajes por correo. Para confirmarlo, pulsa el botón.`, boton: 'Confirmar',
    caduca: d => `El enlace funciona una sola vez y caduca en ${d} días.`, noFuiste: 'Si no fuiste tú, ignora este mensaje: no recibirás nada.',
    baja: 'Si no quieres recibir mensajes, puedes darte de baja aquí:', copia: 'Si el botón no funciona, copia este enlace en tu navegador:' },
  en: { asunto: i => `Confirm you want to receive messages from ${i}`, hola: n => `Hello ${n},`,
    cuerpo: i => `You registered with ${i} and chose to receive its messages by email. To confirm, press the button.`, boton: 'Confirm',
    caduca: d => `The link works only once and expires in ${d} days.`, noFuiste: 'If this was not you, ignore this message: you will not receive anything.',
    baja: 'If you do not want to receive messages, you can unsubscribe here:', copia: 'If the button does not work, copy this link into your browser:' },
  fr: { asunto: i => `Confirmez que vous souhaitez recevoir les messages de ${i}`, hola: n => `Bonjour ${n},`,
    cuerpo: i => `Vous vous êtes enregistré auprès de ${i} et avez choisi de recevoir ses messages par e-mail. Pour confirmer, cliquez sur le bouton.`, boton: 'Confirmer',
    caduca: d => `Le lien ne fonctionne qu'une seule fois et expire dans ${d} jours.`, noFuiste: "Si ce n'était pas vous, ignorez ce message : vous ne recevrez rien.",
    baja: 'Si vous ne souhaitez pas recevoir de messages, vous pouvez vous désinscrire ici :', copia: 'Si le bouton ne fonctionne pas, copiez ce lien dans votre navigateur :' },
  'pt-BR': { asunto: i => `Confirme que você quer receber mensagens de ${i}`, hola: n => `Olá ${n},`,
    cuerpo: i => `Você se registrou em ${i} e marcou que quer receber as mensagens por e-mail. Para confirmar, clique no botão.`, boton: 'Confirmar',
    caduca: d => `O link funciona uma única vez e expira em ${d} dias.`, noFuiste: 'Se não foi você, ignore esta mensagem: você não receberá nada.',
    baja: 'Se não quiser receber mensagens, você pode cancelar aqui:', copia: 'Se o botão não funcionar, copie este link para o seu navegador:' },
}

export interface DatosCorreo {
  destino: string; nombre: string; iglesia: string; idioma: string | null; token: string; bajaToken: string
  /** Dirección de la web (https, sin ruta), por ejemplo la de producción */
  web: string
  /** Dirección de las funciones de borde (https, sin ruta final) */
  funciones: string
  dias: number
}
export interface Correo { asunto: string; texto: string; html: string; cabeceras: Record<string, string>; enlaces: { confirmar: string; baja: string; bajaUnClic: string } }

const origenHttps = (u: string) => {
  try { const x = new URL(u); return x.protocol === 'https:' && !x.username && !x.password && x.pathname.replace(/\/+$/, '') === '' && !x.search ? x.origin : null } catch { return null }
}

export function construirCorreo(d: DatosCorreo): Correo {
  if (!EMAIL_RE.test(d.destino) || d.destino.length > 254) throw new Error('destino')
  if (!TOKEN_RE.test(d.token) || !TOKEN_RE.test(d.bajaToken) || d.token === d.bajaToken) throw new Error('secreto')
  const web = origenHttps(d.web); const funciones = origenHttps(d.funciones)
  if (!web || !funciones) throw new Error('direccion')
  if (!Number.isInteger(d.dias) || d.dias < 1 || d.dias > 14) throw new Error('dias')
  const t = TEXTOS[IDIOMAS.includes(d.idioma as Idioma) ? (d.idioma as Idioma) : 'es']
  const iglesia = limpiar(d.iglesia) || 'Vive ADN'
  const nombre = limpiar(d.nombre, 60)
  const enlaces = {
    confirmar: `${web}/confirmar/${d.token}`,
    baja: `${web}/baja/${d.bajaToken}`,
    bajaUnClic: `${funciones}/functions/v1/baja?t=${d.bajaToken}`,
  }
  const texto = `${t.hola(nombre)}\n\n${t.cuerpo(iglesia)}\n\n${enlaces.confirmar}\n\n${t.caduca(d.dias)}\n${t.noFuiste}\n\n${t.baja}\n${enlaces.baja}\n`
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;color:#1f2937">
<h2 style="color:#00523c;margin:0 0 16px">Vive ADN</h2>
<p>${esc(t.hola(nombre))}</p>
<p>${esc(t.cuerpo(iglesia))}</p>
<p style="margin:24px 0"><a href="${esc(enlaces.confirmar)}" style="background:#00523c;color:#ffffff;padding:12px 22px;border-radius:8px;text-decoration:none;font-weight:bold">${esc(t.boton)}</a></p>
<p style="font-size:13px;color:#4b5563">${esc(t.caduca(d.dias))}</p>
<p style="font-size:12px;color:#6b7280">${esc(t.copia)}<br><span style="word-break:break-all">${esc(enlaces.confirmar)}</span></p>
<p style="font-size:12px;color:#6b7280">${esc(t.noFuiste)}</p>
<hr style="border:none;border-top:1px solid #e5e7eb;margin:20px 0">
<p style="font-size:12px;color:#6b7280">${esc(t.baja)} <a href="${esc(enlaces.baja)}">${esc(enlaces.baja)}</a></p></div>`
  return {
    asunto: t.asunto(iglesia), texto, html, enlaces,
    // Baja de un clic (RFC 8058): el programa de correo hace un POST directo a la función, sin pasar por la página
    cabeceras: { 'List-Unsubscribe': `<${enlaces.bajaUnClic}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' },
  }
}

// Compara la clave de la tarea programada con la esperada, en tiempo constante. Sin clave configurada, la vía queda cerrada.
export async function claveCronValida(recibida: string | null, esperada: string | undefined): Promise<boolean> {
  if (!recibida || !esperada || esperada.length < 32) return false
  const huella = async (t: string) => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(t)))
  const [a, b] = await Promise.all([huella(recibida), huella(esperada)])
  let dif = 0
  for (let i = 0; i < a.length; i++) dif |= a[i]! ^ b[i]!
  return dif === 0
}
