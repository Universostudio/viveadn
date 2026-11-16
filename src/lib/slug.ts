// Dirección web (identificador) de una iglesia: lo que se escribe se normaliza al instante para que nadie tenga que adivinar el formato.
// Pura y probada en Node (scripts/probar-slug.mts). El servidor vuelve a validar con la misma regla.

export const SLUG_MIN = 3
export const SLUG_MAX = 40
export const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/

/** Minúsculas, sin tildes, y cualquier otro carácter (espacios, comas, barras bajas, puntos) pasa a un guion; sin guiones repetidos ni en los extremos */
export function normalizarSlug(texto: string): string {
  return texto
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, SLUG_MAX)
    .replace(/-+$/g, '')
}

export const slugValido = (s: string) => s.length >= SLUG_MIN && s.length <= SLUG_MAX && SLUG_RE.test(s)
