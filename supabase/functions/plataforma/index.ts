import { createClient } from 'npm:@supabase/supabase-js@2'
import { claveCronValida, errorDeCiclo, tamanoLote } from './ciclo.ts'
import { avisoPurga, enviarAviso, leerConfig, type TipoEnvio } from './envio.ts'
import { filasDeFacturacion, simular, validarPrecio } from './facturacion.ts'
import { leerTodo } from './paginar.ts'
import { correoDeAviso, esUuid, estadisticasDeAgregado, estadisticasDeAvisos, resumenDeAgregado, listaDeTickets, resumenDeSoporte, sinDemos, ticketAbierto, validarAviso, validarNovedad, validarRespuesta } from './soporte.ts'
import { conteosPorIglesia, envioDelDia, eventosDeActividad, faltaLaFuncion, historialDeIglesia, leerCuerpoJson, MAX_CUERPO, MAX_LIBRO, salidaSegura } from './panel.ts'

// Panel de plataforma: solo para usuarios en plataforma_admins.
// Usa service_role, asi que cada entrada se valida aqui.

// Entornos de prueba: ADN_ORIGENES_EXTRA añade direcciones de la web (https exactas, separadas por comas, hasta 10). En producción no se define.
const ORIGENES_EXTRA = (Deno.env.get('ADN_ORIGENES_EXTRA') ?? '').split(',').map(s => s.trim()).filter(s => /^https:\/\/[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:\d{1,5})?$/.test(s)).slice(0, 10)
// Destinos validos del enlace de invitacion (nunca localhost)
const ORIGENES_INVITACION = [
  'https://viveadn.com',
  'https://www.viveadn.com',
  'https://viveadn-web-app.vercel.app',
  ...ORIGENES_EXTRA,
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

// Cubos con archivos de iglesia; la primera carpeta de cada ruta es el id de la iglesia
const CUBOS_IGLESIA = ['iglesia-marca', 'iglesia-archivos']

const texto = (v: unknown, max: number) => String(v ?? '').trim().slice(0, max)

Deno.serve(async (req) => {
  const cors = corsPara(req)
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405)

  // El cuerpo se lee como texto con tope (413 si el tamano declarado o el real pasa de 32 KB) y solo se acepta un objeto JSON
  const declarado = req.headers.get('content-length')
  const leido = Number(declarado) > MAX_CUERPO ? { ok: false as const, status: 413 as const, error: 'Cuerpo demasiado grande' } : leerCuerpoJson(await req.text(), declarado)
  if (!leido.ok) return json({ error: leido.error }, leido.status)

  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } })

    // 1. Quien llama es un administrador de la plataforma o, solo para purgar lo vencido, la tarea programada
    //    con la clave ADN_CRON_SECRET (si el secreto no existe, esa via esta cerrada)
    let user: { id: string } | null = null
    const claveCron = req.headers.get('x-adn-cron')
    const esCron = claveCron !== null
    if (esCron) {
      if (!(await claveCronValida(claveCron, Deno.env.get('ADN_CRON_SECRET')))) return json({ error: 'Sin permiso' }, 403)
    } else {
      const userClient = createClient(url, anon, {
        global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
      })
      const { data: { user: autenticado } } = await userClient.auth.getUser()
      if (!autenticado) return json({ error: 'No autenticado' }, 401)
      const { data: esAdmin } = await admin.from('plataforma_admins').select('user_id').eq('user_id', autenticado.id).maybeSingle()
      if (!esAdmin) return json({ error: 'Sin permiso' }, 403)
      user = autenticado
    }

    const body = leido.body
    // La clave de la tarea solo abre la purga y dos lecturas sin datos de personas: el estado de la purga y el libro de purgadas
    if (esCron && !['purgar_vencidas', 'estado_purga', 'libro_purgas', 'avisar_purga'].includes(body.accion)) return json({ error: 'Sin permiso' }, 403)

    // La auditoria no debe perderse en silencio
    const auditar = async (accion: string, iglesia_id: string | null, detalle: Record<string, unknown> = {}) => {
      const { error } = await admin.from('plataforma_auditoria').insert({ actor: user?.id ?? null, accion, iglesia_id, detalle })
      if (error) console.error('auditoria fallida', accion, iglesia_id, error.message)
      return !error
    }

    // Valida el identificador y que la iglesia exista
    const iglesiaValida = async (id: unknown) => {
      if (typeof id !== 'string' || !UUID_RE.test(id)) return null
      const { data } = await admin.from('iglesias').select('id').eq('id', id).maybeSingle()
      return data ? id : null
    }

    // Recorre un prefijo del almacenamiento, carpeta a carpeta, y devuelve todos sus archivos
    const listarArchivos = async (cubo: string, prefijo: string) => {
      const salida: { ruta: string; bytes: number | null }[] = []
      const pila = [prefijo]
      while (pila.length) {
        const dir = pila.pop()!
        for (let offset = 0; ; offset += 100) {
          const { data, error } = await admin.storage.from(cubo).list(dir, { limit: 100, offset })
          if (error) throw new Error('No se pudo listar el almacenamiento')
          for (const e of data ?? []) {
            const ruta = `${dir}/${e.name}`
            if (e.id === null) pila.push(ruta)
            else salida.push({ ruta, bytes: (e.metadata as { size?: number } | null)?.size ?? null })
          }
          if (!data || data.length < 100) break
        }
      }
      return salida
    }

    // Tras borrar las filas de la iglesia: vacia sus archivos (Storage impide borrar una cuenta que todavia es
    // propietaria de objetos) y retira sus cuentas de acceso. Lo que falle queda anotado para repetirlo a mano
    const limpiarExterno = async (iglesiaId: string, usuarios: unknown) => {
      let archivosBorrados = 0
      let archivosPendientes = 0
      for (const cubo of CUBOS_IGLESIA) {
        try {
          const rutas = (await listarArchivos(cubo, iglesiaId)).map(a => a.ruta)
          for (let i = 0; i < rutas.length; i += 100) {
            const lote = rutas.slice(i, i + 100)
            const { error: eQuitar } = await admin.storage.from(cubo).remove(lote)
            if (eQuitar) archivosPendientes += lote.length
            else archivosBorrados += lote.length
          }
        } catch (e) {
          archivosPendientes += 1
          console.error('no se pudo vaciar el cubo', cubo, e instanceof Error ? e.message : e)
        }
      }
      const ids: string[] = Array.isArray(usuarios) ? usuarios : []
      const pendientes: string[] = []
      for (const id of ids) {
        const { error: eBorrar } = await admin.auth.admin.deleteUser(id)
        if (eBorrar) { pendientes.push(id); console.error('no se pudo borrar el usuario', id, eBorrar.message) }
      }
      return { archivosBorrados, archivosPendientes, usuariosBorrados: ids.length - pendientes.length, usuariosPendientes: pendientes }
    }

    // Purga completa de una iglesia en borrado suave cuyo plazo ya vencio: base de datos (atomica y auditada),
    // archivos y cuentas. Devuelve el error de la base si la purga no procede
    const purgarIglesia = async (iglesiaId: string) => {
      const { data: usuarios, error } = await admin.rpc('adn_purgar_iglesia', { p_iglesia: iglesiaId, p_actor: user?.id ?? null })
      if (error) return { error: errorDeCiclo(error.message), resultado: null }
      const r = await limpiarExterno(iglesiaId, usuarios)
      await admin.rpc('adn_auditar_ciclo', {
        p_iglesia: iglesiaId, p_accion: 'purga_externa', p_actor: user?.id ?? null,
        p_detalle: {
          usuarios_borrados: r.usuariosBorrados, usuarios_pendientes: r.usuariosPendientes.length,
          archivos_borrados: r.archivosBorrados, archivos_pendientes: r.archivosPendientes,
        },
      })
      const auditado = await auditar('purgar_iglesia', null, {
        iglesia_id: iglesiaId, usuarios_borrados: r.usuariosBorrados, usuarios_pendientes: r.usuariosPendientes,
        archivos_borrados: r.archivosBorrados, archivos_pendientes: r.archivosPendientes,
      })
      return { error: null, resultado: {
        usuarios_borrados: r.usuariosBorrados, usuarios_pendientes: r.usuariosPendientes.length,
        archivos_borrados: r.archivosBorrados, archivos_pendientes: r.archivosPendientes, auditado,
      } }
    }

    switch (body.accion) {
      case 'listar':
      case 'resumen': {
        // Las listas largas se leen por páginas y ordenadas: el límite de filas del servicio no las corta en silencio
        const [rIglesias, rAddons, { data: planes }, { data: modulos }, { data: planModulos }] = await Promise.all([
          leerTodo<Record<string, any>>((d, h) => admin.from('iglesias').select('id, nombre, slug, plan, activa, etapa, prueba_hasta, borrado_programado_en, adn_borrada_en, es_demo, pais, ciudad, created_at, iglesia_madre_id, red_acceso').order('created_at').order('id').range(d, h)),
          leerTodo<Record<string, any>>((d, h) => admin.from('iglesia_modulos').select('iglesia_id, modulo, activo, origen').order('iglesia_id').order('modulo').range(d, h)),
          admin.from('planes').select('*').order('orden'),
          admin.from('modulos').select('*').order('orden'),
          admin.from('plan_modulos').select('plan, modulo'),
        ])
        if (rIglesias.error || rAddons.error) return json({ error: 'No se pudo leer la lista de iglesias' }, 500)
        const iglesias = rIglesias.data, addons = rAddons.data
        // Los conteos salen de una sola consulta (adn_plataforma_resumen). Si la migración aún no está aplicada, se cuenta como antes (2 consultas por iglesia)
        let porId: Record<string, { miembros: number; usuarios: number }>
        const rResumen = await leerTodo<Record<string, any>>((d, h) => admin.rpc('adn_plataforma_resumen').order('iglesia_id').range(d, h))
        const errorResumen = rResumen.error
        if (!errorResumen) {
          porId = conteosPorIglesia(rResumen.data)
        } else if (faltaLaFuncion(errorResumen as { message?: string; code?: string })) {
          const conteos = await Promise.all((iglesias ?? []).map(async (i) => {
            const [m, u] = await Promise.all([
              admin.from('miembros').select('id', { count: 'exact', head: true }).eq('iglesia_id', i.id),
              admin.from('perfiles').select('id', { count: 'exact', head: true }).eq('iglesia_id', i.id),
            ])
            return [i.id, { miembros: m.count ?? 0, usuarios: u.count ?? 0 }] as const
          }))
          porId = Object.fromEntries(conteos)
        } else {
          return json({ error: 'No se pudo leer el resumen de iglesias' }, 500)
        }
        const addonsPorIglesia = new Map<string, Record<string, any>[]>()
        for (const a of addons) addonsPorIglesia.set(a.iglesia_id, [...(addonsPorIglesia.get(a.iglesia_id) ?? []), a])
        return json(salidaSegura({
          iglesias: (iglesias ?? []).map(i => ({ ...i, ...(porId[i.id] ?? { miembros: 0, usuarios: 0 }), addons: addonsPorIglesia.get(i.id) ?? [] })),
          planes, modulos, plan_modulos: planModulos,
        }))
      }

      case 'actividad': {
        // Ultimas altas y acciones de plataforma: accion, iglesia y fecha. Nunca el detalle de la auditoria
        const limite = Number.isInteger(body.limite) ? Math.max(1, Math.min(body.limite, 100)) : 20
        const { data, error } = await admin.rpc('adn_plataforma_actividad', { p_limite: limite })
        if (error) return json({ error: faltaLaFuncion(error) ? 'La actividad no esta disponible hasta aplicar la migracion del panel' : 'No se pudo leer la actividad' }, faltaLaFuncion(error) ? 501 : 500)
        return json(salidaSegura({ ok: true, eventos: eventosDeActividad(data) }))
      }

      case 'detalle': {
        // Historial de acciones de plataforma de una iglesia: accion y fecha
        if (typeof body.iglesia_id !== 'string' || !UUID_RE.test(body.iglesia_id)) return json({ error: 'Identificador de iglesia no valido' }, 400)
        const { data, error } = await admin.rpc('adn_plataforma_historial', { p_iglesia: body.iglesia_id, p_limite: 50 })
        if (error) return json({ error: faltaLaFuncion(error) ? 'El historial no esta disponible hasta aplicar la migracion del panel' : 'No se pudo leer el historial' }, faltaLaFuncion(error) ? 501 : 500)
        return json(salidaSegura({ ok: true, historial: historialDeIglesia(data) }))
      }

      case 'sistema': {
        // Estado de los procesos: purga, libro de purgadas y envio de correo (solo si esta activo y cuanto se uso hoy; nunca valores de secretos).
        // Cada parte falla por separado: si una no responde, llega como null y el resto se muestra
        const [rPurga, rLibro, rEnvio] = await Promise.all([
          admin.rpc('adn_purga_estado', { p_horas: 48 }),
          admin.rpc('adn_purgas_desde', { p_desde: null }),
          admin.from('adn_envios_dia').select('tipo, n').eq('dia', new Date().toISOString().slice(0, 10)),
        ])
        const config = leerConfig(k => Deno.env.get(k))
        const libro = rLibro.error ? null : (rLibro.data ?? []).slice(-MAX_LIBRO).reverse()
          .map((f: { iglesia_ref: string; purgada_en: string }) => ({ iglesia: f.iglesia_ref, purgada_en: new Date(f.purgada_en).toISOString() }))
        return json(salidaSegura({
          ok: true,
          purga: rPurga.error ? null : rPurga.data,
          libro,
          envio: { ...envioDelDia(rEnvio.error ? null : rEnvio.data, config), contadores: !rEnvio.error },
        }))
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
        // Una iglesia en baja suave no cambia de etapa a mano: se recupera con «recuperar», que respeta el plazo y deja su rastro
        const { data: enBaja } = await admin.from('iglesias').select('adn_borrada_en').eq('id', iglesiaId).maybeSingle()
        if (enBaja?.adn_borrada_en) return json({ error: 'La iglesia esta en baja: usa «Recuperar» para devolverla a su estado' }, 409)
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

      // Decision de Gerencia (informe 41, A1): la plataforma NO exporta datos de personas. La copia la descarga solo el propietario de la iglesia con el autoservicio
      // (funcion datos-iglesia). Estas acciones quedan cerradas con 403 para que una version antigua de la web no abra una puerta por error.
      case 'exportar':
      case 'exportar_plan':
      case 'exportar_pagina':
        return json({ error: 'La plataforma no exporta datos de personas: la copia la descarga el propietario de la iglesia desde «Datos y baja»' }, 403)

      case 'auditoria_iglesia': {
        // La auditoria de la plataforma sobre una iglesia, aparte de su exportacion y solo para administradores de plataforma
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { data, error } = await admin.from('plataforma_auditoria')
          .select('id, created_at, actor, accion, detalle').eq('iglesia_id', iglesiaId).order('created_at', { ascending: false }).limit(1000)
        if (error) return json({ error: 'No se pudo leer la auditoria' }, 500)
        const filas = (data ?? []).map((f) => {
          const detalle = { ...((f.detalle ?? {}) as Record<string, unknown>) }
          delete detalle.ip_hash
          return { ...f, detalle }
        })
        return json({ ok: true, auditoria: filas, limitada: filas.length === 1000 })
      }

      case 'programar_borrado': {
        // Solo desde receso o suspendida; deja un plazo para arrepentirse
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { data: ig } = await admin.from('iglesias').select('slug, etapa, adn_borrada_en').eq('id', iglesiaId).single()
        if (!ig || body.confirmar !== ig.slug) return json({ error: 'La confirmacion no coincide con la direccion de la iglesia' }, 400)
        if (ig.adn_borrada_en) return json({ error: 'La iglesia ya esta en borrado suave' }, 409)
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
        const { data: igBorrada } = await admin.from('iglesias').select('adn_borrada_en').eq('id', iglesiaId).single()
        if (igBorrada?.adn_borrada_en) return json({ error: 'La iglesia esta en borrado suave: usa recuperar' }, 409)
        const { error } = await admin.from('iglesias').update({ borrado_programado_en: null }).eq('id', iglesiaId)
        if (error) return json({ error: 'No se pudo cancelar el borrado' }, 500)
        const auditado = await auditar('cancelar_borrado', iglesiaId)
        return json({ ok: true, auditado })
      }

      case 'borrar_iglesia': {
        // Irreversible: exige la direccion escrita y que el plazo programado haya vencido
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { data: ig } = await admin.from('iglesias').select('slug, adn_borrada_en').eq('id', iglesiaId).single()
        if (!ig || body.confirmar !== ig.slug) return json({ error: 'La confirmacion no coincide con la direccion de la iglesia' }, 400)
        // Una iglesia en borrado suave se purga por la via auditada
        if (ig.adn_borrada_en) {
          const p = await purgarIglesia(iglesiaId)
          if (p.error) return json({ error: p.error.mensaje }, p.error.estado)
          return json({ ok: true, ...p.resultado })
        }
        const { data: usuarios, error } = await admin.rpc('borrar_iglesia', { p_iglesia: iglesiaId })
        if (error) {
          const antes = /BORRADO_NO_VENCIDO/.test(error.message)
          return json({ error: antes ? 'El plazo de borrado programado todavia no ha vencido' : 'No se pudo borrar la iglesia' }, antes ? 409 : 500)
        }
        // La base ya no tiene la iglesia: se vacian sus archivos y se retiran sus cuentas
        const r = await limpiarExterno(iglesiaId, usuarios)
        const auditado = await auditar('borrar_iglesia', null, {
          iglesia_id: iglesiaId, usuarios_borrados: r.usuariosBorrados, usuarios_pendientes: r.usuariosPendientes,
          archivos_borrados: r.archivosBorrados, archivos_pendientes: r.archivosPendientes,
        })
        return json({
          ok: true, usuarios_borrados: r.usuariosBorrados, usuarios_pendientes: r.usuariosPendientes.length,
          archivos_borrados: r.archivosBorrados, archivos_pendientes: r.archivosPendientes, auditado,
        })
      }

      case 'borrar_suave': {
        // Suspende la iglesia y fija 30 dias de plazo; dentro del plazo se puede recuperar
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const { data: ig } = await admin.from('iglesias').select('slug').eq('id', iglesiaId).single()
        if (!ig || body.confirmar !== ig.slug) return json({ error: 'La confirmacion no coincide con la direccion de la iglesia' }, 400)
        const motivo = texto(body.motivo, 500) || null
        const { data: purgaEl, error } = await admin.rpc('adn_borrar_suave', { p_iglesia: iglesiaId, p_actor: user?.id ?? null, p_motivo: motivo })
        if (error) { const e = errorDeCiclo(error.message); return json({ error: e.mensaje }, e.estado) }
        const auditado = await auditar('borrar_suave', iglesiaId, { purga_el: purgaEl })
        return json({ ok: true, purga_el: purgaEl, auditado })
      }

      case 'recuperar': {
        const iglesiaId = await iglesiaValida(body.iglesia_id)
        if (!iglesiaId) return json({ error: 'La iglesia no existe' }, 404)
        const motivo = texto(body.motivo, 500) || null
        const { data: etapa, error } = await admin.rpc('adn_recuperar_iglesia', { p_iglesia: iglesiaId, p_actor: user?.id ?? null, p_motivo: motivo })
        if (error) { const e = errorDeCiclo(error.message); return json({ error: e.mensaje }, e.estado) }
        const auditado = await auditar('recuperar_iglesia', iglesiaId, { etapa })
        return json({ ok: true, etapa, auditado })
      }

      case 'purgar_vencidas': {
        // Purga las iglesias cuyo plazo de gracia ya vencio, en lotes pequenos. La puede lanzar un administrador
        // o la tarea programada; cada purga es completa (base, archivos y cuentas) y queda auditada
        const { data: ids, error } = await admin.rpc('adn_iglesias_vencidas')
        if (error) return json({ error: 'No se pudo consultar las iglesias vencidas' }, 500)
        const todas: string[] = Array.isArray(ids) ? ids : []
        const lote = todas.slice(0, tamanoLote(body.max))
        const purgadas: string[] = []
        const fallidas: string[] = []
        for (const id of lote) {
          const p = await purgarIglesia(id)
          if (p.error) { fallidas.push(id); console.error('purga fallida', id, p.error.mensaje) }
          else purgadas.push(id)
        }
        // Libro de purgadas: solo identificador y fecha. Quien llama debe guardarlo FUERA de la base (docs/PURGA.md, apartado 4)
        const purgada_en = new Date().toISOString()
        return json({ ok: true, vencidas: todas.length, purgadas: purgadas.length, fallidas: fallidas.length, restantes: todas.length - lote.length,
          registro: purgadas.map(iglesia => ({ iglesia, purgada_en })) })
      }

      case 'estado_purga': {
        // Solo cifras: iglesias en borrado suave, vencidas, horas de la mas atrasada y si el retraso supera el umbral (48 horas)
        const { data, error } = await admin.rpc('adn_purga_estado', { p_horas: 48 })
        if (error || !data) return json({ error: 'No se pudo consultar el estado de la purga' }, 500)
        // La tarea programada (pg_cron) es opcional: si su funcion aun no existe o falla, llega null y el resto se muestra
        const { data: tarea, error: eTarea } = await admin.rpc('adn_purga_tarea_estado')
        return json({ ok: true, ...(data as Record<string, unknown>), tarea: eTarea ? null : tarea })
      }

      case 'avisar_purga': {
        // Alerta por correo si la purga va atrasada (docs/COSTE-ENVIO.md): como maximo una al dia, apagada por defecto y solo a la direccion
        // de alertas configurada (ADN_EMAIL_ALERTAS). El correo lleva solo cifras. Si el envio falla, la respuesta lo dice y no pasa nada mas
        const { data, error } = await admin.rpc('adn_purga_estado', { p_horas: 48 })
        if (error || !data) return json({ error: 'No se pudo consultar el estado de la purga' }, 500)
        const e = data as { atrasada: boolean; vencidas: number; horas_mas_atrasada: number; en_borrado: number }
        if (!e.atrasada) return json({ ok: true, aviso: 'no_hace_falta' })
        const config = leerConfig(k => Deno.env.get(k))
        const destino = Deno.env.get('ADN_EMAIL_ALERTAS')?.trim() ?? ''
        const r = await enviarAviso({
          tipo: 'purga', iglesia: null, destino, destinoRegistrado: destino !== '', ...avisoPurga(e),
          idempotencia: `purga/${new Date().toISOString().slice(0, 10)}`,
        }, {
          config,
          reservar: async (tipo: TipoEnvio, igl, topeI, topeT, topeG) => {
            const { data: d, error: er } = await admin.rpc('adn_envio_reservar', { p_tipo: tipo, p_iglesia: igl, p_tope_iglesia: topeI, p_tope_tipo: topeT, p_tope_global: topeG })
            if (er) throw new Error(er.message)
            return String(d)
          },
          liberar: async (tipo: TipoEnvio, igl) => { await admin.rpc('adn_envio_liberar', { p_tipo: tipo, p_iglesia: igl }) },
          fetchFn: fetch, log: (...a) => console.error('alerta de purga', ...a),
        })
        return json({ ok: true, aviso: r.estado, ...(r.estado === 'tope' ? { tope: r.cual } : {}) })
      }

      case 'libro_purgas': {
        // Exporta el libro de purgadas desde la auditoria (identificador y fecha). Con `desde` devuelve solo lo posterior o igual
        let desde: string | null = null
        if (body.desde !== undefined && body.desde !== null && body.desde !== '') {
          if (typeof body.desde !== 'string' || Number.isNaN(Date.parse(body.desde))) return json({ error: 'La fecha no es valida' }, 400)
          desde = new Date(body.desde).toISOString()
        }
        const { data, error } = await admin.rpc('adn_purgas_desde', { p_desde: desde })
        if (error) return json({ error: 'No se pudo leer el libro de purgadas' }, 500)
        return json({ ok: true, registro: (data ?? []).map((f: { iglesia_ref: string; purgada_en: string }) => ({ iglesia: f.iglesia_ref, purgada_en: f.purgada_en })) })
      }

      case 'repurgar_registradas': {
        // Tras restaurar una copia anterior a unas purgas: vuelve a marcar como vencidas las iglesias del libro que reaparecen.
        // No borra nada por si misma: la purga normal (purgar_vencidas) las elimina despues, con sus archivos y cuentas
        if (body.confirmar !== 'REPURGAR') return json({ error: 'Falta la confirmacion' }, 400)
        const ids: unknown = body.ids
        if (!Array.isArray(ids) || ids.length === 0 || ids.length > 5000 || !ids.every(i => typeof i === 'string' && UUID_RE.test(i))) {
          return json({ error: 'La lista de identificadores no es valida' }, 400)
        }
        const { data, error } = await admin.rpc('adn_repurgar_registradas', { p_ids: ids, p_actor: user?.id ?? null })
        if (error) return json({ error: 'No se pudo aplicar el libro de purgadas' }, 500)
        const marcadas = Array.isArray(data) ? data.length : 0
        const auditado = await auditar('repurgar_registradas', null, { recibidas: ids.length, marcadas })
        return json({ ok: true, recibidas: ids.length, marcadas, auditado })
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
        // Lo que no es un entero se rechaza: antes un valor raro (texto, decimal) se cambiaba en silencio por el valor por defecto, y dias = 0 dejaba el codigo sin vencer sin decirlo
        if (body.usos_max !== undefined && !Number.isInteger(body.usos_max)) return json({ error: 'Los usos deben ser un numero entero' }, 400)
        if (body.dias !== undefined && !Number.isInteger(body.dias)) return json({ error: 'La vigencia debe ser un numero entero de dias' }, 400)
        const usosMax = body.usos_max === undefined ? 1 : Number(body.usos_max)
        const dias = body.dias === undefined ? 0 : Number(body.dias)
        if (!etiqueta) return json({ error: 'Falta la etiqueta del codigo' }, 400)
        if (usosMax < 1 || usosMax > 1000) return json({ error: 'Los usos deben estar entre 1 y 1000' }, 400)
        if (dias < 1 || dias > 365) return json({ error: 'La vigencia debe estar entre 1 y 365 dias: un codigo sin vencimiento no se crea' }, 400)
        // Sin letras ambiguas (I, O) ni cifras 0 y 1; 32 simbolos, asi que cada byte se reparte sin sesgo
        const alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
        const aleatorio = (n: number) => [...crypto.getRandomValues(new Uint8Array(n))].map(x => alfabeto[x % 32]).join('')
        const codigo = `ADN-${aleatorio(4)}-${aleatorio(4)}`
        const huella = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(codigo)))].map(x => x.toString(16).padStart(2, '0')).join('')
        const vence = new Date(Date.now() + dias * 86400000).toISOString()
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

      // ---- Soporte: tickets, novedades y avisos dentro de la aplicacion. Lo lee y lo escribe solo la plataforma (service_role); cada iglesia ve lo suyo por seguridad de filas.
      case 'soporte_resumen': {
        // Mismo interruptor que el resto del panel: sin «Incluir demostraciones», los tickets y entregas de iglesias de demostración no cuentan
        const incluirDemo = body.incluir_demo !== false
        // Las cifras se cuentan en SQL; sin la migración, se leen las filas (por páginas) y se cuentan aquí
        const agg = await admin.rpc('adn_soporte_resumen', { p_incluir_demo: incluirDemo })
        if (!agg.error) return json(salidaSegura({ ok: true, ...resumenDeAgregado((agg.data as Record<string, unknown>[] | null)?.[0]) }))
        if (!faltaLaFuncion(agg.error)) return json({ error: 'No se pudo leer el soporte' }, 500)
        const ahora = new Date().toISOString()
        const [t, n, a, d] = await Promise.all([
          leerTodo<Record<string, any>>((x, h) => admin.from('adn_tickets').select('id, iglesia_id, estado, prioridad').order('id').range(x, h)),
          admin.from('adn_novedades').select('version, publicada_en').is('retirada_en', null).order('publicada_en', { ascending: false }),
          admin.from('adn_avisos').select('id').is('retirado_en', null).lte('desde', ahora).or(`hasta.is.null,hasta.gt.${ahora}`),
          incluirDemo ? Promise.resolve({ data: [], error: null }) : leerTodo<Record<string, any>>((x, h) => admin.from('iglesias').select('id').eq('es_demo', true).order('id').range(x, h)),
        ])
        const fallo = t.error ?? n.error ?? a.error ?? d.error
        if (fallo) return json({ error: faltaLaFuncion(fallo as { message?: string; code?: string }) ? 'El soporte no esta disponible hasta aplicar su migracion' : 'No se pudo leer el soporte' }, faltaLaFuncion(fallo as { message?: string; code?: string }) ? 501 : 500)
        const idsDemo = new Set<string>((d.data ?? []).map((x: { id: string }) => x.id))
        const ids = (a.data ?? []).map((x: { id: string }) => x.id)
        const e = ids.length ? await leerTodo<Record<string, any>>((x, h) => admin.from('adn_avisos_entregas').select('id, aviso_id, iglesia_id, leido_en, descartado_en').in('aviso_id', ids).order('id').range(x, h)) : { data: [], error: null }
        if (e.error) return json({ error: 'No se pudo leer el soporte' }, 500)
        return json(salidaSegura({ ok: true, ...resumenDeSoporte(sinDemos(t.data as any, idsDemo, incluirDemo), n.data, a.data, sinDemos(e.data as any, idsDemo, incluirDemo)) }))
      }

      case 'ticket_listar': {
        // Cifras y asunto: el texto de las conversaciones no sale en la lista
        const estado = ['abierto', 'respondido', 'cerrado'].includes(String(body.estado)) ? String(body.estado) : null
        let q = admin.from('adn_tickets').select('id, iglesia_id, asunto, prioridad, estado, created_at, updated_at, cerrado_en, iglesias(nombre), mensajes:adn_ticket_mensajes(count)')
          .order('updated_at', { ascending: false }).limit(100)
        if (estado) q = q.eq('estado', estado)
        const { data, error } = await q
        if (error) return json({ error: faltaLaFuncion(error) ? 'El soporte no esta disponible hasta aplicar su migracion' : 'No se pudieron leer los tickets' }, faltaLaFuncion(error) ? 501 : 500)
        return json(salidaSegura({ ok: true, tickets: listaDeTickets(data) }))
      }

      case 'ticket_abrir': {
        // Leer el texto de un ticket deja rastro ANTES de entregarlo: si la auditoria no se puede escribir, el texto no sale
        if (!esUuid(body.id)) return json({ error: 'Identificador de ticket no valido' }, 400)
        const { data: t, error } = await admin.from('adn_tickets').select('id, iglesia_id, asunto, prioridad, estado, created_at, updated_at, cerrado_en, iglesias(nombre)').eq('id', body.id).maybeSingle()
        if (error) return json({ error: 'No se pudo leer el ticket' }, 500)
        if (!t) return json({ error: 'El ticket no existe' }, 404)
        const auditado = await auditar('ticket_abrir', t.iglesia_id, { ticket_id: t.id })
        if (!auditado) return json({ error: 'No se pudo registrar la lectura en la auditoria; el ticket no se muestra' }, 503)
        const { data: m, error: eM } = await admin.from('adn_ticket_mensajes').select('id, autor_tipo, texto, created_at').eq('ticket_id', body.id).order('id')
        if (eM) return json({ error: 'No se pudo leer el ticket' }, 500)
        return json(salidaSegura({ ok: true, ticket: ticketAbierto(t, m), auditado }))
      }

      case 'ticket_responder': {
        const v = validarRespuesta(body)
        if (!v.ok) return json({ error: v.error }, 400)
        const { data: t } = await admin.from('adn_tickets').select('id, iglesia_id, estado').eq('id', v.id).maybeSingle()
        if (!t) return json({ error: 'El ticket no existe' }, 404)
        if (t.estado === 'cerrado') return json({ error: 'El ticket esta cerrado' }, 409)
        const { error } = await admin.from('adn_ticket_mensajes').insert({ ticket_id: v.id, autor_tipo: 'plataforma', autor: user?.id ?? null, texto: v.texto })
        if (error) return json({ error: /ADN_TICKET_LLENO/.test(error.message) ? 'El ticket tiene demasiados mensajes' : 'No se pudo responder' }, /ADN_TICKET_/.test(error.message) ? 409 : 500)
        const auditado = await auditar('ticket_responder', t.iglesia_id, { ticket_id: v.id })
        return json({ ok: true, auditado })
      }

      case 'ticket_cerrar': {
        if (!esUuid(body.id)) return json({ error: 'Identificador de ticket no valido' }, 400)
        const { data: t, error } = await admin.from('adn_tickets').update({ estado: 'cerrado', cerrado_en: new Date().toISOString() }).eq('id', body.id).neq('estado', 'cerrado').select('id, iglesia_id').maybeSingle()
        if (error) return json({ error: 'No se pudo cerrar el ticket' }, 500)
        if (!t) return json({ error: 'El ticket no existe o ya esta cerrado' }, 404)
        const auditado = await auditar('ticket_cerrar', t.iglesia_id, { ticket_id: t.id })
        return json({ ok: true, auditado })
      }

      case 'novedad_listar': {
        const { data, error } = await admin.from('adn_novedades').select('id, version, titulo, texto, publicada_en, retirada_en').order('publicada_en', { ascending: false }).limit(50)
        if (error) return json({ error: faltaLaFuncion(error) ? 'El soporte no esta disponible hasta aplicar su migracion' : 'No se pudieron leer las novedades' }, faltaLaFuncion(error) ? 501 : 500)
        return json(salidaSegura({ ok: true, novedades: data }))
      }

      case 'novedad_publicar': {
        const v = validarNovedad(body)
        if (!v.ok) return json({ error: v.error }, 400)
        const { data, error } = await admin.from('adn_novedades').insert({ version: v.version, titulo: v.titulo, texto: v.texto, publicada_por: user?.id ?? null }).select('id').single()
        if (error || !data) return json({ error: 'No se pudo publicar la novedad' }, 500)
        const auditado = await auditar('novedad_publicar', null, { novedad_id: data.id, version: v.version })
        return json({ ok: true, id: data.id, auditado })
      }

      case 'novedad_retirar': {
        if (!esUuid(body.id)) return json({ error: 'Identificador no valido' }, 400)
        const { data, error } = await admin.from('adn_novedades').update({ retirada_en: new Date().toISOString() }).eq('id', body.id).is('retirada_en', null).select('id').maybeSingle()
        if (error) return json({ error: 'No se pudo retirar la novedad' }, 500)
        if (!data) return json({ error: 'La novedad no existe o ya esta retirada' }, 404)
        const auditado = await auditar('novedad_retirar', null, { novedad_id: data.id })
        return json({ ok: true, auditado })
      }

      case 'aviso_listar': {
        const { data, error } = await admin.from('adn_avisos').select('id, tipo, titulo, texto, destino, incluir_demo, desde, hasta, created_at, retirado_en, por_correo, correo_estado').order('created_at', { ascending: false }).limit(50)
        if (error) return json({ error: faltaLaFuncion(error) ? 'El soporte no esta disponible hasta aplicar su migracion' : 'No se pudieron leer los avisos' }, faltaLaFuncion(error) ? 501 : 500)
        const ids = (data ?? []).map((x: { id: string }) => x.id)
        // Entregas, lecturas y descartes se cuentan en SQL; sin la migración, se leen las filas por páginas y se cuentan aquí
        let est: Record<string, { entregas: number; leidos: number; descartados: number }> = {}
        if (ids.length) {
          const agg = await admin.rpc('adn_avisos_estadisticas', { p_ids: ids })
          if (!agg.error) est = estadisticasDeAgregado(agg.data)
          else if (faltaLaFuncion(agg.error)) {
            const e = await leerTodo<Record<string, any>>((x, h) => admin.from('adn_avisos_entregas').select('id, aviso_id, leido_en, descartado_en').in('aviso_id', ids).order('id').range(x, h))
            if (e.error) return json({ error: 'No se pudieron leer los avisos' }, 500)
            est = estadisticasDeAvisos(e.data as any)
          } else return json({ error: 'No se pudieron leer los avisos' }, 500)
        }
        return json(salidaSegura({ ok: true, avisos: (data ?? []).map((a: { id: string }) => ({ ...a, ...(est[a.id] ?? { entregas: 0, leidos: 0, descartados: 0 }) })) }))
      }

      case 'aviso_crear': {
        const v = validarAviso(body)
        if (!v.ok) return json({ error: v.error }, 400)
        const config = leerConfig(k => Deno.env.get(k))
        // El correo masivo no se envia: solo se anota si se pidio y si el interruptor general (ADN_ENVIO_ACTIVO) esta apagado
        const correo = correoDeAviso(v.aviso.por_correo, config.activo)
        if (correo === 'sin_envio') return json({ error: 'El envio masivo de correo aun no esta construido: crea el aviso sin correo' }, 409)
        const { data, error } = await admin.from('adn_avisos').insert({ ...v.aviso, correo_estado: correo, creado_por: user?.id ?? null }).select('id').single()
        if (error || !data) return json({ error: faltaLaFuncion(error) ? 'Los avisos no estan disponibles hasta aplicar la migracion del soporte' : 'No se pudo crear el aviso' }, faltaLaFuncion(error) ? 501 : 500)
        const { data: n, error: eEntrega } = await admin.rpc('adn_aviso_entregar', { p_aviso: data.id })
        if (eEntrega) {
          // Un aviso sin reparto no debe quedar vigente: se retira para que nadie lo vea a medias
          await admin.from('adn_avisos').update({ retirado_en: new Date().toISOString() }).eq('id', data.id)
          return json({ error: 'No se pudo repartir el aviso' }, 500)
        }
        const auditado = await auditar('aviso_crear', null, { aviso_id: data.id, tipo: v.aviso.tipo, destino: v.aviso.destino, entregas: n, correo })
        return json({ ok: true, id: data.id, entregas: Number(n) || 0, correo, auditado })
      }

      case 'aviso_retirar': {
        if (!esUuid(body.id)) return json({ error: 'Identificador no valido' }, 400)
        const { data, error } = await admin.from('adn_avisos').update({ retirado_en: new Date().toISOString() }).eq('id', body.id).is('retirado_en', null).select('id').maybeSingle()
        if (error) return json({ error: 'No se pudo retirar el aviso' }, 500)
        if (!data) return json({ error: 'El aviso no existe o ya esta retirado' }, 404)
        const auditado = await auditar('aviso_retirar', null, { aviso_id: data.id })
        return json({ ok: true, auditado })
      }

      // ---- Facturacion en modo de prueba: solo estima el ingreso mensual esperado con el precio que alguien haya fijado. No cobra ni conecta ninguna pasarela.
      case 'facturacion_simulacion': {
        // Las iglesias se cuentan en SQL (agrupadas por plan, etapa, demo y borrado). Sin la migración, se leen por páginas y se cuentan aquí
        const [agg, { data: planes, error: e2 }] = await Promise.all([admin.rpc('adn_plataforma_facturacion'), admin.from('planes').select('*').order('orden')])
        let filas: Parameters<typeof simular>[0]
        if (!agg.error) filas = filasDeFacturacion(agg.data)
        else if (faltaLaFuncion(agg.error)) {
          const r = await leerTodo<Record<string, any>>((d, h) => admin.from('iglesias').select('plan, activa, etapa, es_demo, adn_borrada_en').order('created_at').order('id').range(d, h))
          if (r.error) return json({ error: 'No se pudo leer la facturacion' }, 500)
          filas = r.data as Parameters<typeof simular>[0]
        } else return json({ error: 'No se pudo leer la facturacion' }, 500)
        if (e2) return json({ error: 'No se pudo leer la facturacion' }, 500)
        // Si la migracion de precios aun no esta aplicada, las columnas no vienen: todos los planes salen «sin precio», que es la verdad
        const migrado = (planes ?? []).length === 0 || 'precio_mensual_centimos' in (planes as Record<string, unknown>[])[0]
        return json({ ok: true, migrado, ...simular(filas, planes) })
      }

      case 'plan_precio_fijar': {
        const v = validarPrecio(body)
        if (!v.ok) return json({ error: v.error }, 400)
        const { data: plan } = await admin.from('planes').select('clave').eq('clave', v.clave).maybeSingle()
        if (!plan) return json({ error: 'El plan no existe' }, 404)
        const { error } = await admin.from('planes').update({ precio_mensual_centimos: v.mensual, precio_anual_centimos: v.anual, moneda: v.moneda }).eq('clave', v.clave)
        if (error) return json({ error: faltaLaFuncion(error) ? 'Los precios no estan disponibles hasta aplicar su migracion' : 'No se pudo guardar el precio' }, faltaLaFuncion(error) ? 501 : 500)
        const auditado = await auditar('plan_precio_fijar', null, { plan: v.clave, mensual: v.mensual, anual: v.anual, moneda: v.moneda })
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
