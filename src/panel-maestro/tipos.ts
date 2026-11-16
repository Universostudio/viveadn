// Contratos de las piezas del Panel Maestro. Son genéricos: no mencionan iglesias ni ningún producto concreto.
// Cada producto traduce las respuestas de su backend a estos tipos con un adaptador propio (docs/PANEL-MAESTRO.md).
import type { Component } from 'vue'

export interface ItemMenu {
  to: string
  etiqueta: string
  icono: Component
  /** Número que se muestra junto al ítem (por ejemplo, pruebas por vencer). null o ausente: sin número */
  contador?: number | null
  /** El ítem lleva a una pantalla que aún no tiene datos detrás */
  sinConectar?: boolean
  /** Activo solo con la ruta exacta (la portada) */
  exacto?: boolean
}

export interface GrupoMenu {
  titulo: string
  items: ItemMenu[]
}

export interface ModuloInquilino {
  clave: string
  nombre: string
  activo: boolean
}

/** Estados con significado propio en la tabla; cualquier otro se muestra con su etiqueta en gris */
export type EstadoInquilino = 'activa' | 'prueba' | 'suspendida' | 'onboarding' | 'receso' | string

export interface Inquilino {
  id: string
  nombre: string
  /** Segunda línea: dirección interna y ciudad, por ejemplo */
  subtitulo: string
  plan: { clave: string; nombre: string } | null
  estado: EstadoInquilino
  estadoEtiqueta: string
  /** Texto corto bajo el estado: días de prueba restantes, borrado programado... */
  detalleEstado?: string
  /** El detalle del estado merece atención (prueba por vencer, borrado vencido) */
  detalleUrgente?: boolean
  demo: boolean
  /** La iglesia está en baja: tiene una purga o un borrado programado (borrado suave o programado) */
  enBaja?: boolean
  /** Días enteros hasta la purga; negativo si ya venció; null si no está en baja */
  diasParaPurga?: number | null
  /** Conteos: nunca datos de personas */
  miembros: number
  modulos: ModuloInquilino[]
}

export interface AccionInquilino {
  clave: string
  etiqueta: string
  variante?: 'normal' | 'peligro'
  /** Si lleva a otra pantalla, la ruta; si no, la tabla emite el evento accion */
  ruta?: string
}

export type FiltroInquilinos = 'todas' | 'activas' | 'prueba' | 'suspendidas' | 'receso' | 'baja' | 'demo'

export interface Kpi {
  clave: string
  etiqueta: string
  /** null cuando no hay dato: se muestra «sin conectar» con la línea de sinConectar */
  valor: string | number | null
  nota?: string
  tono?: 'normal' | 'alerta' | 'bien'
  sinConectar?: string
}

export interface EventoActividad {
  id: string
  /** ISO 8601 */
  fecha: string
  texto: string
  tono?: 'normal' | 'alerta'
}

export type SituacionServicio = 'ok' | 'alerta' | 'apagado' | 'sin_conectar'

export interface EstadoServicio {
  clave: string
  etiqueta: string
  situacion: SituacionServicio
  detalle?: string
  /** 0 a 100 para dibujar una barra; ausente: solo la insignia */
  porcentaje?: number
}
