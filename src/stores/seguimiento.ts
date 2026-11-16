import { defineStore } from 'pinia'
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { SELECT_METODO } from '@/lib/alertas'

// ¿Tiene ya la base de datos los métodos de seguimiento? La web de pruebas se despliega sola y la base la actualiza Gerencia cuando lo ordena,
// así que la interfaz funciona en los dos órdenes: sin métodos, todo se calcula como OP72 de siempre; con ellos, cada proceso usa el suyo.
// Se comprueba una vez por carga de la página, con una lectura mínima de la tabla de métodos.
export const useSeguimientoStore = defineStore('seguimiento', () => {
  const disponible = ref<boolean | null>(null)
  let pendiente: Promise<boolean> | null = null

  function asegurar(): Promise<boolean> {
    if (disponible.value !== null) return Promise.resolve(disponible.value)
    pendiente ??= (async () => {
      const { error } = await supabase.from('adn_seguimiento_metodos').select('id').limit(1)
      disponible.value = !error
      return disponible.value
    })()
    return pendiente
  }

  /** Texto para añadir al select de consolidaciones: pide el método de cada proceso si la base ya lo tiene, y nada si no */
  const embeber = () => (disponible.value ? `, ${SELECT_METODO}` : '')

  return { disponible, asegurar, embeber }
})
