import { createClient } from 'npm:@supabase/supabase-js@2'
import { TOKEN_RE, validarRegistro, respuestaDe } from './validar.ts'

// Registro por QR (/checkin/<token>). Es publica: no hay sesion, solo el enlace secreto del evento.
// Toda la logica (ventana, tope, limite por dispositivo, duplicados) vive en la base de datos, en
// info_checkin y registrar_checkin, que solo ejecuta el servidor. Aqui se valida lo recibido, se
// cifra la IP (solo se guarda su huella) y se traduce la respuesta sin revelar si la persona ya existia.

// Entornos de prueba: ADN_ORIGENES_EXTRA añade direcciones de la web (https exactas, separadas por comas, hasta 10). En producción no se define.
const ORIGENES_EXTRA = (Deno.env.get('ADN_ORIGENES_EXTRA') ?? '').split(',').map(s => s.trim()).filter(s => /^https:\/\/[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:\d{1,5})?$/.test(s)).slice(0, 10)
const ORIGENES_PERMITIDOS = ['https://viveadn.com', 'https://www.viveadn.com', 'https://viveadn-web-app.vercel.app', 'http://localhost:5173', ...ORIGENES_EXTRA]
const MAX_CUERPO = 4096

const corsPara = (req: Request) => {
  const origen = req.headers.get('Origin') ?? ''
  return {
    'Access-Control-Allow-Origin': ORIGENES_PERMITIDOS.includes(origen) ? origen : ORIGENES_PERMITIDOS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

// Huella de la IP: HMAC con una clave que nunca sale del servidor, para que no se pueda deshacer
async function huellaIp(ip: string, clave: string) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(`checkin-ip:${clave}`), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const firma = await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(ip))
  return [...new Uint8Array(firma)].map(b => b.toString(16).padStart(2, '0')).join('')
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
    let b: Record<string, unknown> = {}
    try { b = JSON.parse(bruto) } catch { return json({ error: 'datos' }, 400) }
    if (typeof b !== 'object' || b === null || Array.isArray(b)) return json({ error: 'datos' }, 400)

    const token = typeof b.token === 'string' ? b.token : ''
    if (!TOKEN_RE.test(token)) return json({ error: 'no_valido' }, 404)

    const servicio = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, servicio, { auth: { persistSession: false, autoRefreshToken: false } })

    if (b.accion === 'consultar') {
      const { data, error } = await admin.rpc('info_checkin', { p_token: token })
      if (error) { console.error('info_checkin', error.message); return json({ error: 'interno' }, 500) }
      return data ? json(data) : json({ error: 'no_valido' }, 404)
    }

    if (b.accion === 'registrar') {
      const v = validarRegistro(b)
      // Un robot recibe un exito falso y no se guarda nada
      if (!v.ok && v.error === 'bot') return json({ ok: true })
      if (!v.ok) return json({ error: v.error }, 400)
      const ip = req.headers.get('cf-connecting-ip') ?? req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'desconocida'
      const { data, error } = await admin.rpc('registrar_checkin', {
        p_token: token, p_nombre: v.datos.nombre, p_apellido: v.datos.apellido,
        p_email: v.datos.email, p_telefono: v.datos.telefono, p_ip_hash: await huellaIp(ip, servicio),
        p_texto_version: v.datos.textoVersion || null, p_idioma: v.datos.idioma || null,
        p_canales: v.datos.canales.length ? v.datos.canales : null,
      })
      if (error) { console.error('registrar_checkin', error.message); return json({ error: 'interno' }, 500) }
      const r = respuestaDe(String(data))
      return json(r.cuerpo, r.status)
    }

    return json({ error: 'accion' }, 400)
  } catch (e) {
    console.error('checkin-evento', e instanceof Error ? e.message : e)
    return json({ error: 'interno' }, 500)
  }
})
