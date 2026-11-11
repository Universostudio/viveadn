import { createClient } from 'npm:@supabase/supabase-js@2'

// Invitaciones de acceso: un solo uso, caducan a los 15 dias.
// En la base solo se guarda la huella SHA-256 del enlace. El enlace completo solo se muestra
// una vez, a quien invita. Acciones con sesion: crear, reenviar, revocar. Publicas: consultar, aceptar.

// Entornos de prueba: ADN_ORIGENES_EXTRA añade direcciones de la web (https exactas, separadas por comas, hasta 10). En producción no se define.
const ORIGENES_EXTRA = (Deno.env.get('ADN_ORIGENES_EXTRA') ?? '').split(',').map(s => s.trim()).filter(s => /^https:\/\/[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:\d{1,5})?$/.test(s)).slice(0, 10)
const ORIGENES_INVITACION = ['https://viveadn.com', 'https://www.viveadn.com', 'https://viveadn-web-app.vercel.app', ...ORIGENES_EXTRA]
const ORIGENES_PERMITIDOS = [...ORIGENES_INVITACION, 'http://localhost:5173']

const corsPara = (req: Request) => {
  const origen = req.headers.get('Origin') ?? ''
  return {
    'Access-Control-Allow-Origin': ORIGENES_PERMITIDOS.includes(origen) ? origen : ORIGENES_PERMITIDOS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const TOKEN_RE = /^[A-Za-z0-9_-]{43}$/
const texto = (v: unknown, max: number) => String(v ?? '').trim().slice(0, max)

const nuevoToken = () => {
  const b = crypto.getRandomValues(new Uint8Array(32))
  return btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}
const huella = async (t: string) => {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(t))
  return [...new Uint8Array(d)].map(x => x.toString(16).padStart(2, '0')).join('')
}

// ---------- Correo de invitacion (Bird) ----------
// Correo de soporte que ve quien recibe una invitación: se configura con ADN_EMAIL_SOPORTE. El valor de reserva es el que
// ya usaba la función; Gerencia confirma el definitivo.
const SOPORTE = Deno.env.get('ADN_EMAIL_SOPORTE')?.trim() || 'soporte@viveadn.com'
type Idioma = 'es' | 'en' | 'fr' | 'pt-BR'
const IDIOMAS: Idioma[] = ['es', 'en', 'fr', 'pt-BR']
const TEXTOS: Record<Idioma, { asunto: (i: string) => string; hola: (n: string) => string; cuerpo: (q: string, i: string, r: string) => string; boton: string; caduca: string; ignora: string; copia: string; spam: string; auto: (c: string) => string }> = {
  es: { asunto: i => `Te han invitado a ${i} en Vive ADN`, hola: n => `Hola ${n},`, cuerpo: (q, i, r) => `${q} te ha invitado a unirte a ${i} en Vive ADN con el rol de ${r}.`, boton: 'Aceptar la invitacion', caduca: 'El enlace caduca en 15 dias y solo se puede usar una vez.', ignora: 'Si no esperabas este correo, puedes ignorarlo.', copia: 'Si el boton no funciona, copia este enlace en tu navegador:', spam: 'Si no ves este correo en tu bandeja de entrada, revisa la carpeta de spam y marcalo como "No es spam".', auto: c => `Este es un mensaje automatico. Para recibir ayuda escribe a ${c}.` },
  en: { asunto: i => `You have been invited to ${i} on Vive ADN`, hola: n => `Hello ${n},`, cuerpo: (q, i, r) => `${q} has invited you to join ${i} on Vive ADN as ${r}.`, boton: 'Accept the invitation', caduca: 'The link expires in 15 days and can only be used once.', ignora: 'If you were not expecting this email, you can ignore it.', copia: 'If the button does not work, copy this link into your browser:', spam: 'If you cannot find this email in your inbox, check your spam folder and mark it as "Not spam".', auto: c => `This is an automated message. For help, write to ${c}.` },
  fr: { asunto: i => `Vous etes invite a rejoindre ${i} sur Vive ADN`, hola: n => `Bonjour ${n},`, cuerpo: (q, i, r) => `${q} vous invite a rejoindre ${i} sur Vive ADN avec le role de ${r}.`, boton: "Accepter l'invitation", caduca: 'Le lien expire dans 15 jours et ne peut etre utilise qu une seule fois.', ignora: "Si vous n'attendiez pas ce message, vous pouvez l'ignorer.", copia: 'Si le bouton ne fonctionne pas, copiez ce lien dans votre navigateur :', spam: 'Si vous ne trouvez pas cet e-mail dans votre boite de reception, verifiez vos courriers indesirables et marquez-le comme "Non spam".', auto: c => `Ceci est un message automatique. Pour obtenir de l'aide, ecrivez a ${c}.` },
  'pt-BR': { asunto: i => `Voce foi convidado para ${i} no Vive ADN`, hola: n => `Ola ${n},`, cuerpo: (q, i, r) => `${q} convidou voce para participar de ${i} no Vive ADN com a funcao de ${r}.`, boton: 'Aceitar o convite', caduca: 'O link expira em 15 dias e so pode ser usado uma vez.', ignora: 'Se voce nao esperava este e-mail, pode ignora-lo.', copia: 'Se o botao nao funcionar, copie este link no navegador:', spam: 'Se voce nao encontrar este e-mail na caixa de entrada, verifique a pasta de spam e marque como "Nao e spam".', auto: c => `Esta e uma mensagem automatica. Para obter ajuda, escreva para ${c}.` },
}
const esc = (s: string) => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))

