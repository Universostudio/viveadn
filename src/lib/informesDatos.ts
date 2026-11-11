// Lectura de los datos de los informes desde la base. La seguridad por filas y el permiso de cada función deciden
// qué se devuelve: un informe nunca incluye lo que esa persona no podría ver en pantalla.
import { supabase } from '@/lib/supabase'
import { leerTodo } from '@/lib/paginar'
import type { DatosAsistencia, FilaCrecimiento, FilaMiembro, ResumenMiembros } from '@/lib/informes'

export class ErrorInforme extends Error {
  constructor(public clave: string) { super(clave) }
}

const claveDeError = (mensaje: string | undefined): string => {
  const m = mensaje ?? ''
  if (/ADN_SIN_PERMISO/.test(m)) return 'reportes.descargas.errorPermiso'
  if (/ADN_PERIODO_INVALIDO/.test(m)) return 'reportes.descargas.errorPeriodo'
  return 'reportes.descargas.errorGenerico'
}

export async function datosMiembros(): Promise<{ resumen: ResumenMiembros; filas: FilaMiembro[] }> {
  const r = await supabase.rpc('adn_informe_miembros_resumen')
  if (r.error) throw new ErrorInforme(claveDeError(r.error.message))
  const filas = await leerTodo<FilaMiembro>((d, h) => supabase.rpc('adn_informe_miembros').range(d, h))
  if (!filas) throw new ErrorInforme('reportes.descargas.errorGenerico')
  return { resumen: r.data as ResumenMiembros, filas }
}

export async function datosAsistencia(desde: string, hasta: string): Promise<DatosAsistencia> {
  const r = await supabase.rpc('adn_informe_asistencia', { p_desde: desde, p_hasta: hasta })
  if (r.error) throw new ErrorInforme(claveDeError(r.error.message))
  return r.data as DatosAsistencia
}

export async function datosCrecimiento(meses: number): Promise<FilaCrecimiento[]> {
  const r = await supabase.rpc('adn_informe_crecimiento', { p_meses: meses })
  if (r.error) throw new ErrorInforme(claveDeError(r.error.message))
  return (r.data ?? []) as FilaCrecimiento[]
}
