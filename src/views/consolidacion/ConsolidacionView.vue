<template>
  <div class="p-4 sm:p-6 space-y-6">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('consolidacion.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('consolidacion.subtitulo') }}</p>
      </div>
      <button @click="abrirNuevo = true" class="btn-primary flex items-center gap-2">
        <UserPlus class="w-4 h-4" aria-hidden="true" /> {{ t('consolidacion.nuevo') }}
      </button>
    </div>

    <!-- Indicadores de estado -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div
        v-for="estado in estados"
        :key="estado.alerta"
        :class="['card-stat cursor-pointer border-l-4 transition-all', estado.clase,
          filtroActivo === estado.alerta ? 'ring-2 ring-offset-1 ring-adn-verde' : '']"
        @click="toggleFiltro(estado.alerta)"
      >
        <component :is="estado.icono" :class="['w-6 h-6 flex-shrink-0', estado.color]" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold">{{ estado.count }}</p>
          <p class="text-xs text-gray-600">{{ t(estado.label) }}</p>
        </div>
      </div>
    </div>

    <!-- OP72 avanzado: metricas del seguimiento. Sin el modulo, una tarjeta informativa -->
    <div v-if="verMetricas" class="card space-y-4">
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><ChartColumn class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('consolidacion.metricas.titulo') }}</h2>
        <select v-model.number="diasMetricas" @change="cargarMetricas" :aria-label="t('consolidacion.metricas.periodo')"
          class="text-sm border border-gray-200 rounded-lg px-2 py-1.5 bg-white">
          <option :value="7">{{ t('consolidacion.metricas.dias', { n: 7 }) }}</option>
          <option :value="30">{{ t('consolidacion.metricas.dias', { n: 30 }) }}</option>
          <option :value="90">{{ t('consolidacion.metricas.dias', { n: 90 }) }}</option>
        </select>
      </div>
      <p v-if="errorMetricas" class="text-sm text-red-600" role="alert">{{ t('consolidacion.metricas.error') }}</p>
      <p v-else-if="!metricas" class="text-sm text-gray-500" role="status">{{ t('comun.cargando') }}</p>
      <p v-else-if="metricas.total === 0" class="text-sm text-gray-500">{{ t('consolidacion.metricas.sinDatos') }}</p>
      <template v-else>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div v-for="k in tarjetasMetricas" :key="k.etiqueta" class="bg-gray-50 rounded-xl p-3">
            <p class="text-2xl font-bold text-gray-900">{{ k.valor }}</p>
            <p class="text-xs text-gray-500">{{ t(k.etiqueta) }}</p>
          </div>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div v-for="g in gruposMetricas" :key="g.titulo">
            <h3 class="text-sm font-semibold text-gray-700 mb-2">{{ t(g.titulo) }}</h3>
            <ul class="divide-y divide-gray-100 text-sm">
              <li v-for="f in g.filas" :key="f.id ?? 'sin'" class="flex items-center justify-between py-1.5 gap-3">
                <span class="truncate text-gray-700">{{ f.nombre || t('consolidacion.metricas.sinAsignar') }}</span>
                <span class="text-gray-500 whitespace-nowrap">{{ f.total }}<span v-if="f.vencidos" class="text-red-600"> · {{ t('consolidacion.metricas.vencidosN', { n: f.vencidos }) }}</span></span>
              </li>
            </ul>
          </div>
        </div>
      </template>
    </div>
    <div v-else-if="ofrecerMetricas" class="card flex items-start gap-3 bg-adn-arena/40">
      <ChartColumn class="w-6 h-6 text-adn-verde flex-shrink-0" aria-hidden="true" />
      <div>
        <p class="font-semibold text-gray-900">{{ t('consolidacion.metricas.promo') }}</p>
        <p class="text-sm text-gray-600">{{ t('consolidacion.metricas.promoAyuda') }}</p>
      </div>
    </div>

    <!-- Lista de consolidaciones -->
    <div class="card">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-gray-900">
          {{ t('consolidacion.activas') }}
          <span class="ml-2 text-sm font-normal text-gray-400">({{ consolidacionesFiltradas.length }})</span>
        </h2>
        <div class="flex items-center gap-2">
          <button
            v-if="filtroActivo"
            @click="filtroActivo = null"
            class="text-xs text-adn-verde hover:underline"
          >
            {{ t('consolidacion.limpiarFiltro') }}
          </button>
          <select
            v-model="ordenar"
            class="text-sm border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-adn-verde"
          >
            <option value="urgente">{{ t('consolidacion.ordenUrgente') }}</option>
            <option value="reciente">{{ t('consolidacion.ordenReciente') }}</option>
            <option value="nombre">{{ t('consolidacion.ordenNombre') }}</option>
          </select>
        </div>
      </div>

      <div v-if="cargando" class="py-12 text-center text-gray-400">
        <LoaderCircle class="w-8 h-8 mx-auto mb-2 animate-spin text-gray-300" aria-hidden="true" />
        <p>{{ t('consolidacion.cargando') }}</p>
      </div>

      <div v-else-if="consolidacionesFiltradas.length === 0" class="py-12 text-center text-gray-400">
        <CircleCheck class="w-10 h-10 mx-auto mb-2 text-emerald-500" aria-hidden="true" />
        <p class="font-medium">
          {{ filtroActivo ? t('consolidacion.sinEnEstado') : t('consolidacion.sinPendientes') }}
        </p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="c in consolidacionesFiltradas"
          :key="c.id"
          :class="['border rounded-xl p-4 transition-all hover:shadow-sm', claseBorde(c.estado_alerta)]"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="flex items-start gap-3">
              <!-- Avatar con alerta -->
              <div class="relative flex-shrink-0">
                <div class="w-11 h-11 bg-adn-verde rounded-full flex items-center justify-center">
                  <span class="text-white font-bold">{{ c.miembros?.nombre?.[0] ?? '?' }}</span>
                </div>
              </div>

              <!-- Info -->
              <div>
                <p class="font-semibold text-gray-900">
                  {{ c.miembros?.nombre }} {{ c.miembros?.apellido }}
                </p>
                <p class="text-xs text-gray-500 mt-0.5">{{ c.miembros?.crm_id }}</p>
                <div class="flex flex-wrap gap-3 mt-2 text-xs text-gray-500">
                  <span class="inline-flex items-center gap-1"><CalendarDays class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.conversionFecha', { fecha: formatFecha(c.fecha_conversion) }) }}</span>
                  <span class="inline-flex items-center gap-1"><Timer class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.transcurridas', { horas: horasTranscurridas(c.fecha_conversion) }) }}</span>
                  <span v-if="c.consolidador_perfil" class="inline-flex items-center gap-1">
                    <UserRound class="w-3.5 h-3.5" aria-hidden="true" /> {{ c.consolidador_perfil.nombre }} {{ c.consolidador_perfil.apellido }}
                  </span>
                </div>
                <p v-if="c.notas" class="text-xs text-gray-600 mt-2 bg-gray-50 rounded px-2 py-1 italic">
                  "{{ c.notas }}"
                </p>
              </div>
            </div>

            <!-- Acciones -->
            <div class="flex flex-col items-end gap-2 flex-shrink-0">
              <EstadoAlerta :estado="c.estado_alerta" />
              <div class="flex gap-2">
                <button
                  @click="verDetalle(c)"
                  class="text-xs text-adn-verde hover:underline font-medium"
                >
                  {{ t('consolidacion.verDetalles') }}
                </button>
                <button
                  @click="marcarCompletado(c.id)"
                  class="text-xs text-green-700 hover:underline font-medium inline-flex items-center gap-1"
                >
                  <Check class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.completar') }}
                </button>
              </div>
            </div>
          </div>

          <!-- Barra de progreso 72h -->
          <div class="mt-3">
            <div class="flex justify-between text-xs text-gray-400 mb-1">
              <span>{{ t('consolidacion.progreso') }}</span>
              <span>{{ t('consolidacion.limiteFecha', { fecha: formatFecha(c.fecha_limite) }) }}</span>
            </div>
            <div class="h-2 bg-gray-100 rounded-full overflow-hidden">
              <div
                :class="['h-full rounded-full transition-all', claseBarra(c.estado_alerta)]"
                :style="{ width: `${Math.min(progresoHoras(c.fecha_conversion), 100)}%` }"
              ></div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal: Nuevo convertido -->
    <div
      v-if="abrirNuevo"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="abrirNuevo = false"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ t('consolidacion.registrarTitulo') }}</h2>
        <form @submit.prevent="crearConsolidacion" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('consolidacion.miembro') }}</label>
            <select
              v-model="nuevo.miembro_id"
              required
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm"
            >
              <option value="">{{ t('consolidacion.seleccionarMiembro') }}</option>
              <option v-for="m in miembrosDisponibles" :key="m.id" :value="m.id">
                {{ m.nombre }} {{ m.apellido }} ({{ m.crm_id }})
              </option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('consolidacion.fechaConversion') }}</label>
            <input
              v-model="nuevo.fecha_conversion"
              type="datetime-local"
              required
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('consolidacion.notas') }}</label>
            <textarea
              v-model="nuevo.notas"
              rows="3"
              :placeholder="t('consolidacion.notasPlaceholder')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm resize-none"
            ></textarea>
          </div>
          <div class="flex gap-3 pt-2">
            <button type="button" @click="abrirNuevo = false" class="btn-secondary flex-1">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="guardando" class="btn-primary flex-1 disabled:opacity-60">
              {{ guardando ? t('consolidacion.registrando') : t('consolidacion.registrar') }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- Modal: Detalle consolidación -->
    <div
      v-if="detalleActivo"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="detalleActivo = null"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-lg p-6">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-bold text-gray-900">{{ t('consolidacion.detalleTitulo') }}</h2>
          <button @click="detalleActivo = null" class="text-gray-400 hover:text-gray-600 text-xl" :aria-label="t('comun.cerrar')">×</button>
        </div>
        <div v-if="detalleActivo" class="space-y-3 text-sm">
          <div class="bg-gray-50 rounded-xl p-4">
            <p class="font-semibold text-gray-900 text-base">
              {{ detalleActivo.miembros?.nombre }} {{ detalleActivo.miembros?.apellido }}
            </p>
            <p class="text-gray-500">{{ detalleActivo.miembros?.crm_id }}</p>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div class="bg-gray-50 rounded-lg p-3">
              <p class="text-xs text-gray-400">{{ t('consolidacion.estado') }}</p>
              <p class="font-semibold capitalize">{{ te(`alertas.color.${detalleActivo.estado_alerta}`) ? t(`alertas.color.${detalleActivo.estado_alerta}`) : detalleActivo.estado_alerta }}</p>
            </div>
            <div class="bg-gray-50 rounded-lg p-3">
              <p class="text-xs text-gray-400">{{ t('consolidacion.horasTranscurridas') }}</p>
              <p class="font-semibold">{{ horasTranscurridas(detalleActivo.fecha_conversion) }}h</p>
            </div>
            <div class="bg-gray-50 rounded-lg p-3">
              <p class="text-xs text-gray-400">{{ t('consolidacion.conversion') }}</p>
              <p class="font-semibold">{{ formatFecha(detalleActivo.fecha_conversion) }}</p>
            </div>
            <div class="bg-gray-50 rounded-lg p-3">
              <p class="text-xs text-gray-400">{{ t('consolidacion.limite') }}</p>
              <p class="font-semibold">{{ formatFecha(detalleActivo.fecha_limite) }}</p>
            </div>
          </div>
          <div v-if="detalleActivo.notas" class="bg-yellow-50 rounded-lg p-3">
            <p class="text-xs text-gray-400 mb-1">{{ t('consolidacion.notas') }}</p>
            <p class="italic text-gray-700">"{{ detalleActivo.notas }}"</p>
          </div>
          <button
            @click="marcarCompletado(detalleActivo.id); detalleActivo = null"
            class="w-full btn-primary mt-2 inline-flex items-center justify-center gap-2"
          >
            <Check class="w-4 h-4" aria-hidden="true" /> {{ t('consolidacion.marcarCompletado') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import EstadoAlerta from '@/components/EstadoAlerta.vue'
import { CalendarDays, ChartColumn, Check, CircleCheck, Clock, LoaderCircle, Siren, Timer, TriangleAlert, UserPlus, UserRound } from '@lucide/vue'
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { conAlerta } from '@/lib/alertas'
import type { AlertaColor } from '@/lib/supabase'
import { useI18n } from 'vue-i18n'
import { formatoFechaHora } from '@/i18n'
import { useAuthStore } from '@/stores/auth'

const { t, te } = useI18n()
const auth = useAuthStore()

// ---- OP72 avanzado (de pago) ----
const verMetricas = computed(() => auth.tieneModulo('op72_avanzado') && auth.can('consolidacion.ver'))
const ofrecerMetricas = computed(() => !auth.tieneModulo('op72_avanzado') && auth.can('consolidacion.ver'))
const metricas = ref<any>(null)
const errorMetricas = ref(false)
const diasMetricas = ref(30)

async function cargarMetricas() {
  if (!verMetricas.value) return
  metricas.value = null
  errorMetricas.value = false
  const { data, error } = await supabase.rpc('metricas_op72', { p_desde: new Date(Date.now() - diasMetricas.value * 86_400_000).toISOString() })
  if (error) { errorMetricas.value = true; return }
  metricas.value = data
}

const pct = (n: number, d: number) => (d > 0 ? `${Math.round((n / d) * 100)}%` : '0%')
const tarjetasMetricas = computed(() => {
  const m = metricas.value
  if (!m) return []
  return [
    { etiqueta: 'consolidacion.metricas.total', valor: m.total },
    { etiqueta: 'consolidacion.metricas.contacto24h', valor: pct(m.primer_contacto_24h, m.total) },
    { etiqueta: 'consolidacion.metricas.horasPrimerContacto', valor: m.horas_primer_contacto == null ? '-' : `${m.horas_primer_contacto} h` },
    { etiqueta: 'consolidacion.metricas.completados72h', valor: pct(m.completados_72h, m.total) },
    { etiqueta: 'consolidacion.metricas.completados', valor: m.completados },
    { etiqueta: 'consolidacion.metricas.abiertos', valor: m.abiertos },
    { etiqueta: 'consolidacion.metricas.vencidos', valor: m.vencidos },
    { etiqueta: 'consolidacion.metricas.conContacto', valor: pct(m.con_primer_contacto, m.total) },
  ]
})
const gruposMetricas = computed(() => {
  const m = metricas.value
  if (!m) return []
  return [
    { titulo: 'consolidacion.metricas.porConsolidador', filas: (m.por_consolidador ?? []).map((f: any) => ({ id: f.consolidador_id, nombre: f.nombre, total: f.total, vencidos: f.vencidos })) },
    { titulo: 'consolidacion.metricas.porCasa', filas: (m.por_casa ?? []).map((f: any) => ({ id: f.casa_oracion_id, nombre: f.nombre, total: f.total, vencidos: f.vencidos })) },
  ]
})

const cargando = ref(true)
const consolidaciones = ref<any[]>([])
const miembrosDisponibles = ref<any[]>([])
const filtroActivo = ref<AlertaColor | null>(null)
const ordenar = ref('urgente')
const abrirNuevo = ref(false)
const guardando = ref(false)
const detalleActivo = ref<any>(null)

const nuevo = ref({
  miembro_id: '',
  fecha_conversion: new Date().toISOString().slice(0, 16),
  notas: '',
})

// Helpers
function horasTranscurridas(fecha: string) {
  return Math.floor((Date.now() - new Date(fecha).getTime()) / 3600000)
}

function progresoHoras(fecha: string) {
  return (horasTranscurridas(fecha) / 72) * 100
}

function formatFecha(fecha: string) {
  if (!fecha) return '—'
  return formatoFechaHora(fecha, {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit'
  })
}

function claseBorde(alerta: AlertaColor) {
  const m: Record<AlertaColor, string> = {
    verde: 'border-green-200 bg-green-50/30',
    amarillo: 'border-yellow-200 bg-yellow-50/30',
    naranja: 'border-orange-200 bg-orange-50/30',
    rojo: 'border-red-200 bg-red-50/30',
  }
  return m[alerta] ?? 'border-gray-200'
}

function claseBarra(alerta: AlertaColor) {
  const m: Record<AlertaColor, string> = {
    verde: 'bg-green-400', amarillo: 'bg-yellow-400',
    naranja: 'bg-orange-400', rojo: 'bg-red-500',
  }
  return m[alerta] ?? 'bg-gray-400'
}

// Estados para los indicadores (label: clave de traducción)
const estados = computed(() => {
  const conteo = { verde: 0, amarillo: 0, naranja: 0, rojo: 0 }
  consolidaciones.value.forEach(c => { conteo[c.estado_alerta as AlertaColor]++ })
  return [
    { alerta: 'verde' as AlertaColor, icono: CircleCheck, color: 'text-emerald-600', label: 'alertas.rango.verde', count: conteo.verde, clase: 'border-green-400' },
    { alerta: 'amarillo' as AlertaColor, icono: Clock, color: 'text-amber-600', label: 'alertas.rango.amarillo', count: conteo.amarillo, clase: 'border-yellow-400' },
    { alerta: 'naranja' as AlertaColor, icono: TriangleAlert, color: 'text-orange-600', label: 'alertas.rango.naranja', count: conteo.naranja, clase: 'border-orange-400' },
    { alerta: 'rojo' as AlertaColor, icono: Siren, color: 'text-red-600', label: 'alertas.rango.rojo', count: conteo.rojo, clase: 'border-red-400' },
  ]
})

// Filtrado y ordenación
const consolidacionesFiltradas = computed(() => {
  let lista = [...consolidaciones.value]
  if (filtroActivo.value) lista = lista.filter(c => c.estado_alerta === filtroActivo.value)

  if (ordenar.value === 'urgente') {
    const orden: Record<AlertaColor, number> = { rojo: 0, naranja: 1, amarillo: 2, verde: 3 }
    lista.sort((a, b) => (orden[a.estado_alerta as AlertaColor] ?? 9) - (orden[b.estado_alerta as AlertaColor] ?? 9))
  } else if (ordenar.value === 'reciente') {
    lista.sort((a, b) => new Date(b.fecha_conversion).getTime() - new Date(a.fecha_conversion).getTime())
  } else {
    lista.sort((a, b) => (a.miembros?.nombre ?? '').localeCompare(b.miembros?.nombre ?? ''))
  }
  return lista
})

function toggleFiltro(alerta: AlertaColor) {
  filtroActivo.value = filtroActivo.value === alerta ? null : alerta
}

function verDetalle(c: any) {
  detalleActivo.value = c
}

async function cargarDatos() {
  cargando.value = true
  const [consolRes, miembrosRes] = await Promise.all([
    supabase
      .from('consolidaciones')
      .select('*, miembros!consolidaciones_miembro_fk(id, nombre, apellido, crm_id), consolidador_perfil:perfiles!consolidaciones_consolidador_fk(nombre, apellido)')
      .eq('completado', false)
      .order('fecha_conversion', { ascending: true }),
    supabase
      .from('miembros')
      .select('id, nombre, apellido, crm_id')
      .eq('activo', true)
      .order('nombre'),
  ])
  consolidaciones.value = (consolRes.data ?? []).map(conAlerta)
  miembrosDisponibles.value = miembrosRes.data ?? []
  cargando.value = false
}

async function crearConsolidacion() {
  guardando.value = true
  const { error } = await supabase.from('consolidaciones').insert({
    miembro_id: nuevo.value.miembro_id,
    fecha_conversion: nuevo.value.fecha_conversion,
    notas: nuevo.value.notas || null,
  })
  guardando.value = false
  if (!error) {
    abrirNuevo.value = false
    nuevo.value = { miembro_id: '', fecha_conversion: new Date().toISOString().slice(0, 16), notas: '' }
    await cargarDatos()
  }
}

async function marcarCompletado(id: string) {
  await supabase.from('consolidaciones').update({ completado: true }).eq('id', id)
  consolidaciones.value = consolidaciones.value.filter(c => c.id !== id)
}

onMounted(() => { cargarDatos(); cargarMetricas() })
</script>
