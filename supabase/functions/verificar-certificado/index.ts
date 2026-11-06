import { createClient } from 'npm:@supabase/supabase-js@2'
import { codigoDe, respuestaDe } from './validar.ts'

// Verificacion publica de certificados de formacion (/verificar/<codigo>). No hay sesion: solo el codigo del QR.
// La consulta vive en la base de datos (info_certificado, que solo ejecuta el servidor) y devuelve lo minimo: estado,
// iglesia, programa, fecha y el titular reducido (nombre e inicial del apellido). Un certificado revocado no muestra al titular.

const ORIGENES_PERMITIDOS = ['https://viveadn.com', 'https://www.viveadn.com', 'https://viveadn-web-app.vercel.app', 'http://localhost:5173']
const MAX_CUERPO = 1024

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
  const json = (cuerpo: unknown, status = 200) =>
    new Response(JSON.stringify(cuerpo), { status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405)

  try {
    const bruto = await req.text()
    if (bruto.length > MAX_CUERPO) return json({ error: 'datos' }, 413)
    let cuerpo: unknown = null
    try { cuerpo = JSON.parse(bruto) } catch { return json({ error: 'datos' }, 400) }
    const codigo = codigoDe(cuerpo)
    if (!codigo) return json({ error: 'no_valido' }, 404)

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } })
    const { data, error } = await admin.rpc('info_certificado', { p_codigo: codigo })
    if (error) { console.error('info_certificado', error.message); return json({ error: 'interno' }, 500) }
    const r = respuestaDe(data)
    return json(r.cuerpo, r.status)
  } catch (e) {
    console.error('verificar-certificado', e instanceof Error ? e.message : e)
    return json({ error: 'interno' }, 500)
  }
})
