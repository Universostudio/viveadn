// Exportación de una iglesia por páginas: arma el ZIP sin tener nunca el paquete entero en memoria. Pide a la función `plataforma` el plan
// (las tablas y sus cifras) y después cada tabla en páginas, dos veces: una en JSON para `datos.json` y otra en CSV para `csv/<tabla>.csv`,
// porque un ZIP en flujo escribe un archivo detrás de otro. Cada página la calcula la base de datos, que también da el md5 de cada fila:
// la huella de la tabla (md5 de los md5 ordenados) es la misma que comprueba `adn_verificar_carga`, sin que nadie lea la tabla entera.
// El manifiesto se escribe al final porque lleva cifras que solo se conocen al terminar. Son funciones puras: la red y la descarga las pone quien llama.
import { Md5 } from './md5.ts'
import { EscritorZip, type Destino } from './zipFlujo.ts'

export interface ColumnaPlan { nombre: string; tipo: string; obligatoria: boolean }
export interface TablaPlan {
  nombre: string; orden_carga: number; archivo_csv: string; filas: number
  columnas: ColumnaPlan[]; omitidas: string[]; clave: string[]
}
export interface Plan { formato: string; iglesia_id: string; exportado_en: string; total_filas: number; tablas: TablaPlan[]; archivos?: unknown }
export interface PaginaJson { n: number; json: string; hashes: string[]; siguiente?: string[] }
export interface PaginaCsv { n: number; csv: string; siguiente?: string[] }

export interface Fuente {
  plan(): Promise<Plan>
  pagina(tabla: string, formato: 'json', despues: string[] | null, limite: number): Promise<PaginaJson>
  pagina(tabla: string, formato: 'csv', despues: string[] | null, limite: number): Promise<PaginaCsv>
}

export interface Progreso { fase: 'json' | 'csv'; tabla: string; indice: number; tablas: number; filasTabla: number; filasTotales: number; bytes: number }

export interface Opciones {
  slug: string
  hoy: Date
  leeme: string
  destino: Destino
  /** Filas por página (la base lo recorta a 5000). 1000 por defecto */
  limite?: number
  /** Intentos por página antes de rendirse. 3 por defecto */
  intentos?: number
  esperar?: (ms: number) => Promise<void>
  progreso?: (p: Progreso) => void
}

export interface Resultado {
  nombre: string; tablas: number; filas: number; bytes: number
  /** Verdadero si lo leído no coincide con el plan: la iglesia cambió mientras se exportaba */
  cambios: boolean
  paginas: number
}

const SIN_ESPERA = (ms: number) => new Promise<void>(r => setTimeout(r, ms))
const HEX32 = /^[0-9a-f]{32}$/

