// Verificación de un entorno de pruebas ya desplegado: la web, la ruta de salud, la protección de las funciones de borde
// (CORS, JWT, vía de la tarea programada) y el estado de la purga. Solo lee y hace peticiones inocuas: no crea ni borra datos
// y no envía correos. Nunca devuelve ni imprime claves: los resultados llevan solo el nombre de la comprobación y un detalle sin secretos.
// Es la parte reutilizable; la línea de órdenes está en scripts/verificar-entorno.mts y la prueba en scripts/probar-verificar-entorno.mts.

export interface Opciones {
  /** Dirección de la web del entorno, https y sin ruta */
  web: string
  /** Dirección del proyecto de Supabase (la de VITE_SUPABASE_URL), https y sin ruta */
  supabase: string
  /** Clave pública (anon) para llamar a las funciones que verifican el JWT. Opcional, pero obligatoria si se facilita `cron` */
  anon?: string
  /** Secreto de la tarea programada (ADN_CRON_SECRET). Opcional: sin él no se comprueba el estado de la purga */
  cron?: string
}
export interface Resultado { nombre: string; ok: boolean; detalle: string }

const HTTPS_SIN_RUTA = /^https:\/\/[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:\d{1,5})?\/?$/
export const FUNCIONES_CON_CORS = ['plataforma', 'invitaciones', 'registro-iglesia', 'red-resumen', 'dar-publico', 'checkin-evento', 'verificar-certificado', 'baja', 'confirmar-suscripcion', 'datos-iglesia'] as const
export const FUNCIONES_SIN_JWT = ['baja', 'confirmar-suscripcion'] as const
export const RUTAS_LEGALES = ['/privacidad', '/terminos', '/aviso-legal', '/cookies'] as const

const sinBarra = (u: string) => u.replace(/\/+$/, '')

