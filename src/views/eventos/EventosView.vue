<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div class="flex items-center justify-between gap-3 flex-wrap">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('eventos.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('eventos.subtitulo') }}</p>
      </div>
      <button v-if="puedeGestionar" @click="abrirNuevo" class="btn-primary flex items-center gap-2">
        <CalendarPlus class="w-4 h-4" aria-hidden="true" /> {{ t('eventos.nuevo') }}
      </button>
    </div>

    <div class="card flex flex-col sm:flex-row gap-3">
      <div class="flex gap-1" role="group" :aria-label="t('eventos.titulo')">
        <button v-for="v in ['proximos', 'pasados']" :key="v" @click="vista = v as 'proximos' | 'pasados'"
          :aria-pressed="vista === v"
          :class="['px-4 py-2 text-sm font-medium rounded-lg transition-colors', vista === v ? 'bg-adn-verde text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']">
          {{ t(`eventos.${v}`) }}
        </button>
      </div>
      <select v-model="filtroTipo" :aria-label="t('eventos.campoTipo')" class="px-3 py-2 border border-gray-200 rounded-lg text-sm bg-white sm:w-56">
        <option value="">{{ t('eventos.todosTipos') }}</option>
        <option v-for="tp in TIPOS" :key="tp" :value="tp">{{ t(`eventos.tipo.${tp}`) }}</option>
      </select>
    </div>

    <div v-if="cargando" class="card py-10 text-center text-gray-400 text-sm" role="status">{{ t('comun.cargando') }}</div>
    <div v-else-if="!visibles.length" class="card py-10 text-center text-gray-400 text-sm">{{ t(vista === 'proximos' ? 'eventos.vacio' : 'eventos.vacioPasados') }}</div>
    <div v-else class="space-y-3">
      <RouterLink v-for="e in visibles" :key="e.id" :to="`/eventos/${e.id}`"
        class="card flex items-center gap-4 hover:shadow-md transition-shadow focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde">
        <div :class="['w-14 h-14 rounded-xl flex flex-col items-center justify-center flex-shrink-0', e.cancelado ? 'bg-gray-100 text-gray-400' : 'bg-adn-verde/10 text-adn-verde']">
          <span class="text-xs uppercase leading-none">{{ fecha(e.inicia_en, { month: 'short' }) }}</span>
          <span class="text-xl font-bold leading-tight">{{ fecha(e.inicia_en, { day: 'numeric' }) }}</span>
        </div>
        <div class="min-w-0 flex-1">
          <p :class="['font-semibold truncate', e.cancelado ? 'text-gray-400 line-through' : 'text-gray-900']">{{ e.titulo }}</p>
          <p class="text-sm text-gray-500 truncate">
            {{ fecha(e.inicia_en, { weekday: 'long', hour: '2-digit', minute: '2-digit' }) }}
            <template v-if="e.casas_oracion?.nombre"> · {{ e.casas_oracion.nombre }}</template>
            <template v-else-if="e.lugar"> · {{ e.lugar }}</template>
          </p>
        </div>
        <div class="text-right flex-shrink-0 space-y-1">
          <span class="inline-block text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-600">{{ t(`eventos.tipo.${e.tipo}`) }}</span>
          <p v-if="e.cancelado" class="text-xs font-medium text-red-600">{{ t('eventos.cancelado') }}</p>
          <p v-else-if="conteo[e.id] !== undefined" class="text-xs text-gray-500">{{ t('eventos.presentes', { n: conteo[e.id] }) }}</p>
        </div>
      </RouterLink>
      <button v-if="hayMas" @click="verMas" class="btn-secondary w-full text-sm">{{ t('eventos.verMas') }}</button>
    </div>

    <!-- Modal: nuevo evento -->
    <div v-if="abierto" class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50" @click.self="abierto = false" role="dialog" aria-modal="true" :aria-label="t('eventos.nuevo')">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ t('eventos.nuevo') }}</h2>
        <form @submit.prevent="crear" class="space-y-4">
          <div>
            <label for="ev-titulo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoTitulo') }}</label>
            <input id="ev-titulo" v-model="form.titulo" required maxlength="150" :placeholder="t('eventos.ejemploTitulo')" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label for="ev-tipo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoTipo') }}</label>
              <select id="ev-tipo" v-model="form.tipo" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm bg-white">
                <option v-for="tp in TIPOS" :key="tp" :value="tp">{{ t(`eventos.tipo.${tp}`) }}</option>
              </select>
            </div>
            <div>
              <label for="ev-casa" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoCasa') }}</label>
              <select id="ev-casa" v-model="form.casa_id" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm bg-white">
                <option value="">{{ t('eventos.sinCasa') }}</option>
                <option v-for="c in casas" :key="c.id" :value="c.id">{{ c.nombre || c.codigo_zona }}</option>
              </select>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label for="ev-inicio" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoInicio') }}</label>
              <input id="ev-inicio" v-model="form.inicio" type="datetime-local" required class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm" />
            </div>
            <div>
              <label for="ev-fin" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoFin') }}</label>
              <input id="ev-fin" v-model="form.fin" type="datetime-local" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm" />
            </div>
          </div>
          <div>
            <label for="ev-lugar" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoLugar') }}</label>
            <input id="ev-lugar" v-model="form.lugar" maxlength="200" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <div>
            <label for="ev-desc" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoDescripcion') }}</label>
            <textarea id="ev-desc" v-model="form.descripcion" rows="2" maxlength="2000" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm"></textarea>
          </div>
          <div class="rounded-xl bg-gray-50 p-3 space-y-2">
            <label class="flex items-center gap-2 text-sm font-medium text-gray-700">
              <input v-model="form.repetir" type="checkbox" class="rounded border-gray-300 text-adn-verde" /> {{ t('eventos.repetir') }}
            </label>
            <div v-if="form.repetir" class="flex items-center gap-2 text-sm text-gray-600">
              <label for="ev-veces">{{ t('eventos.repetirVeces') }}</label>
              <input id="ev-veces" v-model.number="form.veces" type="number" min="2" :max="MAX_SERIE" class="w-20 px-2 py-1.5 border border-gray-200 rounded-lg text-sm" />
            </div>
          </div>
          <p v-if="errorForm" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(errorForm, { n: MAX_SERIE }) }}</p>
          <div class="flex justify-end gap-3">
            <button type="button" @click="abierto = false" class="btn-secondary text-sm">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="guardando" class="btn-primary text-sm disabled:opacity-60">{{ guardando ? t('comun.guardando') : t('eventos.crear') }}</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { CalendarPlus } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { TIPOS_EVENTO as TIPOS, MAX_SERIE, fechasDeSerie, DURACION_POR_DEFECTO_MS } from '@/lib/eventos'
