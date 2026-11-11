import type { ClaveDocumento, TextosLegales } from './tipos'
import registro from './versiones.json'

export * from './tipos'

// Cada idioma se descarga solo cuando se necesita
const CARGADORES: Record<string, () => Promise<{ default: TextosLegales }>> = {
  es: () => import('./es'),
  en: () => import('./en'),
  fr: () => import('./fr'),
  'pt-BR': () => import('./ptBR'),
}

export async function cargarTextos(idioma: string): Promise<TextosLegales> {
  const carga = CARGADORES[idioma] ?? CARGADORES.es!
  return (await carga()).default
}

export interface VersionLegal { version: string; fecha: string; cambios: string }
export const versionesDe = (doc: ClaveDocumento): VersionLegal[] => (registro.documentos[doc]?.versiones ?? []).map(({ version, fecha, cambios }) => ({ version, fecha, cambios }))
export const versionActual = (doc: ClaveDocumento): VersionLegal => versionesDe(doc).at(-1)!
