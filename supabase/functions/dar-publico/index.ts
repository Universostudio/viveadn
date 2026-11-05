import { createClient } from 'npm:@supabase/supabase-js@2'

// Pagina publica para dar (/dar/<slug>): devuelve el nombre de la iglesia, su apariencia y los fondos
// activos con la direccion de recaudo que ella misma decidio publicar. No expone nada mas de la iglesia.
// Respuesta uniforme 404 si la iglesia no existe, esta inactiva o no tiene fondos activos.
// "enlaces" se mantiene (tipo y url) para la version anterior de la pagina durante el despliegue.

const ORIGENES_PERMITIDOS = ['https://viveadn.com', 'https://www.viveadn.com', 'https://viveadn-web-app.vercel.app', 'http://localhost:5173']

const corsPara = (req: Request) => {
  const origen = req.headers.get('Origin') ?? ''
  return {
    'Access-Control-Allow-Origin': ORIGENES_PERMITIDOS.includes(origen) ? origen : ORIGENES_PERMITIDOS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

const SLUG_RE = /^[a-z0-9][a-z0-9-]{0,62}$/
const COLOR_RE = /^#[0-9a-fA-F]{6}$/
const ORIGINALES: Record<string, number> = { diezmo: 1, ofrenda: 2, donacion: 3 }
const POR_DEFECTO = { plantilla: 'clasica', titulo: null, subtitulo: null, color_primario: '#00523c', color_acento: '#f5a623', logo_url: null, calculadora: 'dia', moneda: 'EUR' }

Deno.serve(async (req) => {
  const cors = corsPara(req)
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405)

  try {
    const body = await req.json().catch(() => ({}))
    const slug = String(body.slug ?? '').trim().toLowerCase()
    const noDisponible = () => json({ error: 'Esta pagina no esta disponible' }, 404)
    if (!SLUG_RE.test(slug)) return noDisponible()

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } })
    const { data: ig } = await admin.from('iglesias').select('id, nombre').eq('slug', slug).eq('activa', true).maybeSingle()
    if (!ig) return noDisponible()

    const [{ data: filas }, { data: conf }] = await Promise.all([
      admin.from('enlaces_dar').select('tipo, url, nombre, descripcion, orden').eq('iglesia_id', ig.id).eq('activo', true),
      admin.from('dar_config').select('plantilla, titulo, subtitulo, color_primario, color_acento, logo_url, calculadora, moneda').eq('iglesia_id', ig.id).maybeSingle(),
    ])
    const fondos = (filas ?? [])
      .filter(f => typeof f.url === 'string' && f.url.startsWith('https://'))
      .sort((a, b) => (a.orden - b.orden) || ((ORIGINALES[a.tipo] ?? 9) - (ORIGINALES[b.tipo] ?? 9)) || a.tipo.localeCompare(b.tipo))
    if (!fondos.length) return noDisponible()

    // Defensa en profundidad: aunque la base ya lo valida, aqui solo salen colores y logos con forma segura
    const config = { ...POR_DEFECTO, ...(conf ?? {}) }
    if (!COLOR_RE.test(config.color_primario)) config.color_primario = POR_DEFECTO.color_primario
    if (!COLOR_RE.test(config.color_acento)) config.color_acento = POR_DEFECTO.color_acento
    if (config.logo_url && !String(config.logo_url).startsWith('https://')) config.logo_url = null

    return json({ iglesia: ig.nombre, config, fondos, enlaces: fondos.map(f => ({ tipo: f.tipo, url: f.url })) })
  } catch (e) {
    console.error('dar-publico', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
