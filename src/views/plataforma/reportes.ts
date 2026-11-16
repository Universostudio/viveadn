// Reportes de la plataforma: crecimiento, altas y bajas, distribución, personas y módulos. Puro (sin Vue ni red) para probarlo en Node.
// Parte de la misma lista `visibles` que el resto del Panel Maestro, así que respeta el interruptor «Incluir demostraciones». Solo cuenta: nunca datos de personas.
import { etapaDe, type Catalogo, type IglesiaFila } from './adaptador.ts'

export const ETAPAS = ['onboarding', 'prueba', 'activa', 'receso', 'suspendida'] as const
const ETAPAS_CON_SERVICIO = new Set<string>(['onboarding', 'prueba', 'activa'])
const mesDe = (d: Date) => `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
const finDeMes = (a: number, m: number) => Date.UTC(a, m + 1, 1) - 1
const viva = (i: IglesiaFila) => !i.adn_borrada_en

export interface MesCrecimiento { mes: string; altas: number; bajas: number; acumuladas: number }

/** Altas (creación) y bajas (borrado) por mes en los últimos `meses` meses, con las iglesias vivas a final de cada mes. */
export function crecimiento(lista: IglesiaFila[], ahora = Date.now(), meses = 12): MesCrecimiento[] {
  const hoy = new Date(ahora)
  const filas: MesCrecimiento[] = []
  for (let k = meses - 1; k >= 0; k--) {
    const d = new Date(Date.UTC(hoy.getUTCFullYear(), hoy.getUTCMonth() - k, 1))
    const clave = mesDe(d), fin = finDeMes(d.getUTCFullYear(), d.getUTCMonth())
    const altas = lista.filter(i => mesDe(new Date(i.created_at)) === clave).length
    const bajas = lista.filter(i => i.adn_borrada_en && mesDe(new Date(i.adn_borrada_en)) === clave).length
    const acumuladas = lista.filter(i => new Date(i.created_at).getTime() <= fin).length - lista.filter(i => i.adn_borrada_en && new Date(i.adn_borrada_en).getTime() <= fin).length
    filas.push({ mes: clave, altas, bajas, acumuladas })
  }
  return filas
}

export interface Distribucion { etapas: readonly string[]; filas: { plan: string; porEtapa: Record<string, number>; total: number }[]; totalPorEtapa: Record<string, number>; total: number }

/** Iglesias vivas por plan y etapa. Las dadas de baja no entran: salen en las bajas del crecimiento. */
export function distribucion(lista: IglesiaFila[], planes: { clave: string }[]): Distribucion {
  const vivas = lista.filter(viva)
  const claves = [...planes.map(p => p.clave), ...vivas.map(i => i.plan).filter(p => !planes.some(x => x.clave === p))]
  const filas = [...new Set(claves)].map(plan => {
    const porEtapa = Object.fromEntries(ETAPAS.map(e => [e, vivas.filter(i => i.plan === plan && etapaDe(i) === e).length]))
    return { plan, porEtapa, total: Object.values(porEtapa).reduce((s, n) => s + n, 0) }
  })
  const totalPorEtapa = Object.fromEntries(ETAPAS.map(e => [e, filas.reduce((s, f) => s + (f.porEtapa[e] ?? 0), 0)]))
  return { etapas: ETAPAS, filas, totalPorEtapa, total: filas.reduce((s, f) => s + f.total, 0) }
}

export interface Personas { miembros: number; usuarios: number; iglesias: number; promedio: number | null; porPlan: { plan: string; miembros: number; iglesias: number }[] }

/** Personas registradas (conteos, no datos) en las iglesias vivas. Promedio nulo si no hay ninguna iglesia. */
export function personas(lista: IglesiaFila[]): Personas {
  const vivas = lista.filter(viva)
  const miembros = vivas.reduce((s, i) => s + (i.miembros ?? 0), 0)
  const planes = [...new Set(vivas.map(i => i.plan))].sort()
  return {
    miembros, usuarios: vivas.reduce((s, i) => s + (i.usuarios ?? 0), 0), iglesias: vivas.length,
    promedio: vivas.length ? Math.round((miembros / vivas.length) * 10) / 10 : null,
    porPlan: planes.map(plan => ({ plan, miembros: vivas.filter(i => i.plan === plan).reduce((s, i) => s + (i.miembros ?? 0), 0), iglesias: vivas.filter(i => i.plan === plan).length })),
  }
}

export interface UsoModulo { clave: string; nombre: string; tipo: string; conAcceso: number; deTotal: number; porComplemento: number }

/** Cuántas iglesias con servicio (alta, prueba o activa) tienen acceso a cada módulo, por su plan o por un complemento activo. Acceso, no uso real. */
export function modulos(lista: IglesiaFila[], c: Catalogo): UsoModulo[] {
  const conServicio = lista.filter(i => viva(i) && ETAPAS_CON_SERVICIO.has(etapaDe(i)))
  return c.modulos.map(m => {
    const delPlan = (i: IglesiaFila) => c.planModulos.some(x => x.plan === i.plan && x.modulo === m.clave)
    const extra = (i: IglesiaFila) => !delPlan(i) && (i.addons ?? []).some(a => a.modulo === m.clave && a.activo)
    return { clave: m.clave, nombre: m.nombre, tipo: m.tipo, conAcceso: conServicio.filter(i => delPlan(i) || extra(i)).length, deTotal: conServicio.length, porComplemento: conServicio.filter(extra).length }
  })
}
