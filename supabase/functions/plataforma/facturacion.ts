// Facturación en modo de prueba: validación del precio de un plan y simulación del ingreso mensual esperado. Funciones puras, sin red ni base, para probarlas con
// `npm run test:facturacion`. NO cobra, NO crea cargos y NO habla con ninguna pasarela: solo multiplica iglesias por el precio que alguien haya fijado.

export interface PlanPrecio { clave: string; nombre?: string | null; precio_mensual_centimos?: number | null; precio_anual_centimos?: number | null; moneda?: string | null }
export interface IglesiaCobro { plan: string; activa?: boolean; etapa?: string | null; es_demo?: boolean | null; adn_borrada_en?: string | null; /** Cuántas iglesias iguales representa la fila (los agregados de SQL); 1 si falta */ n?: number }

export type Validado<T> = ({ ok: true } & T) | { ok: false; error: string }
const MAX_MENSUAL = 10_000_000, MAX_ANUAL = 100_000_000

const centimos = (v: unknown, max: number): number | null | 'mal' => {
  if (v === undefined || v === null || v === '') return null
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0 || v > max) return 'mal'
  return v
}

/** Un precio es opcional; si hay alguno, hace falta la moneda. Vaciar los dos borra el precio. */
export function validarPrecio(body: Record<string, unknown>): Validado<{ clave: string; mensual: number | null; anual: number | null; moneda: string | null }> {
  const clave = String(body.plan ?? '')
  if (!/^[a-z0-9_-]{1,40}$/.test(clave)) return { ok: false, error: 'Plan no valido' }
  const mensual = centimos(body.precio_mensual_centimos, MAX_MENSUAL), anual = centimos(body.precio_anual_centimos, MAX_ANUAL)
  if (mensual === 'mal') return { ok: false, error: 'El precio mensual no es valido' }
  if (anual === 'mal') return { ok: false, error: 'El precio anual no es valido' }
  const moneda = body.moneda === undefined || body.moneda === null || body.moneda === '' ? null : String(body.moneda).trim().toUpperCase()
  if (moneda !== null && !/^[A-Z]{3}$/.test(moneda)) return { ok: false, error: 'La moneda debe tener tres letras' }
  if ((mensual !== null || anual !== null) && moneda === null) return { ok: false, error: 'Falta la moneda' }
  return { ok: true, clave, mensual, anual, moneda: mensual === null && anual === null ? null : moneda }
}

const etapaDe = (i: IglesiaCobro) => i.etapa ?? (i.activa ? 'activa' : 'suspendida')

/** Por qué una iglesia no entra en el ingreso esperado; null si entra (en alta de pago: activa, sin ser demostración ni estar borrada) */
export function motivoFuera(i: IglesiaCobro): 'borrada' | 'demo' | 'onboarding' | 'prueba' | 'receso' | 'suspendida' | null {
  if (i.adn_borrada_en) return 'borrada'
  if (i.es_demo) return 'demo'
  const e = etapaDe(i)
  if (e === 'activa') return null
  return e === 'onboarding' || e === 'prueba' || e === 'receso' ? e : 'suspendida'
}

export interface FilaPlan {
  clave: string; nombre: string; iglesias: number
  precio_mensual_centimos: number | null; precio_anual_centimos: number | null; moneda: string | null
  /** null cuando no se puede calcular (hay iglesias y no hay precio); 0 solo si de verdad no hay ninguna iglesia en este plan */
  ingreso_mensual_centimos: number | null
  causa: 'sin_precio' | 'sin_iglesias' | null
}

/** El ingreso mensual esperado de las iglesias que pagan. Un cero solo sale con su causa; nunca se inventa un precio. */
export function simular(iglesias: IglesiaCobro[] | null | undefined, planes: PlanPrecio[] | null | undefined) {
  const fuera: Record<string, number> = { demo: 0, onboarding: 0, prueba: 0, receso: 0, suspendida: 0, borrada: 0 }
  const pagan = new Map<string, number>()
  for (const i of iglesias ?? []) {
    const m = motivoFuera(i), peso = Number(i.n ?? 1) || 0
    if (m) fuera[m] += peso
    else pagan.set(i.plan, (pagan.get(i.plan) ?? 0) + peso)
  }
  const conocidos = new Set((planes ?? []).map(p => p.clave))
  const filas: FilaPlan[] = (planes ?? []).map(p => {
    const n = pagan.get(p.clave) ?? 0
    const mensual = p.precio_mensual_centimos ?? null
    const tienePrecio = mensual !== null && !!p.moneda
    return {
      clave: p.clave, nombre: p.nombre ?? p.clave, iglesias: n,
      precio_mensual_centimos: mensual, precio_anual_centimos: p.precio_anual_centimos ?? null, moneda: p.moneda ?? null,
      ingreso_mensual_centimos: n === 0 ? 0 : tienePrecio ? n * (mensual as number) : null,
      causa: n === 0 ? 'sin_iglesias' : tienePrecio ? null : 'sin_precio',
    }
  })
  // Iglesias con un plan que ya no está en el catálogo: se cuentan aparte, no se pierden
  const planDesconocido = [...pagan].filter(([c]) => !conocidos.has(c)).reduce((s, [, n]) => s + n, 0)
  const porMoneda: Record<string, number> = {}
  for (const f of filas) if (f.ingreso_mensual_centimos && f.moneda) porMoneda[f.moneda] = (porMoneda[f.moneda] ?? 0) + f.ingreso_mensual_centimos
  const pagando = filas.reduce((s, f) => s + f.iglesias, 0) + planDesconocido
  return {
    etiqueta: 'datos_de_prueba' as const,
    planes: filas,
    pagando,
    // Si alguna iglesia paga un plan sin precio, el total es parcial: se dice, no se redondea a «todo bien»
    incompleto: filas.some(f => f.causa === 'sin_precio') || planDesconocido > 0,
    ingreso_mensual_por_moneda: porMoneda,
    plan_desconocido: planDesconocido,
    fuera_del_calculo: fuera,
  }
}

/** Las filas del agregado SQL (adn_plataforma_facturacion) con la forma que espera `simular`: una fila por grupo, con su número de iglesias */
export const filasDeFacturacion = (filas: { plan: string; activa: boolean; etapa: string | null; es_demo: boolean; borrada: boolean; n: number | string }[] | null | undefined): IglesiaCobro[] =>
  (filas ?? []).map(f => ({ plan: f.plan, activa: f.activa, etapa: f.etapa, es_demo: f.es_demo, adn_borrada_en: f.borrada ? 'borrada' : null, n: Number(f.n) }))
