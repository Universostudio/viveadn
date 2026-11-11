import { createClient } from 'npm:@supabase/supabase-js@2'
import { errorDeAutoservicio, validarBaja, validarPagina } from './autoservicio.ts'
import { avisoBaja, enviarAviso, IDIOMAS, leerConfig, type ResultadoEnvio, type TipoEnvio } from './envio.ts'

// Autoservicio del propietario de la iglesia: descargar todos sus datos y pedir o cancelar la baja.
// Usa service_role, asi que cada entrada se valida aqui y otra vez en la base (adn_es_propietario).
// Quien llama es siempre el usuario de la sesion; la iglesia sale de su perfil, nunca de lo que envie el navegador.
// Funciona tambien con la iglesia suspendida (la baja la suspende): el propietario debe poder descargar y cancelar dentro del plazo.

// Entornos de prueba: ADN_ORIGENES_EXTRA añade direcciones de la web (https exactas, separadas por comas, hasta 10). En producción no se define.
const ORIGENES_EXTRA = (Deno.env.get('ADN_ORIGENES_EXTRA') ?? '').split(',').map(s => s.trim()).filter(s => /^https:\/\/[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:\d{1,5})?$/.test(s)).slice(0, 10)
const ORIGENES_PERMITIDOS = ['https://viveadn.com', 'https://www.viveadn.com', 'https://viveadn-web-app.vercel.app', ...ORIGENES_EXTRA, 'http://localhost:5173']

