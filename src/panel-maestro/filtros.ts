// Filtrado de la tabla de inquilinos, aparte de la vista para poder probarlo sin navegador
import type { FiltroInquilinos, Inquilino } from './tipos'

export const FILTROS: FiltroInquilinos[] = ['todas', 'activas', 'prueba', 'suspendidas', 'demo']

export function coincideFiltro(i: Inquilino, filtro: FiltroInquilinos): boolean {
  switch (filtro) {
    case 'activas': return i.estado === 'activa'
    case 'prueba': return i.estado === 'prueba'
    case 'suspendidas': return i.estado === 'suspendida'
    case 'demo': return i.demo
    default: return true
  }
}

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

export function coincideBusqueda(i: Inquilino, texto: string): boolean {
  const q = normalizar(texto.trim())
  if (!q) return true
  return normalizar(`${i.nombre} ${i.subtitulo}`).includes(q)
}

export function filtrarInquilinos(lista: Inquilino[], filtro: FiltroInquilinos, texto: string): Inquilino[] {
  return lista.filter(i => coincideFiltro(i, filtro) && coincideBusqueda(i, texto))
}

export function contarPorFiltro(lista: Inquilino[]): Record<FiltroInquilinos, number> {
  return Object.fromEntries(FILTROS.map(f => [f, lista.filter(i => coincideFiltro(i, f)).length])) as Record<FiltroInquilinos, number>
}