export async function verificar(o: Opciones, f: typeof fetch = fetch): Promise<Resultado[]> {
  const r: Resultado[] = []
  const anota = (nombre: string, ok: boolean, detalle: string) => r.push({ nombre, ok, detalle })
  // Una petición que falla por red cuenta como comprobación fallida, no como excepción que corta las demás
  const pide = async (url: string, init: RequestInit = {}) => {
    try { return await f(url, { ...init, signal: AbortSignal.timeout(15000) }) } catch { return null }
  }

  if (!HTTPS_SIN_RUTA.test(o.web)) { anota('web: dirección', false, 'debe ser https y sin ruta'); return r }
  if (!HTTPS_SIN_RUTA.test(o.supabase)) { anota('supabase: dirección', false, 'debe ser https y sin ruta'); return r }
  const web = sinBarra(o.web); const sb = sinBarra(o.supabase)
  const fn = (n: string) => `${sb}/functions/v1/${n}`

  // 1. La web
  const raiz = await pide(`${web}/`)
  anota('web: abre', raiz?.status === 200, `estado ${raiz?.status ?? 'sin respuesta'}`)
  anota('web: no se indexa', /noindex/i.test(raiz?.headers.get('x-robots-tag') ?? ''), 'el entorno de pruebas debe llevar noindex')
  const salud = await pide(`${web}/api/salud`)
  let cuerpoSalud = ''; try { cuerpoSalud = salud ? (await salud.text()).trim() : '' } catch { /* se queda vacío */ }
  anota('web: ruta de salud', salud?.status === 200 && cuerpoSalud === '{"ok":true}', `estado ${salud?.status ?? 'sin respuesta'}${salud?.status === 503 ? ' (revisa VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY en el alojamiento)' : ''}`)
  for (const ruta of RUTAS_LEGALES) {
    const p = await pide(`${web}${ruta}`)
    anota(`web: ${ruta}`, p?.status === 200, `estado ${p?.status ?? 'sin respuesta'}`)
  }

  // 2. CORS: cada función debe aceptar el origen de esta web (si no, el secreto ADN_ORIGENES_EXTRA no está bien puesto)
  const origen = new URL(web).origin
  for (const n of FUNCIONES_CON_CORS) {
    const p = await pide(fn(n), { method: 'OPTIONS', headers: { Origin: origen, 'Access-Control-Request-Method': 'POST' } })
    const permitido = p?.headers.get('access-control-allow-origin')
    anota(`cors: ${n}`, p?.status === 200 && permitido === origen,
      p ? `estado ${p.status}, ${permitido === origen ? 'acepta el origen' : 'no acepta el origen: define ADN_ORIGENES_EXTRA con la dirección de la web'}` : 'sin respuesta (¿función desplegada?)')
  }

  // 3. Funciones que se abren con un enlace: sin JWT. Un 401 significa que se desplegaron verificándolo
  for (const n of FUNCIONES_SIN_JWT) {
    const p = await pide(fn(n), { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
    const desplegada = !!p && p.status !== 404
    anota(`sin JWT: ${n}`, !!p && desplegada && p.status !== 401 && p.status < 500, p ? `estado ${p.status}${p.status === 401 ? ' (desplegada verificando el JWT: redespliégala sin verificarlo)' : p.status === 404 ? ' (no está desplegada)' : ''}` : 'sin respuesta')
  }

  // 4. Funciones con JWT: sin la clave pública deben rechazar; con ella, contestar
  if (o.anon) {
    const sin = await pide(fn('dar-publico'), { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
    anota('con JWT: dar-publico rechaza sin clave', sin?.status === 401, `estado ${sin?.status ?? 'sin respuesta'}`)
    const con = await pide(fn('dar-publico'), { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: o.anon, Authorization: `Bearer ${o.anon}` }, body: '{}' })
    anota('con JWT: dar-publico contesta con la clave', !!con && con.status !== 401 && con.status !== 404 && con.status < 500, `estado ${con?.status ?? 'sin respuesta'}`)
  }

  // 5. Vía de la tarea programada: con una clave cualquiera debe estar cerrada
  // `plataforma` se despliega verificando el JWT, así que la tarea real envía la clave pública además de x-adn-cron: aquí igual.
  // Sin clave pública, un 401 de la pasarela también significa cerrada, pero no prueba que la función rechace la clave falsa.
  const falsa = 'x'.repeat(40)
  const publica: Record<string, string> = o.anon ? { apikey: o.anon, Authorization: `Bearer ${o.anon}` } : {}
  for (const n of ['plataforma', 'enviar-confirmaciones'] as const) {
    const p = await pide(fn(n), { method: 'POST', headers: { 'Content-Type': 'application/json', ...publica, 'x-adn-cron': falsa }, body: '{"accion":"estado_purga"}' })
    const cerrada = p?.status === 403 || (!o.anon && p?.status === 401)
    anota(`tarea: ${n} cerrada a una clave falsa`, cerrada, `estado ${p?.status ?? 'sin respuesta'}${p?.status === 404 ? ' (no está desplegada)' : ''}${!o.anon && p?.status === 401 ? ' (la pasarela la rechazó antes: facilita VITE_SUPABASE_ANON_KEY para comprobar la función)' : ''}`)
  }

  // 6. Estado de la purga y libro, con el secreto real si se facilita
  if (o.cron && !o.anon) {
    anota('purga: omitida', false, 'con ADN_CRON_SECRET hace falta también VITE_SUPABASE_ANON_KEY: la tarea real envía las dos')
  } else if (o.cron) {
    const llama = async (accion: string) => {
      const p = await pide(fn('plataforma'), { method: 'POST', headers: { 'Content-Type': 'application/json', ...publica, 'x-adn-cron': o.cron! }, body: JSON.stringify({ accion }) })
      let j: any = null; try { j = p ? await p.json() : null } catch { /* sin cuerpo válido */ }
      return { p, j }
    }
    const { p, j } = await llama('estado_purga')
    const cifras = j && typeof j.atrasada === 'boolean' && Number.isFinite(j.en_borrado) && Number.isFinite(j.vencidas)
    anota('purga: la tarea puede consultar el estado', p?.status === 200 && !!cifras, `estado ${p?.status ?? 'sin respuesta'}${p?.status === 403 ? ' (el secreto no coincide con ADN_CRON_SECRET de la función)' : ''}`)
    if (cifras) anota('purga: al día', j.atrasada === false, `en borrado suave ${j.en_borrado}, vencidas ${j.vencidas}, la más atrasada ${j.horas_mas_atrasada} h`)
    const l = await llama('libro_purgas')
    anota('purga: el libro se puede exportar', l.p?.status === 200 && Array.isArray(l.j?.registro), `estado ${l.p?.status ?? 'sin respuesta'}, ${Array.isArray(l.j?.registro) ? l.j.registro.length + ' purgas registradas' : 'sin libro'}`)
  }
  return r
}
