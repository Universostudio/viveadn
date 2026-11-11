import { createClient } from 'npm:@supabase/supabase-js@2'

// Confirmación de la suscripción por correo (/confirmar/<secreto>): quien se registró por QR confirma que quiere recibir
// mensajes. Se despliega sin verificar JWT (la abre cualquiera con el enlace). Solo POST: un GET de una vista previa o de un
// analizador de correo no puede gastar el enlace; la página pide una confirmación explícita y es ella quien hace el POST.
// La respuesta no revela nada de la persona ni de la iglesia, ni si el consentimiento llegó a cambiar.
// La doble confirmación está apagada por defecto (ajuste adn_doble_confirmacion): sin ella no existen solicitudes que confirmar.

const ORIGENES_PERMITIDOS = ['https://viveadn.com', 'https://www.viveadn.com', 'https://viveadn-web-app.vercel.app', 'http://localhost:5173']
const TOKEN_RE = /^[0-9a-f]{64}$/

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
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405)

  try {
    const body = await req.json().catch(() => ({}))
    const token = String(body.token ?? '').trim().toLowerCase()
    if (!TOKEN_RE.test(token)) return json({ ok: false, motivo: 'invalido' })

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } })
    const { data, error } = await admin.rpc('adn_confirmacion_consumir', { p_token: token })
    if (error || !data) {
      console.error('confirmar-suscripcion', error?.message ?? 'sin datos')
      return json({ error: 'Error interno' }, 500)
    }
    const r = data as { ok: boolean; canal?: string; motivo?: string }
    return json(r.ok ? { ok: true, canal: r.canal } : { ok: false, motivo: r.motivo ?? 'invalido' })
  } catch (e) {
    console.error('confirmar-suscripcion', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
