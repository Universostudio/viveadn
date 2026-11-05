import { createClient } from 'npm:@supabase/supabase-js@2'
import { validarRegistro, respuestaDeError } from './validar.ts'

// Registro de iglesias por su cuenta (/registro). Es publica: no hay sesion.
// Crea la iglesia y su superadministrador y le envia un correo para que cree su contrasena, de modo que
// el correo queda comprobado. En la etapa de pruebas exige un codigo de acceso (ver plataforma_ajustes).
// Un correo que ya tiene cuenta recibe la misma respuesta que uno nuevo, para no revelar quien existe.

const ORIGENES_INVITACION = ['https://viveadn.com', 'https://www.viveadn.com', 'https://viveadn-web-app.vercel.app']
const ORIGENES_PERMITIDOS = [...ORIGENES_INVITACION, 'http://localhost:5173']
const MAX_CUERPO = 4096
const MAX_INTENTOS = 5     // por dispositivo
const VENTANA_MIN = 60

const corsPara = (req: Request) => {
  const origen = req.headers.get('Origin') ?? ''
  return {
    'Access-Control-Allow-Origin': ORIGENES_PERMITIDOS.includes(origen) ? origen : ORIGENES_PERMITIDOS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

const hex = (buf: ArrayBuffer) => [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('')
const sha256 = async (t: string) => hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(t)))
// Huella de la IP: HMAC con una clave que nunca sale del servidor, para que no se pueda deshacer
async function huellaIp(ip: string, clave: string) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(`registro-ip:${clave}`), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return hex(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(ip)))
}