// El mismo criterio que adn_csv_campo de la base: se entrecomilla lo vacío, lo que lleva comillas, comas o saltos y lo que tiene espacios en los extremos
const campoCsv = (t: string): string => (t === '' || /["\r\n,]/.test(t) || /^\s|\s$/.test(t) ? `"${t.replace(/"/g, '""')}"` : t)

export async function exportarPaginado(fuente: Fuente, o: Opciones): Promise<Resultado> {
  const limite = Math.min(Math.max(Math.trunc(o.limite ?? 1000), 1), 5000)
  const intentos = Math.max(Math.trunc(o.intentos ?? 3), 1)
  const esperar = o.esperar ?? SIN_ESPERA
  const codificador = new TextEncoder()

  // Una página con reintentos: un fallo de red a mitad de una exportación grande no obliga a empezar de cero
  async function pedir<T>(f: () => Promise<T>): Promise<T> {
    let ultimo: unknown
    for (let i = 1; i <= intentos; i++) {
      try { return await f() } catch (e) { ultimo = e; if (i < intentos) await esperar(250 * 2 ** (i - 1)) }
    }
    throw ultimo instanceof Error ? ultimo : new Error('No se pudo leer una página de la exportación')
  }

  const plan = await pedir(() => fuente.plan())
  if (!plan || !Array.isArray(plan.tablas) || plan.tablas.length === 0) throw new Error('El plan de la exportación no es válido')
  const base = `viveadn-${o.slug}-${o.hoy.toISOString().slice(0, 10)}`
  const zip = new EscritorZip(o.destino, o.hoy)
  let paginas = 0
  let filasTotales = 0
  let cambios = false

  // Recorre una tabla página a página con el cursor de su clave. Cada página llega entera, nunca más de `limite` filas
  async function recorrer<T extends { n: number; siguiente?: string[] }>(
    t: TablaPlan, formato: 'json' | 'csv', alPagina: (p: T) => Promise<void>): Promise<number> {
    let despues: string[] | null = null
    let leidas = 0
    for (let vuelta = 0; ; vuelta++) {
      if (vuelta > Math.ceil(Math.max(t.filas, 1) / limite) + 1000) throw new Error(`La paginación de ${t.nombre} no termina`)
      const d: string[] | null = despues
      const p: T = await pedir<T>(() => fuente.pagina(t.nombre, formato as 'json', d, limite) as unknown as Promise<T>)
      if (typeof p?.n !== 'number' || p.n < 0 || p.n > limite) throw new Error(`Página no válida en ${t.nombre}`)
      paginas++
      await alPagina(p)
      leidas += p.n
      if (!p.siguiente) break
      if (p.n === 0) throw new Error(`La paginación de ${t.nombre} no avanza`)
      despues = p.siguiente ?? null
    }
    return leidas
  }

  await zip.empezar('LEEME.txt')
  await zip.escribir(o.leeme)

  // 1. datos.json: las filas de todas las tablas. La iglesia va en su propio campo, como en el formato de siempre
  const huellas = new Map<string, string>()
  const leidasJson = new Map<string, number>()
  let iglesiaFila = 'null'
  await zip.empezar('datos.json')
  await zip.escribir(`{"formato":${JSON.stringify(plan.formato)},"exportado_en":${JSON.stringify(plan.exportado_en)},"tablas":{`)
  let primeraTabla = true
  let indice = 0
  for (const t of plan.tablas) {
    indice++
    const hashes: string[] = []
    let hayFilas = false
    const esIglesia = t.nombre === 'iglesias'
    if (!esIglesia) { await zip.escribir(`${primeraTabla ? '' : ','}${JSON.stringify(t.nombre)}:[`); primeraTabla = false }
    let iglesiaTexto = ''
    const leidas = await recorrer<PaginaJson>(t, 'json', async p => {
      if (typeof p.json !== 'string' || !Array.isArray(p.hashes) || p.hashes.length !== p.n) throw new Error(`Página sin su JSON o sus huellas en ${t.nombre}`)
      for (const h of p.hashes) { if (!HEX32.test(h)) throw new Error(`Huella no válida en ${t.nombre}`); hashes.push(h) }
      // El texto llega como '[...]': se quitan los corchetes y se encadena con el de las demás páginas
      const interior = p.json.slice(1, -1)
      if (p.json[0] !== '[' || p.json[p.json.length - 1] !== ']') throw new Error(`JSON de página no válido en ${t.nombre}`)
      if (p.n === 0) return
      if (esIglesia) iglesiaTexto += (iglesiaTexto ? ',' : '') + interior
      else { await zip.escribir((hayFilas ? ',' : '') + interior); hayFilas = true }
    })
    if (esIglesia) iglesiaFila = iglesiaTexto || 'null'
    else await zip.escribir(']')
    huellas.set(t.nombre, new Md5().update(codificador.encode(hashes.sort().join(','))).hex())
    leidasJson.set(t.nombre, leidas)
    filasTotales += leidas
    if (leidas !== t.filas) cambios = true
    o.progreso?.({ fase: 'json', tabla: t.nombre, indice, tablas: plan.tablas.length, filasTabla: leidas, filasTotales, bytes: zip.bytes })
  }
  await zip.escribir(`},"iglesia":${iglesiaFila},"archivos":${JSON.stringify(plan.archivos ?? null)}}`)

  // 2. Un CSV por tabla, con su cabecera y su huella md5 calculada mientras se escribe
  const md5Csv = new Map<string, string>()
  indice = 0
  for (const t of plan.tablas) {
    indice++
    await zip.empezar(t.archivo_csv)
    const md5 = new Md5()
    const escribir = async (texto: string) => { if (texto) { md5.update(codificador.encode(texto)); await zip.escribir(texto) } }
    await escribir(t.columnas.map(c => campoCsv(c.nombre)).join(',') + '\r\n')
    const leidas = await recorrer<PaginaCsv>(t, 'csv', async p => {
      if (typeof p.csv !== 'string') throw new Error(`Página sin su CSV en ${t.nombre}`)
      await escribir(p.csv)
    })
    md5Csv.set(t.nombre, md5.hex())
    if (leidas !== leidasJson.get(t.nombre)) cambios = true
    o.progreso?.({ fase: 'csv', tabla: t.nombre, indice, tablas: plan.tablas.length, filasTabla: leidas, filasTotales, bytes: zip.bytes })
  }

  // 3. El manifiesto, al final: con las cifras de lo que de verdad se escribió
  const manifiesto = {
    formato: plan.formato, iglesia_id: plan.iglesia_id, exportado_en: plan.exportado_en,
    codificacion: 'UTF-8 sin BOM', separador: ',', fin_de_linea: 'CRLF',
    nulos: 'campo vacio sin comillas; la cadena vacia va entre comillas ("")',
    total_filas: filasTotales,
    paginado: true, filas_por_pagina: limite, cambios_durante_la_exportacion: cambios,
    archivos_de_almacenamiento: plan.archivos ?? null,
    tablas: plan.tablas.map(t => ({
      nombre: t.nombre, orden_carga: t.orden_carga, archivo_csv: t.archivo_csv, filas: leidasJson.get(t.nombre) ?? 0,
      columnas: t.columnas, omitidas: t.omitidas, huella: huellas.get(t.nombre), md5_csv: md5Csv.get(t.nombre),
    })),
  }
  await zip.empezar('manifest.json')
  await zip.escribir(JSON.stringify(manifiesto, null, 2))
  const { bytes } = await zip.cerrar()
  return { nombre: `${base}.zip`, tablas: plan.tablas.length, filas: filasTotales, bytes, cambios, paginas }
}

/** La fuente de la función de borde `plataforma`: `llamar` envía el cuerpo y devuelve la respuesta ya interpretada (o lanza con el motivo) */
export function fuenteDePlataforma(llamar: (cuerpo: Record<string, unknown>) => Promise<any>, iglesiaId: string): Fuente {
  return {
    async plan() { return (await llamar({ accion: 'exportar_plan', iglesia_id: iglesiaId })).plan as Plan },
    async pagina(tabla: string, formato: 'json' | 'csv', despues: string[] | null, limite: number) {
      return (await llamar({ accion: 'exportar_pagina', iglesia_id: iglesiaId, tabla, formato, despues, limite })).pagina
    },
  } as Fuente
}