// Devuelve true solo si Bird acepta el mensaje. Cualquier fallo devuelve false y el enlace se copia a mano.
async function enviarCorreo(p: { para: string; nombre: string; quien: string; iglesia: string; rol: string; enlace: string; idioma: Idioma; idInvitacion: string }) {
  const clave = Deno.env.get('BIRD_API_KEY')
  if (!clave) return false
  const region = /^bk_([a-z0-9]+)_/.exec(clave)?.[1] ?? 'eu1'
  const t = TEXTOS[p.idioma]
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;color:#1f2937">
<h2 style="color:#00523c;margin:0 0 16px">Vive ADN</h2>
<p>${esc(t.hola(p.nombre))}</p>
<p>${esc(t.cuerpo(p.quien, p.iglesia, p.rol))}</p>
<p style="margin:24px 0"><a href="${esc(p.enlace)}" style="background:#00523c;color:#ffffff;padding:12px 22px;border-radius:8px;text-decoration:none;font-weight:bold">${esc(t.boton)}</a></p>
<p style="font-size:13px;color:#4b5563">${esc(t.caduca)}</p>
<p style="font-size:12px;color:#6b7280">${esc(t.copia)}<br><span style="word-break:break-all">${esc(p.enlace)}</span></p>
<p style="font-size:12px;color:#6b7280">${esc(t.ignora)}</p>
<p style="font-size:12px;color:#6b7280">${esc(t.spam)}</p>
<hr style="border:none;border-top:1px solid #e5e7eb;margin:20px 0"><p style="font-size:11px;color:#9ca3af">${esc(t.auto(SOPORTE))}</p></div>`
  const texto = `${t.hola(p.nombre)}\n\n${t.cuerpo(p.quien, p.iglesia, p.rol)}\n\n${p.enlace}\n\n${t.caduca}\n${t.ignora}\n${t.spam}\n\n${t.auto(SOPORTE)}`
  try {
    const r = await fetch(`https://${region}.platform.bird.com/v1/email/messages`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${clave}`, 'Content-Type': 'application/json', 'Idempotency-Key': `invitacion/${p.idInvitacion}` },
      body: JSON.stringify({
        from: { email: 'no-responder@viveadn.com', name: 'Vive ADN' },
        to: [{ email: p.para, name: p.nombre }],
        reply_to: [{ email: SOPORTE, name: 'Soporte Vive ADN' }],
        subject: t.asunto(p.iglesia), html, text: texto,
        category: 'transactional', track_clicks: false, track_opens: false,
      }),
    })
    if (!r.ok) { console.error('bird', r.status, (await r.text()).slice(0, 300)); return false }
    return true
  } catch (e) { console.error('bird', e instanceof Error ? e.message : e); return false }
}

const DEBILES =['1234', '12345', '123456', 'password', 'contrasena', 'viveadn', 'qwerty']
function claveValida(p: string, email: string) {
  if (p.length < 10 || p.length > 72) return 'La contrasena debe tener entre 10 y 72 caracteres'
  const baja = p.toLowerCase()
  if (DEBILES.some(d => baja.includes(d))) return 'Esa contrasena es demasiado facil de adivinar'
  const local = email.split('@')[0]
  if (local.length >= 4 && baja.includes(local)) return 'La contrasena no puede contener tu correo'
  if (/^(.)\1+$/.test(p)) return 'La contrasena no puede repetir un solo caracter'
  return null
}