import { leerTodo } from '@/lib/paginar'

const { t, locale } = useI18n()
const auth = useAuthStore()
const puedeGestionar = computed(() => auth.can('eventos.gestionar'))

const cargando = ref(true)
const eventos = ref<any[]>([])
const casas = ref<any[]>([])
const conteo = ref<Record<string, number>>({})
const vista = ref<'proximos' | 'pasados'>('proximos')
const filtroTipo = ref('')
const abierto = ref(false)
const guardando = ref(false)
const errorForm = ref('')
const form = ref(formVacio())

function formVacio() {
  return { titulo: '', tipo: 'culto', casa_id: '', inicio: '', fin: '', lugar: '', descripcion: '', repetir: false, veces: 4 }
}

const fecha = (iso: string, opciones: Intl.DateTimeFormatOptions) => new Date(iso).toLocaleString(locale.value, opciones)

// El servidor ya devuelve la vista pedida (próximos desde el más cercano, pasados desde el más reciente)
const visibles = computed(() => eventos.value)

const POR_VISTA = 100
const limite = ref(POR_VISTA)
const hayMas = ref(false)

// Cuántos asistieron a cada evento, contando todas las filas (no solo la primera página de 1000)
async function contarPresentes(ids: string[]): Promise<Record<string, number> | null> {
  const c: Record<string, number> = Object.fromEntries(ids.map(id => [id, 0]))
  // Se piden de 50 en 50 eventos para que la dirección de la petición no sea demasiado larga
  for (let i = 0; i < ids.length; i += 50) {
    const lote = ids.slice(i, i + 50)
    const filas = await leerTodo<{ evento_id: string }>((d, h) =>
      supabase.from('asistencia_evento').select('evento_id').eq('presente', true).in('evento_id', lote).order('id').range(d, h))
    if (!filas) return null
    for (const a of filas) c[a.evento_id] = (c[a.evento_id] ?? 0) + 1
  }
  return c
}

