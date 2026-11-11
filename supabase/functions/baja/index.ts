import { createClient } from 'npm:@supabase/supabase-js@2'
import { leerPeticion } from './entrada.ts'

// Baja por enlace (/baja/<secreto>): la persona que recibe un mensaje confirma que no quiere recibir más por ese canal.
// Se despliega sin verificar JWT (la abre cualquiera con el enlace). Solo acepta POST: un GET de un analizador de correo
// que "visita" el enlace no puede gastarlo; la página pide una confirmación explícita y es ella quien hace el POST.
// El secreto tiene 244 bits aleatorios y la base guarda solo su huella. La respuesta no revela nada de la persona
// ni de la iglesia: solo si se dio de baja, el canal, o por qué no (inválido, usado o caducado).
// Tambien acepta la baja de un clic de los programas de correo (cabecera List-Unsubscribe, RFC 8058): ver entrada.ts.
// Enviar de verdad los enlaces (correo con el enlace) NO existe todavía: esta función solo consume los que se creen con
// adn_baja_crear_enlace.

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
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405)

  try {
    const peticion = leerPeticion(req.url, req.headers.get('Content-Type'), await req.text())
    if (!peticion) return json({ ok: false, motivo: 'invalido' }, new URL(req.url).searchParams.has('t') ? 400 : 200)
    const { token, modo } = peticion

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } })
    const { data, error } = await admin.rpc('adn_baja_consumir', { p_token: token })
    if (error || !data) {
      console.error('baja', error?.message ?? 'sin datos')
      return json({ error: 'Error interno' }, 500)
    }
    const r = data as { ok: boolean; canal?: string; motivo?: string }
    // La baja de un clic de un programa de correo espera un 2xx si se hizo y no lee el cuerpo
    if (modo === 'una_clic') return r.ok ? json({ ok: true }) : json({ ok: false, motivo: r.motivo ?? 'invalido' }, 400)
    return json(r.ok ? { ok: true, canal: r.canal } : { ok: false, motivo: r.motivo ?? 'invalido' })
  } catch (e) {
    console.error('baja', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
