import { createClient } from 'npm:@supabase/supabase-js@2'

// Baja por enlace (/baja/<secreto>): la persona que recibe un mensaje confirma que no quiere recibir más por ese canal.
// Se despliega sin verificar JWT (la abre cualquiera con el enlace). Solo acepta POST: un GET de un analizador de correo
// que "visita" el enlace no puede gastarlo; la página pide una confirmación explícita y es ella quien hace el POST.
// El secreto tiene 244 bits aleatorios y la base guarda solo su huella. La respuesta no revela nada de la persona
// ni de la iglesia: solo si se dio de baja, el canal, o por qué no (inválido, usado o caducado).
// Enviar de verdad los enlaces (correo con el enlace) NO existe todavía: esta función solo consume los que se creen con
// adn_baja_crear_enlace.

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

const TOKEN_RE = /^[0-9a-f]{64}$/

Deno.serve(async (req) => {
  const cors = corsPara(req)
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405)

  try {
    const body = await req.json().catch(() => ({}))
    const token = String(body.token ?? '').trim().toLowerCase()
    if (!TOKEN_RE.test(token)) return json({ ok: false, motivo: 'invalido' })

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } })
    const { data, error } = await admin.rpc('adn_baja_consumir', { p_token: token })
    if (error || !data) {
      console.error('baja', error?.message ?? 'sin datos')
      return json({ error: 'Error interno' }, 500)
    }
    const r = data as { ok: boolean; canal?: string; motivo?: string }
    return json(r.ok ? { ok: true, canal: r.canal } : { ok: false, motivo: r.motivo ?? 'invalido' })
  } catch (e) {
    console.error('baja', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
