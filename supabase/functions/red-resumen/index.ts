import { createClient } from 'npm:@supabase/supabase-js@2'

// Panel de red: la iglesia madre ve cifras agregadas de sus sedes.
// Solo lo pide el superadministrador de la madre. Cada sede aparece segun el acceso que la plataforma
// haya concedido: con 'ninguno' solo se muestra el nombre y la ciudad, nunca cifras ni personas.
// Usa service_role, asi que cada entrada se valida aqui y solo salen conteos.

// Entornos de prueba: ADN_ORIGENES_EXTRA añade direcciones de la web (https exactas, separadas por comas, hasta 10). En producción no se define.
const ORIGENES_EXTRA = (Deno.env.get('ADN_ORIGENES_EXTRA') ?? '').split(',').map(s => s.trim()).filter(s => /^https:\/\/[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:\d{1,5})?$/.test(s)).slice(0, 10)
const ORIGENES_PERMITIDOS = ['https://viveadn.com', 'https://www.viveadn.com', 'https://viveadn-web-app.vercel.app', 'http://localhost:5173', ...ORIGENES_EXTRA]

const corsPara = (req: Request) => {
  const origen = req.headers.get('Origin') ?? ''
  return {
    'Access-Control-Allow-Origin': ORIGENES_PERMITIDOS.includes(origen) ? origen : ORIGENES_PERMITIDOS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

Deno.serve(async (req) => {
  const cors = corsPara(req)
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405)

  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    })
    const { data: { user } } = await userClient.auth.getUser()
    if (!user) return json({ error: 'No autenticado' }, 401)

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } })

    // Quien llama debe ser superadministrador activo de su iglesia
    const { data: perfil } = await admin.from('perfiles').select('iglesia_id, rol, activo').eq('id', user.id).maybeSingle()
    if (!perfil?.iglesia_id || perfil.activo !== true) return json({ error: 'Sin permiso' }, 403)
    const { data: rol } = await admin.from('roles').select('es_propietario').eq('iglesia_id', perfil.iglesia_id).eq('clave', perfil.rol).maybeSingle()
    if (rol?.es_propietario !== true) return json({ error: 'Sin permiso' }, 403)

    const { data: sedes } = await admin.from('iglesias')
      .select('id, nombre, pais, ciudad, activa, red_acceso').eq('iglesia_madre_id', perfil.iglesia_id).order('nombre')
    if (!sedes?.length) return json({ sedes: [], propia: null, totales: null, total: 0 })
    const cuerpo = await req.clone().json().catch(() => ({}))
    // Para decidir si se muestra el menu basta con saber cuantas sedes hay
    if (cuerpo?.solo_contar === true) return json({ total: sedes.length })

    const cifras = async (id: string) => {
      const [m, c, o, a] = await Promise.all([
        admin.from('miembros').select('id', { count: 'exact', head: true }).eq('iglesia_id', id).eq('activo', true),
        admin.from('casas_oracion').select('id', { count: 'exact', head: true }).eq('iglesia_id', id).eq('activa', true),
        admin.from('consolidaciones').select('id', { count: 'exact', head: true }).eq('iglesia_id', id).eq('completado', false),
        admin.from('consolidaciones').select('id', { count: 'exact', head: true }).eq('iglesia_id', id).eq('completado', false).eq('estado_alerta', 'rojo'),
      ])
      return { miembros: m.count ?? 0, casas: c.count ?? 0, consolidaciones: o.count ?? 0, alertas: a.count ?? 0 }
    }

    const visibles = sedes.filter(s => s.activa && s.red_acceso === 'resumen')
    const [propia, ...deSedes] = await Promise.all([cifras(perfil.iglesia_id), ...visibles.map(s => cifras(s.id))])
    const porId = new Map(visibles.map((s, i) => [s.id, deSedes[i]]))

    const salida = sedes.map(s => ({
      id: s.id, nombre: s.nombre, pais: s.pais, ciudad: s.ciudad, activa: s.activa, acceso: s.red_acceso,
      resumen: porId.get(s.id) ?? null,
    }))
    const totales = [propia, ...deSedes].reduce((t, c) => ({
      miembros: t.miembros + c.miembros, casas: t.casas + c.casas, consolidaciones: t.consolidaciones + c.consolidaciones, alertas: t.alertas + c.alertas,
    }), { miembros: 0, casas: 0, consolidaciones: 0, alertas: 0 })

    return json({ sedes: salida, propia, totales })
  } catch (e) {
    console.error('red-resumen', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