Deno.serve(async (req) => {
  const cors = corsPara(req)
  const json = (cuerpo: unknown, status = 200) =>
    new Response(JSON.stringify(cuerpo), { status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405)

  try {
    const bruto = await req.text()
    if (bruto.length > MAX_CUERPO) return json({ error: 'datos' }, 413)
    let b: Record<string, unknown> = {}
    try { b = JSON.parse(bruto) } catch { return json({ error: 'datos' }, 400) }
    if (typeof b !== 'object' || b === null || Array.isArray(b)) return json({ error: 'datos' }, 400)

    const servicio = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, servicio, { auth: { persistSession: false, autoRefreshToken: false } })

    const { data: ajustes } = await admin.from('plataforma_ajustes').select('clave, valor').in('clave', ['registro_abierto', 'registro_requiere_codigo'])
    const ajuste = (c: string, defecto: boolean) => { const v = (ajustes ?? []).find(a => a.clave === c)?.valor; return typeof v === 'boolean' ? v : defecto }
    const abierto = ajuste('registro_abierto', false)       // si falta el ajuste, se queda cerrado
    const requiereCodigo = ajuste('registro_requiere_codigo', true)

    // La pagina pregunta que campos mostrar
    if (b.accion === 'consultar') return json({ abierto, requiere_codigo: requiereCodigo })
    if (b.accion !== 'registrar') return json({ error: 'datos' }, 400)
    if (!abierto) return json(respuestaDeError('cerrado').cuerpo, 403)

    const v = validarRegistro(b, requiereCodigo)
    // Un robot recibe un exito falso y no se guarda nada
    if (!v.ok && v.error === 'bot') return json({ ok: true })

    // Cada intento cuenta, tambien los fallidos, para que no se pueda adivinar un codigo
    const ip = req.headers.get('cf-connecting-ip') ?? req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'desconocida'
    const ipHash = await huellaIp(ip, servicio)
    const { data: dentro, error: eLimite } = await admin.rpc('registrar_intento_registro', { p_ip_hash: ipHash, p_max: MAX_INTENTOS, p_minutos: VENTANA_MIN })
    if (eLimite) { console.error('limite', eLimite.message); return json({ error: 'interno' }, 500) }
    if (dentro !== true) { const r = respuestaDeError('limite'); return json(r.cuerpo, r.status) }

    if (!v.ok) { const r = respuestaDeError(v.error); return json(r.cuerpo, r.status) }
    const { iglesia, propietario, codigo } = v.datos

    // Codigo de acceso: se usa de forma atomica y se devuelve si el alta no se completa
    let codigoId: string | null = null
    if (requiereCodigo) {
      const { data: id, error } = await admin.rpc('consumir_codigo_registro', { p_hash: await sha256(codigo) })
      if (error) { console.error('codigo', error.message); return json({ error: 'interno' }, 500) }
      if (!id) { const r = respuestaDeError('codigo'); return json(r.cuerpo, r.status) }
      codigoId = id as string
    }
    const devolverCodigo = async () => {
      if (codigoId) { const { error } = await admin.rpc('devolver_codigo_registro', { p_id: codigoId }); if (error) console.error('no se pudo devolver el codigo', codigoId, error.message) }
    }
    const fallo = async (e: string) => { await devolverCodigo(); const r = respuestaDeError(e); return json(r.cuerpo, r.status) }

    const { data: planOk } = await admin.from('planes').select('clave').eq('clave', 'semilla').eq('activo', true).maybeSingle()
    if (!planOk) { await devolverCodigo(); console.error('falta el plan semilla'); return json({ error: 'interno' }, 500) }
    const { data: existe } = await admin.from('iglesias').select('id').eq('slug', iglesia.slug).maybeSingle()
    if (existe) return await fallo('slug')

    // Un correo con perfil ya pertenece a una iglesia: se responde igual que a uno nuevo y no se crea nada
    const { data: perfilExistente } = await admin.from('perfiles').select('id').eq('email', propietario.email).maybeSingle()
    if (perfilExistente) { await devolverCodigo(); return json({ ok: true }) }

    const inicio = Date.now()
    const origenPeticion = req.headers.get('Origin') ?? ''
    const origen = ORIGENES_INVITACION.includes(origenPeticion) ? origenPeticion : 'https://viveadn.com'
    const { data: ig, error: eIg } = await admin.from('iglesias')
      .insert({ nombre: iglesia.nombre, slug: iglesia.slug, plan: 'semilla', pais: iglesia.pais, ciudad: iglesia.ciudad, es_demo: false })
      .select('id').single()
    if (eIg || !ig) { await devolverCodigo(); console.error('iglesia', eIg?.message); return json({ error: 'interno' }, 500) }
    const deshacerIglesia = async () => {
      const { error } = await admin.from('iglesias').delete().eq('id', ig.id)
      if (error) console.error('no se pudo deshacer la iglesia', ig.id, error.message)
    }

    const { data: inv, error: eInv } = await admin.auth.admin.inviteUserByEmail(propietario.email, {
      redirectTo: `${origen}/reset-password`,
      data: { nombre: propietario.nombre, apellido: propietario.apellido },
    })
    if (eInv || !inv?.user) {
      await deshacerIglesia(); await devolverCodigo()
      // Si el correo ya tenia cuenta en el sistema de acceso, se responde como si todo fuera bien
      if (/already|registered|exists/i.test(eInv?.message ?? '')) return json({ ok: true })
      console.error('invitacion', eInv?.message)
      return json({ error: 'interno' }, 500)
    }
    // Si la invitacion devolvio un usuario anterior (invitado y sin confirmar), nunca se borra
    const creadoAhora = new Date(inv.user.created_at).getTime() >= inicio - 5000
    const { data: perfilDelUsuario } = await admin.from('perfiles').select('id').eq('id', inv.user.id).maybeSingle()
    if (perfilDelUsuario) { await deshacerIglesia(); await devolverCodigo(); return json({ ok: true }) }

    const { error: ePerfil } = await admin.from('perfiles').insert({
      id: inv.user.id, iglesia_id: ig.id, nombre: propietario.nombre, apellido: propietario.apellido, email: propietario.email, rol: 'propietario',
    })
    if (ePerfil) {
      if (creadoAhora) {
        const { error } = await admin.auth.admin.deleteUser(inv.user.id)
        if (error) console.error('no se pudo borrar el usuario creado', inv.user.id, error.message)
      }
      await deshacerIglesia(); await devolverCodigo()
      console.error('perfil', ePerfil.message)
      return json({ error: 'interno' }, 500)
    }

    const { error: eAud } = await admin.from('plataforma_auditoria').insert({
      actor: null, accion: 'registro_autoservicio', iglesia_id: ig.id, detalle: { codigo_id: codigoId, ip_hash: ipHash, slug: iglesia.slug },
    })
    if (eAud) console.error('auditoria fallida', ig.id, eAud.message)
    return json({ ok: true })
  } catch (e) {
    console.error('registro-iglesia', e instanceof Error ? e.message : e)
    return json({ error: 'interno' }, 500)
  }
})
