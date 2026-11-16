// Método de seguimiento de nuevas personas: reglas para crear y editar un método propio. Son las mismas que aplica la base de datos
// (restricciones de adn_seguimiento_metodos), para avisar antes de enviar y con un texto claro, no con un error de la base.
export const PLANTILLA_OP72_ID = '5e000000-0000-4000-8000-000000000072'
export const PLANTILLA_SIMPLE_ID = '5e000000-0000-4000-8000-000000000001'
export const MAX_METODOS_PROPIOS = 10
export const MAX_PLAZO_HORAS = 720
export const MAX_NOMBRE = 80

export interface MetodoFila {
  id: string
  iglesia_id: string | null
  clave: string
  nombre: string
  plantilla_origen: string | null
  pasos: number
  plazo_horas: number
  umbral_amarillo_horas: number
  umbral_naranja_horas: number
  primer_contacto_horas: number | null
  archivado_en: string | null
}

/** Lo que se edita en el formulario: los números llegan como texto de un campo, por eso admiten cadenas */
export interface BorradorMetodo {
  nombre: string
  pasos: number | string
  plazo_horas: number | string
  umbral_amarillo_horas: number | string
  umbral_naranja_horas: number | string
  primer_contacto_horas: number | string | null
}

export type CampoMetodo = 'nombre' | 'pasos' | 'plazo' | 'amarillo' | 'naranja' | 'primer'
export type ErroresMetodo = Partial<Record<CampoMetodo, string>>

export const esPlantilla = (m: Pick<MetodoFila, 'iglesia_id'>) => m.iglesia_id === null
export const esPropio = (m: Pick<MetodoFila, 'iglesia_id'>) => m.iglesia_id !== null

const entero = (v: number | string | null | undefined): number | null => {
  if (v === null || v === undefined || String(v).trim() === '') return null
  const n = Number(v)
  return Number.isInteger(n) ? n : NaN
}

/** Devuelve, por campo, la clave de traducción del error (seguimiento.errores.*). Vacío si el borrador es válido. */
export function validarMetodo(b: BorradorMetodo): ErroresMetodo {
  const e: ErroresMetodo = {}
  const nombre = (b.nombre ?? '').trim()
  if (nombre.length < 1) e.nombre = 'seguimiento.errores.nombreVacio'
  else if (nombre.length > MAX_NOMBRE) e.nombre = 'seguimiento.errores.nombreLargo'
  const pasos = entero(b.pasos)
  if (pasos === null || Number.isNaN(pasos) || pasos < 1 || pasos > 3) e.pasos = 'seguimiento.errores.pasos'
  const plazo = entero(b.plazo_horas)
  if (plazo === null || Number.isNaN(plazo) || plazo < 1 || plazo > MAX_PLAZO_HORAS) e.plazo = 'seguimiento.errores.plazo'
  const amarillo = entero(b.umbral_amarillo_horas)
  if (amarillo === null || Number.isNaN(amarillo) || amarillo < 1) e.amarillo = 'seguimiento.errores.amarillo'
  const naranja = entero(b.umbral_naranja_horas)
  if (naranja === null || Number.isNaN(naranja)) e.naranja = 'seguimiento.errores.naranja'
  else if (amarillo !== null && !Number.isNaN(amarillo) && naranja <= amarillo) e.naranja = 'seguimiento.errores.naranjaMenor'
  else if (!e.plazo && plazo !== null && naranja > plazo) e.naranja = 'seguimiento.errores.naranjaMayorPlazo'
  const primer = entero(b.primer_contacto_horas)
  if (primer !== null) {
    if (Number.isNaN(primer) || primer < 1) e.primer = 'seguimiento.errores.primer'
    else if (!e.plazo && plazo !== null && primer > plazo) e.primer = 'seguimiento.errores.primerMayorPlazo'
  }
  return e
}

export const esValido = (b: BorradorMetodo) => Object.keys(validarMetodo(b)).length === 0

export function borradorDe(m: MetodoFila): BorradorMetodo {
  return {
    nombre: m.nombre, pasos: m.pasos, plazo_horas: m.plazo_horas, umbral_amarillo_horas: m.umbral_amarillo_horas,
    umbral_naranja_horas: m.umbral_naranja_horas, primer_contacto_horas: m.primer_contacto_horas,
  }
}

/** Valores listos para enviar a la base (números, nombre sin espacios sobrantes). Solo se usa con un borrador válido. */
export function valoresDe(b: BorradorMetodo) {
  return {
    nombre: b.nombre.trim(),
    pasos: Number(b.pasos),
    plazo_horas: Number(b.plazo_horas),
    umbral_amarillo_horas: Number(b.umbral_amarillo_horas),
    umbral_naranja_horas: Number(b.umbral_naranja_horas),
    primer_contacto_horas: entero(b.primer_contacto_horas),
  }
}

