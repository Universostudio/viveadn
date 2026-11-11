import { createClient } from 'npm:@supabase/supabase-js@2'
import { claveCronValida, construirCorreo } from './correo.ts'

// Envío de los correos de confirmación de la suscripción (doble confirmación del registro por QR).
// TODO ESTÁ APAGADO POR DEFECTO, con tres cerrojos independientes:
//  1. La clave de la tarea programada (cabecera x-adn-cron, ADN_CRON_SECRET): sin ella responde 403 y no hace nada.
//  2. El interruptor ADN_CONFIRMACION_ACTIVA=1 de la función: si no está, responde {activo:false} sin tocar la base de datos.
//  3. El ajuste adn_doble_confirmacion de la base: apagado, no hay solicitudes preparadas ni se crean.
// Además necesita BIRD_API_KEY. Nadie la llama hoy: no hay tarea programada ni se ha desplegado.
// [NV] Que el proveedor acepte las cabeceras List-Unsubscribe en este campo no está comprobado contra el proveedor real.

Deno.serve(async (req) => {
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405)
  if (!(await claveCronValida(req.headers.get('x-adn-cron'), Deno.env.get('ADN_CRON_SECRET')))) return json({ error: 'Sin permiso' }, 403)
  if (Deno.env.get('ADN_CONFIRMACION_ACTIVA') !== '1') return json({ activo: false })

  const clave = Deno.env.get('BIRD_API_KEY')
  const url = Deno.env.get('SUPABASE_URL')!
  const web = Deno.env.get('ADN_WEB_URL') ?? 'https://viveadn.com'
  const soporte = Deno.env.get('ADN_EMAIL_SOPORTE')?.trim() || 'soporte@viveadn.com'
  if (!clave) return json({ activo: true, error: 'Sin proveedor de correo' }, 503)

  try {
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } })
    const dias = 3
    const { data, error } = await admin.rpc('adn_confirmacion_preparar', { p_max: 20, p_dias: dias })
    if (error) { console.error('enviar-confirmaciones', error.message); return json({ error: 'Error interno' }, 500) }
    const region = /^bk_([a-z0-9]+)_/.exec(clave)?.[1] ?? 'eu1'
    let enviadas = 0, fallidas = 0
    for (const f of (data ?? []) as { id: string; destino: string; idioma: string | null; nombre: string; iglesia: string; token: string; baja_token: string }[]) {
      let ok = false
      try {
        const c = construirCorreo({ destino: f.destino, nombre: f.nombre, iglesia: f.iglesia, idioma: f.idioma, token: f.token, bajaToken: f.baja_token, web, funciones: url, dias })
        const r = await fetch(`https://${region}.platform.bird.com/v1/email/messages`, {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${clave}`, 'Content-Type': 'application/json', 'Idempotency-Key': `confirmacion/${f.id}` },
          body: JSON.stringify({
            from: { email: 'no-responder@viveadn.com', name: 'Vive ADN' }, to: [{ email: f.destino, name: f.nombre }],
            reply_to: [{ email: soporte, name: 'Soporte Vive ADN' }], subject: c.asunto, html: c.html, text: c.texto,
            headers: c.cabeceras, category: 'transactional', track_clicks: false, track_opens: false,
          }),
        })
        ok = r.ok
        // Sin correos ni secretos en el registro: solo el estado del proveedor
        if (!r.ok) console.error('enviar-confirmaciones', 'proveedor', r.status)
      } catch (e) { console.error('enviar-confirmaciones', e instanceof Error ? e.message : 'fallo') }
      if (ok) enviadas++
      else { fallidas++; await admin.rpc('adn_confirmacion_fallida', { p_id: f.id }) }
    }
    return json({ activo: true, enviadas, fallidas })
  } catch (e) {
    console.error('enviar-confirmaciones', e instanceof Error ? e.message : e)
    return json({ error: 'Error interno' }, 500)
  }
})
