// Estado compartido del Panel Maestro: la lista de iglesias con sus conteos (nunca datos de personas), el catálogo de planes y módulos,
// los ajustes de registro y el estado de la purga. Todas las pantallas del panel leen de aquí y cualquier acción recarga.
import { defineStore } from 'pinia'
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { i18n } from '@/i18n'

export interface PurgaEstado { atrasada: boolean; en_borrado: number; vencidas: number; horas_mas_atrasada: number }
export interface EventoCrudo { tipo: 'alta' | 'accion'; accion: string; iglesia_id: string | null; iglesia: string | null; fecha: string }
export interface Sistema {
  purga: PurgaEstado | null
  libro: { iglesia: string; purgada_en: string }[] | null
  envio: { activo: boolean; hoy: number; por_tipo: Record<string, number>; tope_global: number; contadores: boolean } | null
}
export type Carga = 'pendiente' | 'cargando' | 'ok' | 'no'
export interface Registro { abierto: boolean; requiere_codigo: boolean; codigos: any[] }

export const usePlataformaStore = defineStore('plataforma', () => {
  const iglesias = ref<any[]>([])
  const planes = ref<any[]>([])
  const modulos = ref<any[]>([])
  const planModulos = ref<any[]>([])
  const registro = ref<Registro>({ abierto: false, requiere_codigo: true, codigos: [] })
  const purga = ref<PurgaEstado | null>(null)
  const cargando = ref(false)
  // Actividad global y estado del sistema: cada bloque carga por separado y, si falla, lo dice sin tumbar el resto
  const actividad = ref<EventoCrudo[]>([])
  const actividadEstado = ref<Carga>('pendiente')
  const sistema = ref<Sistema | null>(null)
  const sistemaEstado = ref<Carga>('pendiente')
  const cargada = ref(false)
  // Aviso como función para que se traduzca de nuevo si cambia el idioma
  const aviso = ref<{ texto: () => string; error: boolean } | null>(null)

  function avisar(texto: () => string, error = false) { aviso.value = { texto, error } }
  function limpiarAviso() { aviso.value = null }

  async function llamar(cuerpo: Record<string, unknown>) {
    const { data, error } = await supabase.functions.invoke('plataforma', { body: { ...cuerpo, origen: window.location.origin } })
    if (error) {
      // La función devuelve el motivo en el cuerpo de la respuesta de error
      let motivo = i18n.global.t('plataforma.errorGenerico')
      try {
        const resp = (error as any).context
        if (resp?.json) motivo = (await resp.json()).error ?? motivo
      } catch { /* se queda el mensaje genérico */ }
      throw new Error(motivo)
    }
    return data
  }

  // El estado de la purga no debe tumbar el panel: si falla, la tarjeta lo dice y el resto sigue funcionando
  async function cargarPurga() {
    try {
      const d = await llamar({ accion: 'estado_purga' })
      purga.value = typeof d?.atrasada === 'boolean'
        ? { atrasada: d.atrasada, en_borrado: Number(d.en_borrado) || 0, vencidas: Number(d.vencidas) || 0, horas_mas_atrasada: Number(d.horas_mas_atrasada) || 0 }
        : null
    } catch { purga.value = null }
  }

  async function cargarActividad(limite = 10) {
    actividadEstado.value = 'cargando'
    try {
      const d = await llamar({ accion: 'actividad', limite })
      actividad.value = Array.isArray(d?.eventos) ? d.eventos : []
      actividadEstado.value = 'ok'
    } catch { actividad.value = []; actividadEstado.value = 'no' }
  }

  async function cargarSistema() {
    sistemaEstado.value = 'cargando'
    try {
      const d = await llamar({ accion: 'sistema' })
      sistema.value = { purga: d?.purga ?? null, libro: Array.isArray(d?.libro) ? d.libro : null, envio: d?.envio ?? null }
      sistemaEstado.value = 'ok'
    } catch { sistema.value = null; sistemaEstado.value = 'no' }
  }

  async function cargar() {
    cargando.value = true
    try {
      const d = await llamar({ accion: 'listar' })
      iglesias.value = d.iglesias
      planes.value = d.planes
      modulos.value = d.modulos
      planModulos.value = d.plan_modulos
      registro.value = await llamar({ accion: 'registro_estado' })
      cargada.value = true
    } catch (e: any) {
      const texto = e.message
      avisar(() => texto, true)
    }
    await cargarPurga()
    cargando.value = false
  }

  async function asegurarCargada() { if (!cargada.value && !cargando.value) await cargar() }

  // Ejecuta una acción de escritura, avisa del resultado y recarga la lista
  async function ejecutar(cuerpo: Record<string, unknown>, ok: () => string) {
    try {
      await llamar(cuerpo)
      avisar(ok)
    } catch (e: any) {
      const texto = e.message
      avisar(() => texto, true)
    }
    await cargar()
  }

  function limpiar() {
    iglesias.value = []; planes.value = []; modulos.value = []; planModulos.value = []
    registro.value = { abierto: false, requiere_codigo: true, codigos: [] }
    purga.value = null; cargada.value = false; aviso.value = null
    actividad.value = []; actividadEstado.value = 'pendiente'; sistema.value = null; sistemaEstado.value = 'pendiente'
  }

  return { iglesias, planes, modulos, planModulos, registro, purga, cargando, cargada, aviso, actividad, actividadEstado, sistema, sistemaEstado, avisar, limpiarAviso, llamar, cargar, cargarPurga, cargarActividad, cargarSistema, asegurarCargada, ejecutar, limpiar }
})
