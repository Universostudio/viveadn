// Supabase devuelve como máximo 1000 filas por petición. Este lector pide páginas hasta agotarlas.
// Devuelve null si alguna petición falla, para no mostrar datos incompletos como si fueran completos.
type Pagina<T> = PromiseLike<{ data: T[] | null; error: unknown }>

export async function leerTodo<T>(pedir: (desde: number, hasta: number) => Pagina<T>, tamano = 1000): Promise<T[] | null> {
  const todo: T[] = []
  for (let desde = 0; ; desde += tamano) {
    const { data, error } = await pedir(desde, desde + tamano - 1)
    if (error) return null
    todo.push(...(data ?? []))
    if ((data ?? []).length < tamano) return todo
  }
}