const corsPara = (req: Request) => {
  const origen = req.headers.get('Origin') ?? ''
  return {
    'Access-Control-Allow-Origin': ORIGENES_PERMITIDOS.includes(origen) ? origen : ORIGENES_PERMITIDOS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

// Cubos con archivos de iglesia; la primera carpeta de cada ruta es el id de la iglesia
const CUBOS_IGLESIA = ['iglesia-marca', 'iglesia-archivos']

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

    // 1. Quien llama: la sesion. Su iglesia es la de su perfil
    const userClient = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } })
    const { data: { user } } = await userClient.auth.getUser()
    if (!user) return json({ error: 'No autenticado' }, 401)
    const { data: perfil } = await admin.from('perfiles').select('iglesia_id').eq('id', user.id).maybeSingle()
    const iglesiaId: string | null = perfil?.iglesia_id ?? null
    if (!iglesiaId) return json({ error: 'Solo el propietario de la iglesia puede hacerlo' }, 403)

    const body = await req.json().catch(() => ({}))
    const falloDe = (mensaje: string | undefined) => { const e = errorDeAutoservicio(mensaje); return json({ error: e.mensaje }, e.estado) }

    // Cada entrada comprueba otra vez que quien llama es el propietario activo: una cuenta desactivada pierde el acceso al instante
    const { data: esPropietario } = await admin.rpc('adn_es_propietario', { p_iglesia: iglesiaId, p_actor: user.id })
    if (esPropietario !== true) return json({ error: 'Solo el propietario de la iglesia puede hacerlo' }, 403)

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

    // Aviso por correo al propietario (docs/COSTE-ENVIO.md). Nunca rompe la baja: devuelve el estado del envio y ya.
    // Apagado por defecto; solo sale a la direccion del perfil de quien actua, que ya esta registrada
    const avisarBaja = async (accion: 'pedida' | 'cancelada', purgaEl: string | null): Promise<ResultadoEnvio['estado']> => {
      try {
        const config = leerConfig(k => Deno.env.get(k))
        const { data: yo } = await admin.from('perfiles').select('email').eq('id', user.id).maybeSingle()
        const { data: ig } = await admin.from('iglesias').select('nombre').eq('id', iglesiaId).maybeSingle()
        const idioma = IDIOMAS.includes(body.idioma) ? body.idioma : 'es'
        const fecha = purgaEl ? new Date(purgaEl).toLocaleDateString(idioma, { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }) : undefined
        const c = avisoBaja(accion, { idioma, iglesia: ig?.nombre ?? '', fecha, soporte: config.soporte })
        const r = await enviarAviso({
          tipo: 'baja', iglesia: iglesiaId, destino: String(yo?.email ?? ''), destinoRegistrado: !!yo?.email,
          ...c, idempotencia: `baja/${iglesiaId}/${accion}/${purgaEl ?? new Date().toISOString().slice(0, 13)}`,
        }, {
          config,
          reservar: async (tipo: TipoEnvio, igl, topeI, topeT, topeG) => {
            const { data, error } = await admin.rpc('adn_envio_reservar', { p_tipo: tipo, p_iglesia: igl, p_tope_iglesia: topeI, p_tope_tipo: topeT, p_tope_global: topeG })
            if (error) throw new Error(error.message)
            return String(data)
          },
          liberar: async (tipo: TipoEnvio, igl) => { await admin.rpc('adn_envio_liberar', { p_tipo: tipo, p_iglesia: igl }) },
          fetchFn: fetch, log: (...a) => console.error('aviso de baja', ...a),
        })
        return r.estado
      } catch (e) {
        console.error('aviso de baja', e instanceof Error ? e.message : e)
        return 'fallo'
      }
    }

    switch (body.accion) {
      case 'estado': {
        const { data, error } = await admin.rpc('adn_autoservicio_estado', { p_iglesia: iglesiaId, p_actor: user.id })
        if (error || !data) return falloDe(error?.message)
        return json({ ok: true, estado: data })
      }

      case 'exportar_plan': {
        // Una descarga completa: se anota aqui (con el limite de 6 por hora), una sola vez, y despues el navegador pide cada pagina
        const { error: eAnotar } = await admin.rpc('adn_autoservicio_exportar', { p_iglesia: iglesiaId, p_actor: user.id })
        if (eAnotar) return falloDe(eAnotar.message)
        const { data, error } = await admin.rpc('adn_exportar_plan', { p_iglesia: iglesiaId })
        if (error || !data) return json({ error: 'No se pudo preparar la descarga' }, 500)
        let archivos: Record<string, unknown> = {}
        try {
          for (const cubo of CUBOS_IGLESIA) archivos[cubo] = await listarArchivos(cubo, iglesiaId)
        } catch {
          archivos = { error: 'No se pudo listar el almacenamiento' }
        }
        return json({ ok: true, plan: { ...(data as Record<string, unknown>), archivos } })
      }

      case 'exportar_pagina': {
        const v = validarPagina(body)
        if (!v.ok) return json({ error: v.error }, 400)
        const { data, error } = await admin.rpc('adn_exportar_pagina',
          { p_iglesia: iglesiaId, p_tabla: v.pagina.tabla, p_formato: v.pagina.formato, p_despues: v.pagina.despues, p_limite: v.pagina.limite })
        if (error) {
          if (/ADN_TABLA_NO_EXPORTABLE|ADN_FORMATO_INVALIDO|ADN_CURSOR_INVALIDO|invalid input syntax/.test(error.message)) return json({ error: 'Peticion no valida' }, 400)
          console.error('exportar_pagina', error.message)
          return json({ error: 'No se pudo leer la pagina' }, 500)
        }
        return json({ ok: true, pagina: data })
      }

      case 'solicitar_baja': {
        // No borra nada: suspende la iglesia y fija la purga a 30 dias. Dentro del plazo el propietario puede cancelarla
        const { data: ig } = await admin.from('iglesias').select('slug').eq('id', iglesiaId).maybeSingle()
        if (!ig) return json({ error: 'La iglesia no existe' }, 404)
        const v = validarBaja(body, ig.slug)
        if (!v.ok) return json({ error: v.error }, 400)
        const { data: purgaEl, error } = await admin.rpc('adn_autoservicio_baja', { p_iglesia: iglesiaId, p_actor: user.id, p_motivo: v.motivo })
        if (error) return falloDe(error.message)
        const aviso = await avisarBaja('pedida', String(purgaEl))
        return json({ ok: true, purga_el: purgaEl, aviso })
      }

      case 'cancelar_baja': {
        const motivo = String(body.motivo ?? '').trim().slice(0, 500) || null
        const { data: etapa, error } = await admin.rpc('adn_autoservicio_cancelar_baja', { p_iglesia: iglesiaId, p_actor: user.id, p_motivo: motivo })
        if (error) return falloDe(error.message)
        const aviso = await avisarBaja('cancelada', null)
        return json({ ok: true, etapa, aviso })
      }

      default:
        return json({ error: 'Accion no valida' }, 400)
    }
  } catch (e) {
    console.error('datos-iglesia', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