Deno.serve(async (req) => {
  const cors = corsPara(req)
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405)

  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } })
    const body = await req.json().catch(() => ({}))
    const origenCrudo = req.headers.get('Origin') ?? ''
    const origen = ORIGENES_INVITACION.includes(origenCrudo) ? origenCrudo : ORIGENES_INVITACION[0]

    // ---------- Acciones publicas (se identifican con el enlace) ----------
    if (body.accion === 'consultar' || body.accion === 'aceptar') {
      const token = texto(body.token, 64)
      // Respuesta uniforme: no se distingue inexistente, caducada, usada o revocada
      const invalida = () => json({ error: 'Esta invitacion no es valida o ha caducado. Pide una nueva a quien te invito.' }, 410)
      if (!TOKEN_RE.test(token)) return invalida()
      const h = await huella(token)

      if (body.accion === 'consultar') {
        const { data } = await admin.from('invitaciones')
          .select('nombre, rol, iglesia_id')
          .eq('token_hash', h).is('usada_en', null).is('revocada_en', null).gt('caduca_en', new Date().toISOString()).maybeSingle()
        if (!data) return invalida()
        const [{ data: ig }, { data: rl }] = await Promise.all([
          admin.from('iglesias').select('nombre').eq('id', data.iglesia_id).maybeSingle(),
          admin.from('roles').select('nombre').eq('iglesia_id', data.iglesia_id).eq('clave', data.rol).maybeSingle(),
        ])
        return json({ nombre: data.nombre, iglesia: ig?.nombre ?? '', rol: rl?.nombre ?? data.rol })
      }

      const clave = String(body.password ?? '')
      const { data: filas, error: eRec } = await admin.rpc('reclamar_invitacion', { p_hash: h })
      if (eRec) { console.error('reclamar', eRec.message); return json({ error: 'No se pudo aceptar la invitacion' }, 500) }
      const inv = Array.isArray(filas) ? filas[0] : filas
      if (!inv) return invalida()

      const liberar = async () => { await admin.rpc('liberar_invitacion', { p_id: inv.id }) }
      const errClave = claveValida(clave, inv.email)
      if (errClave) { await liberar(); return json({ error: errClave }, 400) }

      const { data: creado, error: eUser } = await admin.auth.admin.createUser({
        email: inv.email, password: clave, email_confirm: true,
        user_metadata: { nombre: inv.nombre, apellido: inv.apellido },
      })
      if (eUser || !creado?.user) {
        await liberar()
        const existe = /already|registered|exists/i.test(eUser?.message ?? '')
        return json({ error: existe ? 'Ese correo ya tiene una cuenta en la plataforma' : (eUser?.message?.includes('pwned') || eUser?.message?.includes('weak') ? 'Esa contrasena es demasiado facil de adivinar' : 'No se pudo crear la cuenta') }, existe ? 409 : 400)
      }
      const { error: ePerfil } = await admin.from('perfiles').insert({
        id: creado.user.id, iglesia_id: inv.iglesia_id, nombre: inv.nombre, apellido: inv.apellido, email: inv.email, rol: inv.rol,
      })
      if (ePerfil) {
        await admin.auth.admin.deleteUser(creado.user.id)
        await liberar()
        if (/PLAN_LIMITE/.test(ePerfil.message ?? '')) return json({ error: 'Esta iglesia ha alcanzado el limite de usuarios de su plan. Avisa a quien te invito.' }, 409)
        return json({ error: 'No se pudo crear el perfil' }, 500)
      }
      return json({ ok: true, email: inv.email })
    }

    // ---------- Acciones con sesion ----------
    const userClient = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } })
    const { data: { user } } = await userClient.auth.getUser()
    if (!user) return json({ error: 'No autenticado' }, 401)

    const idioma: Idioma = IDIOMAS.includes(body.idioma) ? body.idioma : 'es'
    const { data: yo } = await admin.from('perfiles').select('id, iglesia_id, rol, activo, nombre, apellido').eq('id', user.id).maybeSingle()
    if (!yo || !yo.activo || !yo.iglesia_id) return json({ error: 'Sin permiso' }, 403)
    const { data: miRol } = await admin.from('roles').select('es_propietario, rol_permisos(permiso)')
      .eq('iglesia_id', yo.iglesia_id).eq('clave', yo.rol).maybeSingle()
    // deno-lint-ignore no-explicit-any
    const puede = !!miRol && ((miRol as any).es_propietario || ((miRol as any).rol_permisos ?? []).some((p: any) => p.permiso === 'usuarios.gestionar'))
    if (!puede) return json({ error: 'Sin permiso' }, 403)
    const soySuper = !!miRol && (miRol as any).es_propietario === true // deno-lint-ignore no-explicit-any

    const crearEnlace = async (i: { email: string; nombre: string; apellido: string; rol: string }) => {
      const token = nuevoToken()
      const { data, error } = await admin.from('invitaciones').insert({
        iglesia_id: yo.iglesia_id, email: i.email, nombre: i.nombre, apellido: i.apellido, rol: i.rol,
        token_hash: await huella(token), creada_por: yo.id,
      }).select('id, caduca_en').single()
      if (error || !data) return { error }
      return { id: data.id, caduca_en: data.caduca_en, enlace: `${origen}/aceptar#t=${token}` }
    }

    const mandar = async (i: { email: string; nombre: string; rol: string }, r: { id: string; enlace: string }) => {
      const [{ data: ig }, { data: rl }] = await Promise.all([
        admin.from('iglesias').select('nombre').eq('id', yo.iglesia_id).maybeSingle(),
        admin.from('roles').select('nombre').eq('iglesia_id', yo.iglesia_id).eq('clave', i.rol).maybeSingle(),
      ])
      return await enviarCorreo({
        para: i.email, nombre: i.nombre, quien: `${yo.nombre ?? ''} ${yo.apellido ?? ''}`.trim() || 'Vive ADN',
        iglesia: ig?.nombre ?? 'Vive ADN', rol: rl?.nombre ?? i.rol, enlace: r.enlace, idioma, idInvitacion: r.id,
      })
    }

    switch (body.accion) {
      case 'crear': {
        const email = texto(body.email, 254).toLowerCase()
        const nombre = texto(body.nombre, 60)
        const apellido = texto(body.apellido, 60)
        const rol = texto(body.rol, 40)
        if (!EMAIL_RE.test(email)) return json({ error: 'El correo no es valido' }, 400)
        if (!nombre || !apellido) return json({ error: 'Faltan el nombre y el apellido' }, 400)
        const { data: rolOk } = await admin.from('roles').select('clave, es_propietario').eq('iglesia_id', yo.iglesia_id).eq('clave', rol).maybeSingle()
        if (!rolOk) return json({ error: 'Ese rol no existe en tu iglesia' }, 400)
        if (rolOk.es_propietario && !soySuper) return json({ error: 'Solo un superadministrador puede invitar a otro' }, 403)
        const { data: yaTiene } = await admin.from('perfiles').select('id').eq('email', email).maybeSingle()
        if (yaTiene) return json({ error: 'Ese correo ya tiene una cuenta en la plataforma' }, 409)
        // Sustituye cualquier invitacion pendiente anterior para ese correo
        await admin.from('invitaciones').update({ revocada_en: new Date().toISOString() })
          .eq('iglesia_id', yo.iglesia_id).eq('email', email).is('usada_en', null).is('revocada_en', null)
        const r = await crearEnlace({ email, nombre, apellido, rol })
        if ('error' in r) {
          if (/PLAN_LIMITE/.test(r.error?.message ?? '')) return json({ error: 'Has alcanzado el limite de usuarios de tu plan. Quita un usuario o una invitacion pendiente, o cambia de plan.' }, 409)
          console.error('crear', r.error?.message); return json({ error: 'No se pudo crear la invitacion' }, 500)
        }
        const enviado = await mandar({ email, nombre, rol }, r)
        return json({ ok: true, ...r, enviado })
      }
      case 'reenviar': {
        if (typeof body.id !== 'string' || !UUID_RE.test(body.id)) return json({ error: 'Invitacion no valida' }, 400)
        const { data: vieja } = await admin.from('invitaciones').select('email, nombre, apellido, rol, usada_en, revocada_en')
          .eq('id', body.id).eq('iglesia_id', yo.iglesia_id).maybeSingle()
        if (!vieja || vieja.usada_en) return json({ error: 'Invitacion no valida' }, 404)
        const { data: rolV } = await admin.from('roles').select('es_propietario').eq('iglesia_id', yo.iglesia_id).eq('clave', vieja.rol).maybeSingle()
        if (rolV?.es_propietario && !soySuper) return json({ error: 'Solo un superadministrador puede invitar a otro' }, 403)
        await admin.from('invitaciones').update({ revocada_en: new Date().toISOString() }).eq('id', body.id).is('revocada_en', null)
        const r = await crearEnlace(vieja)
        if ('error' in r) {
          if (/PLAN_LIMITE/.test(r.error?.message ?? '')) return json({ error: 'Has alcanzado el limite de usuarios de tu plan. Quita un usuario o una invitacion pendiente, o cambia de plan.' }, 409)
          return json({ error: 'No se pudo crear la invitacion' }, 500)
        }
        const enviado = await mandar(vieja, r)
        return json({ ok: true, ...r, enviado })
      }
      case 'revocar': {
        if (typeof body.id !== 'string' || !UUID_RE.test(body.id)) return json({ error: 'Invitacion no valida' }, 400)
        const { data, error } = await admin.from('invitaciones').update({ revocada_en: new Date().toISOString() })
          .eq('id', body.id).eq('iglesia_id', yo.iglesia_id).is('usada_en', null).is('revocada_en', null).select('id')
        if (error) return json({ error: 'No se pudo revocar' }, 500)
        return json({ ok: (data ?? []).length === 1 })
      }
      default:
        return json({ error: 'Accion desconocida' }, 400)
    }
  } catch (e) {
    console.error('invitaciones', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
