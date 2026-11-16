// Cotizador de planes y modulos. Una estimacion, no un cobro: aqui no se cobra nada. Los importes vienen del catalogo
// (precios_plan y precios_modulo), que por ahora es una propuesta (docs/PLANES.md). Todo en centimos de la moneda base.

export interface PlanCat { clave: string; nombre: string; max_miembros: number | null; max_usuarios: number | null; orden: number }
export interface ModuloCat { clave: string; nombre: string; descripcion: string | null; tipo: string; orden: number }
export interface Catalogo {
  planes: PlanCat[]
  modulos: ModuloCat[]
  planModulos: Record<string, string[]>   // plan -> modulos que incluye
  precioPlan: Record<string, number>
  precioModulo: Record<string, number>
}
export interface Requisitos { personas?: number | null; usuarios?: number | null }
export interface Extra { modulo: string; importe: number }
export interface Cotizacion {
  plan: string
  base: number
  extras: Extra[]
  total: number
  sinPrecio: string[]    // modulos fuera del plan sin precio en el catalogo: no se puede cotizar el total
  cabe: boolean          // el plan cubre las personas y usuarios pedidos
}

// Los modulos de nucleo vienen siempre; el resto se puede contratar o ya viene en el plan
export const modulosContratables = (cat: Catalogo): ModuloCat[] =>
  cat.modulos.filter(m => m.tipo !== 'nucleo').sort((a, b) => a.orden - b.orden)

export function cotizar(cat: Catalogo, plan: string, elegidos: Iterable<string>, req: Requisitos = {}): Cotizacion {
  const p = cat.planes.find(x => x.clave === plan)
  const incluidos = new Set(cat.planModulos[plan] ?? [])
  const extras: Extra[] = []
  const sinPrecio: string[] = []
  for (const clave of new Set(elegidos)) {
    const m = cat.modulos.find(x => x.clave === clave)
    if (!m || m.tipo === 'nucleo' || incluidos.has(clave)) continue
    const importe = cat.precioModulo[clave]
    if (importe === undefined) sinPrecio.push(clave)
    else extras.push({ modulo: clave, importe })
  }
  const base = cat.precioPlan[plan] ?? 0
  const total = base + extras.reduce((s, e) => s + e.importe, 0)
  const cabe = !!p
    && (req.personas == null || p.max_miembros === null || req.personas <= p.max_miembros)
    && (req.usuarios == null || p.max_usuarios === null || req.usuarios <= p.max_usuarios)
  return { plan, base, extras, total, sinPrecio, cabe }
}

// Todos los planes para lo que se pide, del mas barato al mas caro; los que no cubren el tamano o no se pueden cotizar van al final
export function compararPlanes(cat: Catalogo, elegidos: Iterable<string>, req: Requisitos = {}): Cotizacion[] {
  const lista = [...elegidos]
  return cat.planes
    .filter(p => cat.precioPlan[p.clave] !== undefined)
    .map(p => cotizar(cat, p.clave, lista, req))
    .sort((a, b) => Number(b.cabe && !b.sinPrecio.length) - Number(a.cabe && !a.sinPrecio.length) || a.total - b.total)
}

export function recomendado(cat: Catalogo, elegidos: Iterable<string>, req: Requisitos = {}): Cotizacion | null {
  const mejor = compararPlanes(cat, elegidos, req)[0]
  return mejor && mejor.cabe && mejor.sinPrecio.length === 0 ? mejor : null
}

// Con moneda decidida se da formato de dinero; sin ella, solo el numero (unidades), porque la moneda base esta por decidir
export function formatoImporte(centimos: number, moneda: string | null, idioma: string): string {
  const valor = centimos / 100
  if (!moneda) return new Intl.NumberFormat(idioma, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(valor)
  return new Intl.NumberFormat(idioma, { style: 'currency', currency: moneda }).format(valor)
}
