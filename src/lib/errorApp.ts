// Estado de error de la aplicación: cuando algo impide mostrar la pantalla normal, se enseña una pantalla propia
// con una salida clara en lugar de una página en blanco.
import { ref } from 'vue'

export type TipoError = 'inicio' | 'carga' | 'inesperado'

/** null mientras todo va bien */
export const errorApp = ref<TipoError | null>(null)

export function marcarError(tipo: TipoError) {
  // El primero manda: un error de carga no se tapa con otro posterior
  if (errorApp.value === null) errorApp.value = tipo
}

// Tras publicar una versión nueva, la página abierta pide un archivo que ya no existe. Cada navegador lo dice a su manera.
const CARGA_RE = /(failed to fetch dynamically imported module|error loading dynamically imported module|importing a module script failed|unable to preload css|loading (css )?chunk [\w-]+ failed)/i
export function esErrorDeCarga(e: unknown): boolean {
  const mensaje = e instanceof Error ? `${e.name} ${e.message}` : typeof e === 'string' ? e : ''
  return CARGA_RE.test(mensaje)
}
