// Seguimiento de nuevos convertidos: contactos registrados y enlaces para llamar o escribir por WhatsApp.
// Funciones puras, probadas en Node (scripts/probar-seguimiento.mts). No envían nada: solo construyen enlaces que abre quien está en pantalla.

export interface FilaConsolidacion {
  primer_contacto_fecha?: string | null; primer_contacto_notas?: string | null
  segundo_contacto_fecha?: string | null; segundo_contacto_notas?: string | null
  tercer_contacto_fecha?: string | null; tercer_contacto_notas?: string | null
}

export type NumeroContacto = 1 | 2 | 3
export interface Contacto { n: NumeroContacto; fecha: string; notas: string | null }

const PREFIJO: Record<NumeroContacto, 'primer' | 'segundo' | 'tercer'> = { 1: 'primer', 2: 'segundo', 3: 'tercer' }

/** Los contactos ya registrados, en orden */
export function contactosDe(c: FilaConsolidacion): Contacto[] {
  return ([1, 2, 3] as NumeroContacto[]).flatMap(n => {
    const fecha = c[`${PREFIJO[n]}_contacto_fecha` as keyof FilaConsolidacion]
    const notas = c[`${PREFIJO[n]}_contacto_notas` as keyof FilaConsolidacion]
    return fecha ? [{ n, fecha, notas: notas ?? null }] : []
  })
}

/** El primer hueco libre (1 a 3) o null si ya están los tres */
export function siguienteHueco(c: FilaConsolidacion): NumeroContacto | null {
  for (const n of [1, 2, 3] as NumeroContacto[]) if (!c[`${PREFIJO[n]}_contacto_fecha` as keyof FilaConsolidacion]) return n
  return null
}

/** Las columnas a escribir para el contacto n. La nota vacía se guarda como nula */
export function camposContacto(n: NumeroContacto, fechaIso: string, nota: string): Record<string, string | null> {
  const t = nota.trim()
  return { [`${PREFIJO[n]}_contacto_fecha`]: fechaIso, [`${PREFIJO[n]}_contacto_notas`]: t === '' ? null : t.slice(0, 1000) }
}

/** Un contacto no puede ser del futuro (con 5 minutos de margen por el reloj del dispositivo) */
export function fechaDeContactoValida(fechaIso: string, ahora = Date.now()): boolean {
  const t = Date.parse(fechaIso)
  return Number.isFinite(t) && t <= ahora + 5 * 60_000
}

const soloDigitos = (s: string) => s.replace(/\D/g, '')

// Prefijos telefónicos de los países más habituales; un número sin prefijo internacional solo se completa si se conoce el país [NV: lista a ampliar con los países reales de las iglesias]
const PREFIJOS_PAIS: Record<string, string> = {
  es: '34', espana: '34', espanha: '34', spain: '34',
  mx: '52', mexico: '52', co: '57', colombia: '57', ar: '54', argentina: '54', cl: '56', chile: '56',
  pe: '51', peru: '51', ve: '58', venezuela: '58', ec: '593', ecuador: '593', gt: '502', guatemala: '502',
  us: '1', 'estados unidos': '1', eeuu: '1', br: '55', brasil: '55', brazil: '55', pt: '351', portugal: '351',
  fr: '33', francia: '33', france: '33',
}
const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').trim().toLowerCase()
export function prefijoDePais(pais: string | null | undefined): string | null {
  return pais ? PREFIJOS_PAIS[normalizar(pais)] ?? null : null
}

/** Enlace tel: o null si el número no sirve (menos de 6 cifras) */
export function enlaceLlamar(telefono: string | null | undefined): string | null {
  if (!telefono) return null
  const d = soloDigitos(telefono)
  if (d.length < 6 || d.length > 15) return null
  return `tel:${telefono.trim().startsWith('+') ? '+' : ''}${d}`
}

/** Enlace de WhatsApp (wa.me exige el número en formato internacional, sin + ni ceros). Si el número no trae prefijo y no se conoce el país, null */
export function enlaceWhatsApp(telefono: string | null | undefined, pais?: string | null): string | null {
  if (!telefono) return null
  const t = telefono.trim()
  let d = soloDigitos(t)
  if (d.length < 6) return null
  if (t.startsWith('+')) {
    // ya internacional
  } else if (d.startsWith('00')) {
    d = d.slice(2)
  } else {
    const prefijo = prefijoDePais(pais)
    if (!prefijo) return null
    d = prefijo + d.replace(/^0+/, '')
  }
  if (d.length < 8 || d.length > 15) return null
  return `https://wa.me/${d}`
}
