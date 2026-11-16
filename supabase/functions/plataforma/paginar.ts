// Lectura completa por páginas. El servicio alojado limita cuántas filas devuelve cada respuesta (por defecto en torno a 1.000, sin verificar aquí) y corta
// la lista en silencio; esta función sigue pidiendo páginas hasta que una viene vacía, de modo que vale cualquiera que sea el límite del servicio.
// Quien la use debe ordenar la consulta por una clave estable (si no, las páginas pueden repetir o saltarse filas).
export interface Pagina<T> { data: T[] | null; error: { message?: string } | null }

export async function leerTodo<T>(pagina: (desde: number, hasta: number) => PromiseLike<Pagina<T>>, tamano = 1000, tope = 200_000): Promise<{ data: T[]; error: { message?: string } | null }> {
  const filas: T[] = []
  for (let desde = 0; desde < tope; ) {
    const r = await pagina(desde, desde + tamano - 1)
    if (r.error) return { data: [], error: r.error }
    if (!r.data || r.data.length === 0) return { data: filas, error: null }
    filas.push(...r.data)
    desde += r.data.length
  }
  // Más filas que el tope: no se devuelve una lista cortada como si fuera completa
  return { data: [], error: { message: 'demasiadas filas' } }
}
