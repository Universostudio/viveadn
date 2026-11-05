import { createClient } from 'npm:@supabase/supabase-js@2'

// Panel de plataforma: solo para usuarios en plataforma_admins.
// Usa service_role, asi que cada entrada se valida aqui.

// Destinos validos del enlace de invitacion (nunca localhost)
const ORIGENES_INVITACION = [
  'https://viveadn.com',
  'https://www.viveadn.com',
  'https://viveadn-web-app.vercel.app',
]
// Origenes que pueden llamar a la funcion (localhost solo para desarrollo)
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
const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const texto = (v: unknown, max: number) => String(v ?? '').trim().slice(0, max)

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

    // 1. Quien llama debe ser administrador de la plataforma
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    })
    const { data: { user } } = await userClient.auth.getUser()
    if (!user) return json({ error: 'No autenticado' }, 401)

    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } })
    const { data: esAdmin } = await admin.from('plataforma_admins').select('user_id').eq('user_id', user.id).maybeSingle()
    if (!esAdmin) return json({ error: 'Sin permiso' }, 403)

    const body = await req.json().catch(() => ({}))

    // La auditoria no debe perderse en silencio
    const auditar = async (accion: string, iglesia_id: string | null, detalle: Record<string, unknown> = {}) => {
      const { error } = await admin.from('plataforma_auditoria').insert({ actor: user.id, accion, iglesia_id, detalle })
      if (error) console.error('auditoria fallida', accion, iglesia_id, error.message)
      return !error
    }

    // Valida el identificador y que la iglesia exista
    const iglesiaValida = async (id: unknown) => {
      if (typeof id !== 'string' || !UUID_RE.test(id)) return null
      const { data } = await admin.from('iglesias').select('id').eq('id', id).maybeSingle()
      return data ? id : null
    }

    switch (body.accion) {
      case 'listar': {
        const [{ data: iglesias }, { data: addons }, { data: planes }, { data: modulos }, { data: planModulos }] = await Promise.all([
          admin.from('iglesias').select('id, nombre, slug, plan, activa, es_demo, pais, ciudad, created_at, iglesia_madre_id, red_acceso').order('created_at'),
          admin.from('iglesia_modulos').select('iglesia_id, modulo, activo, origen'),
          admin.from('planes').select('*').order('orden'),
          admin.from('modulos').select('*').order('orden'),
          admin.from('plan_modulos').select('plan, modulo'),
        ])
        const conteos = await Promise.all((iglesias ?? []).map(async (i) => {
          const [m, u] = await Promise.all([
            admin.from('miembros').select('id', { count: 'exact', head: true }).eq('iglesia_id', i.id),
            admin.from('perfiles').select('id', { count: 'exact', head: true }).eq('iglesia_id', i.id),
          ])
          return [i.id, { miembros: m.count ?? 0, usuarios: u.count ?? 0 }] as const
        }))
        const porId = Object.fromEntries(conteos)
        return json({
          iglesias: (iglesias ?? []).map(i => ({ ...i, ...porId[i.id], addons: (addons ?? []).filter(a => a.iglesia_id === i.id) })),
          planes, modulos, plan_modulos: planModulos,
        })
      }

      case 'crear_iglesia': {
        const inicio = Date.now()
        const nombre = texto(body.nombre, 80)
        const slug = texto(body.slug, 40).toLowerCase()
        const plan = texto(body.plan || 'semilla', 40)
        const email = texto(body.email, 254).toLowerCase()
        const nombreProp = texto(body.nombre_propietario, 60)
        const apellidoProp = texto(body.apellido_propietario, 60)
        const pais = texto(body.pais, 80)
        const ciudad = texto(body.ciudad, 80)
        if (nombre.length < 2) return json({ error: 'El nombre debe tener entre 2 y 80 caracteres' }, 400)
        if (!SLUG_RE.test(slug) || slug.length < 3) return json({ error: 'La direccion solo admite letras minusculas, numeros y guiones (3 a 40)' }, 400)
        if (!pais || !ciudad) return json({ error: 'Faltan el pais y la ciudad' }, 400)
        if (!EMAIL_RE.test(email)) return json({ error: 'El correo del propietario no es valido' }, 400)
        if (!nombreProp || !apellidoProp) return json({ error: 'Falta el nombre y apellido del propietario' }, 400)
        const { data: planOk } = await admin.from('planes').select('clave').eq('clave', plan).eq('activo', true).maybeSingle()
        if (!planOk) return json({ error: 'El plan no existe' }, 400)
        const { data: existe } = await admin.from('iglesias').select('id').eq('slug', slug).maybeSingle()
        if (existe) return json({ error: 'Esa direccion ya esta en uso' }, 409)
        // Un correo con perfil ya pertenece a una iglesia: no se reutiliza
        const { data: perfilExistente } = await admin.from('perfiles').select('id').eq('email', email).maybeSingle()
        if (perfilExistente) return json({ error: 'Ese correo ya tiene una cuenta en la plataforma' }, 409)

        const origen = ORIGENES_INVITACION.includes(body.origen) ? body.origen : 'https://viveadn.com'
        const { data: ig, error: eIg } = await admin.from('iglesias')
          .insert({ nombre, slug, plan, pais, ciudad, es_demo: body.es_demo === true })
          .select('id').single()
        if (eIg || !ig) return json({ error: 'No se pudo crear la iglesia' }, 500)

        const deshacerIglesia = async () => {
          const { error } = await admin.from('iglesias').delete().eq('id', ig.id)
          if (error) console.error('no se pudo deshacer la iglesia', ig.id, error.message)
        }

        const { data: inv, error: eInv } = await admin.auth.admin.inviteUserByEmail(email, {
          redirectTo: `${origen}/reset-password`,
          data: { nombre: nombreProp, apellido: apellidoProp },
        })
        if (eInv || !inv?.user) {
          await deshacerIglesia()
          const yaExiste = /already|registered|exists/i.test(eInv?.message ?? '')
          return json({ error: yaExiste ? 'Ese correo ya tiene una cuenta en la plataforma' : 'No se pudo enviar la invitacion' }, yaExiste ? 409 : 500)
        }

        // Si la invitacion devolvio un usuario anterior (invitado y sin confirmar), nunca se borra
        const creadoAhora = new Date(inv.user.created_at).getTime() >= inicio - 5000
        const { data: perfilDelUsuario } = await admin.from('perfiles').select('id').eq('id', inv.user.id).maybeSingle()
        if (perfilDelUsuario) {
          await deshacerIglesia()
          return json({ error: 'Ese correo ya tiene una cuenta en la plataforma' }, 409)
        }

        const { error: ePerfil } = await admin.from('perfiles').insert({
          id: inv.user.id, iglesia_id: ig.id, nombre: nombreProp, apellido: apellidoProp, email, rol: 'propietario',
        })
        if (ePerfil) {
          if (creadoAhora) {
            const { error: eBorrar } = await admin.auth.admin.deleteUser(inv.user.id)
            if (eBorrar) console.error('no se pudo borrar el usuario creado', inv.user.id, eBorrar.message)
          }
          await deshacerIglesia()
          return json({ error: 'No se pudo crear el perfil del propietario' }, 500)
        }
        const auditado = await auditar('crear_iglesia', ig.id, { nombre, slug, plan, propietario: email })
        return json({ ok: true, iglesia_id: ig.id, auditado })
      }

      case 'cambiar_plan': {
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { data: planOk } = await admin.from('planes').select('clave').eq('clave', body.plan).eq('activo', true).maybeSingle()
        if (!planOk) return json({ error: 'El plan no existe' }, 400)
        const { error } = await admin.from('iglesias').update({ plan: planOk.clave }).eq('id', iglesiaId)
        if (error) return json({ error: 'No se pudo cambiar el plan' }, 500)
        const auditado = await auditar('cambiar_plan', iglesiaId, { plan: planOk.clave })
        return json({ ok: true, auditado })
      }

      case 'modulo_addon': {
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { data: mod } = await admin.from('modulos').select('clave').eq('clave', body.modulo).maybeSingle()
        if (!mod) return json({ error: 'El modulo no existe' }, 400)
        if (body.activo === true) {
          const { error } = await admin.from('iglesia_modulos')
            .upsert({ iglesia_id: iglesiaId, modulo: mod.clave, activo: true, origen: body.origen === 'cortesia' ? 'cortesia' : 'addon', desde: new Date().toISOString(), hasta: null })
          if (error) return json({ error: 'No se pudo activar el modulo' }, 500)
        } else {
          const { error } = await admin.from('iglesia_modulos').delete().eq('iglesia_id', iglesiaId).eq('modulo', mod.clave)
          if (error) return json({ error: 'No se pudo quitar el modulo' }, 500)
        }
        const auditado = await auditar('modulo_addon', iglesiaId, { modulo: mod.clave, activo: body.activo === true })
        return json({ ok: true, auditado })
      }

      case 'estado': {
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const activa = body.activa === true
        const { error } = await admin.from('iglesias').update({ activa }).eq('id', iglesiaId)
        if (error) return json({ error: 'No se pudo cambiar el estado' }, 500)
        const auditado = await auditar(activa ? 'activar_iglesia' : 'suspender_iglesia', iglesiaId)
        return json({ ok: true, auditado })
      }

      case 'vincular_red': {
        // Vincula una iglesia como sede de otra (o la deja independiente con madre_id nulo) y fija el acceso de la madre
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        let madreId: string | null = null
        if (body.madre_id !== null && body.madre_id !== undefined && body.madre_id !== '') {
          madreId = await iglesiaValida(body.madre_id)
          if (!madreId) return json({ error: 'La iglesia madre no existe' }, 404)
          if (madreId === iglesiaId) return json({ error: 'Una iglesia no puede ser madre de si misma' }, 400)
        }
        if (!['ninguno', 'resumen'].includes(body.red_acceso)) return json({ error: 'El nivel de acceso no es valido' }, 400)
        const { error } = await admin.from('iglesias').update({ iglesia_madre_id: madreId, red_acceso: body.red_acceso }).eq('id', iglesiaId)
        if (error) {
          // La base rechaza cadenas de mas de un nivel con un mensaje propio
          const regla = /sede|madre/i.test(error.message)
          return json({ error: regla ? 'Una iglesia madre no puede ser sede, ni una sede tener sedes' : 'No se pudo cambiar la red' }, regla ? 409 : 500)
        }
        const auditado = await auditar('vincular_red', iglesiaId, { madre_id: madreId, red_acceso: body.red_acceso })
        return json({ ok: true, auditado })
      }

      default:
        return json({ error: 'Accion desconocida' }, 400)
    }
  } catch (e) {
    console.error('error interno', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