/** ¿Cambia el borrador algo respecto al método guardado? */
export function hayCambios(m: MetodoFila, b: BorradorMetodo): boolean {
  const v = valoresDe(b), o = valoresDe(borradorDe(m))
  return (Object.keys(v) as (keyof typeof v)[]).some(k => v[k] !== o[k])
}

/** Los plazos y los colores son lo que mueve la fecha límite y el color de los procesos abiertos (el nombre o el número de pasos no) */
export function cambiaElPlazo(m: MetodoFila, b: BorradorMetodo): boolean {
  const v = valoresDe(b)
  return v.plazo_horas !== m.plazo_horas || v.umbral_amarillo_horas !== m.umbral_amarillo_horas || v.umbral_naranja_horas !== m.umbral_naranja_horas
}

/** Valores de una plantilla para «restaurar» un método propio que salió de ella */
export const restaurarDesde = (plantilla: MetodoFila, actual: BorradorMetodo): BorradorMetodo => ({ ...borradorDe(plantilla), nombre: actual.nombre })

/** Nombre y valores de una copia nueva a partir de un método (plantilla o propio) */
export function copiaDe(origen: MetodoFila, claves: string[], aleatorio: () => string = () => Math.random().toString(16).slice(2, 8)) {
  const sufijo = ' (copia)'
  const nombre = origen.nombre.length + sufijo.length > MAX_NOMBRE ? origen.nombre.slice(0, MAX_NOMBRE - sufijo.length) + sufijo : origen.nombre + sufijo
  return {
    clave: claveNueva(claves, aleatorio), nombre, plantilla_origen: origen.id, pasos: origen.pasos, plazo_horas: origen.plazo_horas,
    umbral_amarillo_horas: origen.umbral_amarillo_horas, umbral_naranja_horas: origen.umbral_naranja_horas, primer_contacto_horas: origen.primer_contacto_horas,
  }
}

/** Clave nueva «propio_xxxxxx» que no esté en uso y cumpla ^[a-z0-9_]{2,30}$ */
export function claveNueva(existentes: string[], aleatorio: () => string = () => Math.random().toString(16).slice(2, 8)): string {
  for (let i = 0; i < 50; i++) {
    const c = `propio_${aleatorio().toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 12)}`
    if (/^[a-z0-9_]{2,30}$/.test(c) && !existentes.includes(c)) return c
  }
  return `propio_${Date.now().toString(36)}`
}

/** Plantillas primero (OP72, luego Seguimiento simple), después los propios por nombre; los archivados no se ofrecen */
export function ordenarMetodos(metodos: MetodoFila[]): MetodoFila[] {
  const orden = (m: MetodoFila) => m.id === PLANTILLA_OP72_ID ? 0 : m.id === PLANTILLA_SIMPLE_ID ? 1 : esPlantilla(m) ? 2 : 3
  return metodos.filter(m => !m.archivado_en).sort((a, b) => orden(a) - orden(b) || a.nombre.localeCompare(b.nombre, 'es'))
}

/** Los cuatro tramos del semáforo con sus horas, para mostrarlos y compararlos */
export function tramos(m: Pick<MetodoFila, 'plazo_horas' | 'umbral_amarillo_horas' | 'umbral_naranja_horas'>) {
  return { verde: m.umbral_amarillo_horas, amarillo: m.umbral_naranja_horas, naranja: m.plazo_horas }
}

/** Traduce un error de la base a una clave de traducción (seguimiento.errores.*). Lo que no se reconoce se muestra genérico. */
export function errorDeBase(err: { message?: string; code?: string } | null | undefined): string {
  const t = `${err?.message ?? ''} ${err?.code ?? ''}`
  if (t.includes('ADN_DEMASIADOS_METODOS')) return 'seguimiento.errores.demasiados'
  if (t.includes('ADN_METODO_ACTIVO')) return 'seguimiento.errores.activo'
  if (t.includes('ADN_METODO_ARCHIVADO')) return 'seguimiento.errores.archivado'
  if (t.includes('ADN_METODO_DE_OTRA_IGLESIA') || t.includes('ADN_PLANTILLA_DE_OTRA_IGLESIA')) return 'seguimiento.errores.ajeno'
  if (t.includes('23505')) return 'seguimiento.errores.repetido'
  if (t.includes('42501') || t.toLowerCase().includes('row-level security') || t.toLowerCase().includes('permission denied')) return 'seguimiento.errores.permiso'
  return 'seguimiento.errores.generico'
}
