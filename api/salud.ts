// Ruta de salud: GET /api/salud. Responde solo si la web está viva y el servicio de Auth contesta a tiempo.
// La respuesta es mínima a propósito: {"ok":true} con 200 o {"ok":false} con 503. No devuelve versiones, tiempos,
// nombres de servicios ni mensajes de error, porque es pública y cualquiera puede llamarla.
// La caché de la plataforma (30 s) evita que una llamada repetida llegue siempre al servicio de Auth.
// Solo sintaxis que Node entiende al quitar los tipos, para poder probarla sin compilar (npm run test:salud).

export interface Comprobacion { ok: boolean }
type Peticion = (url: string, init: { headers: Record<string, string>; signal: AbortSignal }) => Promise<{ ok: boolean }>

export async function comprobarSalud(url: string | undefined, clave: string | undefined, peticion: Peticion, ms = 3000): Promise<Comprobacion> {
  if (!url || !clave || !/^https:\/\/[a-z0-9.-]+$/i.test(url.replace(/\/+$/, ''))) return { ok: false }
  const control = new AbortController()
  const plazo = setTimeout(() => control.abort(), ms)
  try {
    const r = await peticion(`${url.replace(/\/+$/, '')}/auth/v1/health`, { headers: { apikey: clave }, signal: control.signal })
    return { ok: r.ok === true }
  } catch {
    return { ok: false }
  } finally {
    clearTimeout(plazo)
  }
}

interface Pedido { method?: string }
interface Respuesta {
  setHeader(nombre: string, valor: string): void
  status(codigo: number): Respuesta
  end(cuerpo?: string): void
}

export default async function handler(req: Pedido, res: Respuesta) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.setHeader('Allow', 'GET, HEAD')
    res.status(405).end()
    return
  }
  const env = (globalThis as { process?: { env: Record<string, string | undefined> } }).process?.env ?? {}
  const { ok } = await comprobarSalud(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_ANON_KEY, (u, i) => fetch(u, i))
  res.setHeader('Content-Type', 'application/json; charset=utf-8')
  res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=30')
  res.setHeader('X-Robots-Tag', 'noindex, nofollow')
  res.status(ok ? 200 : 503).end(req.method === 'HEAD' ? undefined : JSON.stringify({ ok }))
}
