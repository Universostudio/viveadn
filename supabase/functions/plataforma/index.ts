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

const ETAPAS = ['onboarding', 'prueba', 'activa', 'receso', 'suspendida']

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
          admin.from('iglesias').select('id, nombre, slug, plan, activa, etapa, prueba_hasta, borrado_programado_en, es_demo, pais, ciudad, created_at, iglesia_madre_id, red_acceso').order('created_at'),
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

      case 'etapa': {
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        if (!ETAPAS.includes(body.etapa)) return json({ error: 'La etapa no es valida' }, 400)
        const cambios: Record<string, unknown> = { etapa: body.etapa }
        if (body.etapa === 'prueba') {
          const dias = Number(body.prueba_dias ?? 30)
          if (!Number.isInteger(dias) || dias < 1 || dias > 365) return json({ error: 'Los dias de prueba deben estar entre 1 y 365' }, 400)
          cambios.prueba_hasta = new Date(Date.now() + dias * 86400000).toISOString()
        }
        const { error } = await admin.from('iglesias').update(cambios).eq('id', iglesiaId)
        if (error) return json({ error: 'No se pudo cambiar la etapa' }, 500)
        const auditado = await auditar('etapa_iglesia', iglesiaId, { etapa: body.etapa, prueba_hasta: cambios.prueba_hasta ?? null })
        return json({ ok: true, auditado })
      }

      case 'exportar': {
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { data, error } = await admin.rpc('exportar_iglesia', { p_iglesia: iglesiaId })
        if (error || !data) return json({ error: 'No se pudo exportar la iglesia' }, 500)
        const auditado = await auditar('exportar_iglesia', iglesiaId)
        return json({ ok: true, exportacion: data, auditado })
      }

      case 'programar_borrado': {
        // Solo desde receso o suspendida; deja un plazo para arrepentirse
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { data: ig } = await admin.from('iglesias').select('slug, etapa').eq('id', iglesiaId).single()
        if (!ig || body.confirmar !== ig.slug) return json({ error: 'La confirmacion no coincide con la direccion de la iglesia' }, 400)
        const dias = Number(body.dias ?? 30)
        if (!Number.isInteger(dias) || dias < 7 || dias > 90) return json({ error: 'El plazo debe estar entre 7 y 90 dias' }, 400)
        if (!['receso', 'suspendida'].includes(ig.etapa)) return json({ error: 'Solo se programa el borrado de una iglesia en receso o suspendida' }, 409)
        const hasta = new Date(Date.now() + dias * 86400000).toISOString()
        const { error } = await admin.from('iglesias').update({ borrado_programado_en: hasta }).eq('id', iglesiaId)
        if (error) return json({ error: 'No se pudo programar el borrado' }, 500)
        const auditado = await auditar('programar_borrado', iglesiaId, { borrado_programado_en: hasta })
        return json({ ok: true, borrado_programado_en: hasta, auditado })
      }

      case 'cancelar_borrado': {
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { error } = await admin.from('iglesias').update({ borrado_programado_en: null }).eq('id', iglesiaId)
        if (error) return json({ error: 'No se pudo cancelar el borrado' }, 500)
        const auditado = await auditar('cancelar_borrado', iglesiaId)
        return json({ ok: true, auditado })
      }

      case 'borrar_iglesia': {
        // Irreversible: exige la direccion escrita y que el plazo programado haya vencido
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { data: ig } = await admin.from('iglesias').select('slug').eq('id', iglesiaId).single()
        if (!ig || body.confirmar !== ig.slug) return json({ error: 'La confirmacion no coincide con la direccion de la iglesia' }, 400)
        const { data: usuarios, error } = await admin.rpc('borrar_iglesia', { p_iglesia: iglesiaId })
        if (error) {
          const antes = /BORRADO_NO_VENCIDO/.test(error.message)
          return json({ error: antes ? 'El plazo de borrado programado todavia no ha vencido' : 'No se pudo borrar la iglesia' }, antes ? 409 : 500)
        }
        // La base ya no tiene la iglesia: se retiran sus cuentas de acceso. Las que fallen quedan anotadas
        const ids: string[] = Array.isArray(usuarios) ? usuarios : []
        const pendientes: string[] = []
        for (const id of ids) {
          const { error: eBorrar } = await admin.auth.admin.deleteUser(id)
          if (eBorrar) { pendientes.push(id); console.error('no se pudo borrar el usuario', id, eBorrar.message) }
        }
        const auditado = await auditar('borrar_iglesia', null, { iglesia_id: iglesiaId, usuarios_borrados: ids.length - pendientes.length, usuarios_pendientes: pendientes })
        return json({ ok: true, usuarios_borrados: ids.length - pendientes.length, usuarios_pendientes: pendientes.length, auditado })
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

      case 'registro_estado': {
        const [{ data: ajustes }, { data: codigos }] = await Promise.all([
          admin.from('plataforma_ajustes').select('clave, valor').in('clave', ['registro_abierto', 'registro_requiere_codigo']),
          admin.from('registro_codigos').select('id, etiqueta, usos, usos_max, vence_en, activo, created_at').order('created_at', { ascending: false }).limit(100),
        ])
        const ajuste = (c: string, defecto: boolean) => { const v = (ajustes ?? []).find(a => a.clave === c)?.valor; return typeof v === 'boolean' ? v : defecto }
        return json({ abierto: ajuste('registro_abierto', false), requiere_codigo: ajuste('registro_requiere_codigo', true), codigos: codigos ?? [] })
      }

      case 'registro_ajustes': {
        if (typeof body.abierto !== 'boolean' || typeof body.requiere_codigo !== 'boolean') return json({ error: 'Faltan los ajustes' }, 400)
        const ahora = new Date().toISOString()
        const { error } = await admin.from('plataforma_ajustes').upsert([
          { clave: 'registro_abierto', valor: body.abierto, updated_at: ahora },
          { clave: 'registro_requiere_codigo', valor: body.requiere_codigo, updated_at: ahora },
        ])
        if (error) return json({ error: 'No se pudieron guardar los ajustes' }, 500)
        const auditado = await auditar('registro_ajustes', null, { abierto: body.abierto, requiere_codigo: body.requiere_codigo })
        return json({ ok: true, auditado })
      }

      case 'codigo_crear': {
        const etiqueta = texto(body.etiqueta, 80)
        const usosMax = Number.isInteger(body.usos_max) ? Number(body.usos_max) : 1
        const dias = Number.isInteger(body.dias) ? Number(body.dias) : 0
        if (!etiqueta) return json({ error: 'Falta la etiqueta del codigo' }, 400)
        if (usosMax < 1 || usosMax > 1000) return json({ error: 'Los usos deben estar entre 1 y 1000' }, 400)
        if (dias < 0 || dias > 365) return json({ error: 'La vigencia debe estar entre 0 y 365 dias' }, 400)
        // Sin letras ambiguas (I, O) ni cifras 0 y 1; 32 simbolos, asi que cada byte se reparte sin sesgo
        const alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
        const aleatorio = (n: number) => [...crypto.getRandomValues(new Uint8Array(n))].map(x => alfabeto[x % 32]).join('')
        const codigo = `ADN-${aleatorio(4)}-${aleatorio(4)}`
        const huella = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(codigo)))].map(x => x.toString(16).padStart(2, '0')).join('')
        const vence = dias > 0 ? new Date(Date.now() + dias * 86400000).toISOString() : null
        const { data: fila, error } = await admin.from('registro_codigos')
          .insert({ codigo_hash: huella, etiqueta, usos_max: usosMax, vence_en: vence }).select('id').single()
        if (error || !fila) return json({ error: 'No se pudo crear el codigo' }, 500)
        // El codigo solo se muestra ahora: en la base queda su huella
        const auditado = await auditar('codigo_crear', null, { codigo_id: fila.id, etiqueta, usos_max: usosMax, dias })
        return json({ ok: true, codigo, auditado })
      }

      case 'codigo_estado': {
        if (typeof body.id !== 'string' || !UUID_RE.test(body.id) || typeof body.activo !== 'boolean') return json({ error: 'Datos no validos' }, 400)
        const { data, error } = await admin.from('registro_codigos').update({ activo: body.activo }).eq('id', body.id).select('id').maybeSingle()
        if (error) return json({ error: 'No se pudo cambiar el codigo' }, 500)
        if (!data) return json({ error: 'El codigo no existe' }, 404)
        const auditado = await auditar(body.activo ? 'codigo_activar' : 'codigo_desactivar', null, { codigo_id: body.id })
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
