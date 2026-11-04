import { createClient } from 'npm:@supabase/supabase-js@2'

// Pagina publica para dar (/dar/<slug>): devuelve solo el nombre de la iglesia y las direcciones
// activas de recaudo que ella misma decidio publicar. No expone nada mas de la iglesia.
// Respuesta uniforme 404 si la iglesia no existe, esta inactiva o no tiene enlaces activos.

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
const ORDEN: Record<string, number> = { diezmo: 1, ofrenda: 2, donacion: 3 }

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

    const { data: filas } = await admin.from('enlaces_dar').select('tipo, url').eq('iglesia_id', ig.id).eq('activo', true)
    const enlaces = (filas ?? [])
      .filter(f => typeof f.url === 'string' && f.url.startsWith('https://'))
      .sort((a, b) => (ORDEN[a.tipo] ?? 9) - (ORDEN[b.tipo] ?? 9))
    if (!enlaces.length) return noDisponible()

    return json({ iglesia: ig.nombre, enlaces })
  } catch (e) {
    console.error('dar-publico', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
