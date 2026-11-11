// Arma los archivos de la exportación de una iglesia a partir de la respuesta de la función `plataforma`.
// Son funciones puras: la descarga la hace la pantalla.
import { crearZip, type EntradaZip } from './zip.ts'

interface TablaManifiesto { nombre: string; archivo_csv: string; filas: number }

export interface RespuestaExportacion {
  formato?: string
  exportado_en?: string
  iglesia?: unknown
  tablas?: Record<string, unknown[]>
  csv?: Record<string, string>
  manifiesto?: { tablas: TablaManifiesto[]; [clave: string]: unknown }
  archivos?: unknown
}

export type Paquete =
  | { tipo: 'zip'; nombre: string; bytes: Uint8Array; mime: 'application/zip'; tablas: number; filas: number }
  | { tipo: 'json'; nombre: string; texto: string; mime: 'application/json' }

// Con el formato 2 (manifiesto y CSV) sale un ZIP; con la exportación anterior, solo el JSON de siempre.
export function construirPaquete(exp: RespuestaExportacion, slug: string, hoy: Date, leeme: string): Paquete {
  const base = `viveadn-${slug}-${hoy.toISOString().slice(0, 10)}`
  const m = exp.manifiesto
  if (!m || !exp.csv) return { tipo: 'json', nombre: `${base}.json`, texto: JSON.stringify(exp, null, 2), mime: 'application/json' }

  const entradas: EntradaZip[] = [
    { ruta: 'LEEME.txt', contenido: leeme },
    { ruta: 'manifest.json', contenido: JSON.stringify({ ...m, archivos_de_almacenamiento: exp.archivos ?? null }, null, 2) },
    { ruta: 'datos.json', contenido: JSON.stringify({ formato: exp.formato, exportado_en: exp.exportado_en, iglesia: exp.iglesia, tablas: exp.tablas, archivos: exp.archivos ?? null }, null, 2) },
  ]
  for (const t of m.tablas) {
    const csv = exp.csv[t.nombre]
    if (typeof csv !== 'string') throw new Error(`Falta el CSV de la tabla ${t.nombre}`)
    entradas.push({ ruta: t.archivo_csv, contenido: csv })
  }
  const filas = m.tablas.reduce((a, t) => a + t.filas, 0)
  return { tipo: 'zip', nombre: `${base}.zip`, bytes: crearZip(entradas, hoy), mime: 'application/zip', tablas: m.tablas.length, filas }
}