async function cargar() {
  cargando.value = true
  // Un evento es "próximo" hasta que termina o, sin hora de fin, durante 3 horas desde que empieza
  const limiteSinFin = new Date(Date.now() - DURACION_POR_DEFECTO_MS).toISOString()
  const ahora = new Date().toISOString()
  const proximos = vista.value === 'proximos'
  let q = supabase.from('eventos')
    .select('id, titulo, tipo, inicia_en, termina_en, lugar, cancelado, casa_oracion_id, casas_oracion!eventos_casa_fk(nombre)')
    .or(proximos
      ? `termina_en.gte.${ahora},and(termina_en.is.null,inicia_en.gte.${limiteSinFin})`
      : `termina_en.lt.${ahora},and(termina_en.is.null,inicia_en.lt.${limiteSinFin})`)
    .order('inicia_en', { ascending: proximos })
  if (filtroTipo.value) q = q.eq('tipo', filtroTipo.value)
  const [ev, cs] = await Promise.all([
    q.limit(limite.value + 1),
    casas.value.length ? Promise.resolve({ data: casas.value }) : supabase.from('casas_oracion').select('id, nombre, codigo_zona').eq('activa', true).order('nombre'),
  ])
  const filas = ev.data ?? []
  hayMas.value = filas.length > limite.value
  eventos.value = filas.slice(0, limite.value)
  casas.value = cs.data ?? []
  cargando.value = false
  conteo.value = {}
  if (auth.can('asistencia.ver') && eventos.value.length) conteo.value = (await contarPresentes(eventos.value.map(e => e.id))) ?? {}
}

// Al cambiar de vista o de tipo se empieza de nuevo desde la primera página
watch([vista, filtroTipo], () => { limite.value = POR_VISTA; cargar() })

function verMas() { limite.value += POR_VISTA; cargar() }

function abrirNuevo() {
  form.value = formVacio()
  errorForm.value = ''
  abierto.value = true
}

async function crear() {
  errorForm.value = ''
  const f = form.value
  const inicio = new Date(f.inicio)
  const fin = f.fin ? new Date(f.fin) : null
  if (Number.isNaN(inicio.getTime())) { errorForm.value = 'eventos.errorFechas'; return }
  if (fin && fin <= inicio) { errorForm.value = 'eventos.errorFechas'; return }
  const veces = f.repetir ? Math.floor(f.veces) : 1
  if (f.repetir && !(veces >= 2 && veces <= MAX_SERIE)) { errorForm.value = 'eventos.errorVeces'; return }
  const serie = f.repetir ? crypto.randomUUID() : null
  const filas = fechasDeSerie(inicio, fin, veces).map(d => ({
    titulo: f.titulo.trim(), tipo: f.tipo, lugar: f.lugar.trim() || null, descripcion: f.descripcion.trim() || null,
    casa_oracion_id: f.casa_id || null, serie_id: serie,
    inicia_en: d.inicio.toISOString(), termina_en: d.fin ? d.fin.toISOString() : null,
  }))
  guardando.value = true
  const { error } = await supabase.from('eventos').insert(filas)
  guardando.value = false
  if (error) { errorForm.value = 'eventos.errorCrear'; return }
  abierto.value = false
  await cargar()
}

onMounted(cargar)
</script>
