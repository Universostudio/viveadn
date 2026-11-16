import { defineStore } from 'pinia'
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { avisosVisibles, type EntregaAviso } from '@/lib/soporte'

// Novedades y avisos de la plataforma para la iglesia. La web de pruebas se despliega sola y la base la actualiza Gerencia cuando lo ordena, así que se comprueba
// una vez por carga si las tablas existen: sin ellas no se ofrece nada (ni menú, ni avisos) y no se muestra ningún cero inventado.
export const useSoporteStore = defineStore('soporte', () => {
  const disponible = ref<boolean | null>(null)
  let pendiente: Promise<boolean> | null = null
  const novedadesSinVer = ref(0)
  const avisos = ref<ReturnType<typeof avisosVisibles>>([])

  function asegurar(): Promise<boolean> {
    if (disponible.value !== null) return Promise.resolve(disponible.value)
    pendiente ??= (async () => {
      const { error } = await supabase.from('adn_novedades').select('id').limit(1)
      disponible.value = !error
      return disponible.value
    })()
    return pendiente
  }

  /** Cuántas novedades se publicaron después de la última vez que esta persona las miró */
  async function contarNovedades() {
    if (!(await asegurar())) { novedadesSinVer.value = 0; return }
    const { data: vista } = await supabase.from('adn_novedades_vistas').select('vista_en').maybeSingle()
    let q = supabase.from('adn_novedades').select('*', { count: 'exact', head: true })
    if (vista?.vista_en) q = q.gt('publicada_en', vista.vista_en)
    const { count } = await q
    novedadesSinVer.value = count ?? 0
  }

  async function marcarNovedadesVistas() {
    if (!(await asegurar())) return
    const { error } = await supabase.rpc('adn_novedades_marcar_vistas')
    if (!error) novedadesSinVer.value = 0
  }

  /** Avisos de la plataforma para esta iglesia. Al mostrarse por primera vez quedan marcados como leídos */
  async function cargarAvisos() {
    if (!(await asegurar())) { avisos.value = []; return }
    const { data, error } = await supabase.from('adn_avisos_entregas').select('aviso_id, leido_en, descartado_en, aviso:adn_avisos(id, tipo, titulo, texto)').is('descartado_en', null)
    if (error) { avisos.value = []; return }
    avisos.value = avisosVisibles(data as unknown as EntregaAviso[])
    const nuevos = avisos.value.filter(a => !a.leido).map(a => a.id)
    if (nuevos.length) {
      await supabase.from('adn_avisos_entregas').update({ leido_en: new Date().toISOString() }).in('aviso_id', nuevos).is('leido_en', null)
      avisos.value = avisos.value.map(a => ({ ...a, leido: true }))
    }
  }

  async function descartar(id: string) {
    const ahora = new Date().toISOString()
    const { error } = await supabase.from('adn_avisos_entregas').update({ descartado_en: ahora }).eq('aviso_id', id)
    if (!error) avisos.value = avisos.value.filter(a => a.id !== id)
    return !error
  }

  function limpiar() { disponible.value = null; pendiente = null; novedadesSinVer.value = 0; avisos.value = [] }

  return { disponible, novedadesSinVer, avisos, asegurar, contarNovedades, marcarNovedadesVistas, cargarAvisos, descartar, limpiar }
})
