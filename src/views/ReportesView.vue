<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('reportes.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('reportes.subtitulo') }}</p>
    </div>

    <!-- Selector de período -->
    <div class="card flex flex-wrap items-center gap-3">
      <span class="text-sm font-medium text-gray-700">{{ t('reportes.periodo') }}</span>
      <div class="flex gap-2">
        <button
          v-for="p in periodos"
          :key="p.valor"
          @click="periodo = p.valor"
          :class="['text-sm px-3 py-1.5 rounded-lg font-medium transition-colors',
            periodo === p.valor ? 'bg-adn-verde text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']"
        >
          {{ t(p.label) }}
        </button>
      </div>
    </div>

    <!-- KPIs principales -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
      <div class="card-stat">
        <Users class="w-6 h-6 text-adn-verde flex-shrink-0" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ kpis.totalMiembros }}</p>
          <p class="text-xs text-gray-500">{{ t('reportes.miembrosActivos') }}</p>
          <p class="text-xs text-green-600 mt-0.5">{{ t('reportes.nuevos', kpis.nuevosMiembros) }}</p>
        </div>
      </div>
      <div class="card-stat">
        <HeartHandshake class="w-6 h-6 text-adn-verde flex-shrink-0" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ kpis.consolidacionesCompletadas }}</p>
          <p class="text-xs text-gray-500">{{ t('reportes.consolidaciones') }}</p>
          <p class="text-xs text-adn-verde mt-0.5">{{ t('reportes.tasaExito', { n: kpis.tasaExito }) }}</p>
        </div>
      </div>
      <div class="card-stat">
        <House class="w-6 h-6 text-adn-verde flex-shrink-0" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ kpis.casasActivas }}</p>
          <p class="text-xs text-gray-500">{{ t('reportes.casasActivas') }}</p>
        </div>
      </div>
      <div class="card-stat">
        <GraduationCap class="w-6 h-6 text-adn-verde flex-shrink-0" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ kpis.progresoFormacion }}</p>
          <p class="text-xs text-gray-500">{{ t('reportes.enFormacion') }}</p>
        </div>
      </div>
    </div>

    <!-- Consolidación por estado -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div class="card">
        <h2 class="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2"><HeartHandshake class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('reportes.consolidacion') }}</h2>
        <div class="space-y-3">
          <div v-for="estado in estadosConsolidacion" :key="estado.label" class="flex items-center gap-3">
            <component :is="estado.icono" :class="['w-5 h-5 flex-shrink-0', estado.tono]" aria-hidden="true" />
            <div class="flex-1">
              <div class="flex justify-between text-sm mb-1">
                <span class="text-gray-700">{{ t(estado.label) }}</span>
                <span class="font-semibold">{{ estado.count }}</span>
              </div>
              <div class="h-2 bg-gray-100 rounded-full overflow-hidden">
                <div :class="['h-full rounded-full', estado.color]"
                  :style="{ width: `${totalConsolidaciones ? (estado.count / totalConsolidaciones) * 100 : 0}%` }">
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Formación por nivel -->
      <div class="card">
        <h2 class="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2"><GraduationCap class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('reportes.alumnosPorNivel') }}</h2>
        <div class="space-y-3">
          <div v-for="nivel in nivelesFormacion" :key="nivel.clave" class="flex items-center gap-3">
            <component :is="nivel.icono" class="w-5 h-5 flex-shrink-0 text-adn-verde" aria-hidden="true" />
            <div class="flex-1">
              <div class="flex justify-between text-sm mb-1">
                <span class="text-gray-700">{{ t(nivel.nombre) }}</span>
                <span class="font-semibold">{{ nivel.count }}</span>
              </div>
              <div class="h-2 bg-gray-100 rounded-full overflow-hidden">
                <div class="h-full bg-adn-verde rounded-full"
                  :style="{ width: `${maxNivel ? (nivel.count / maxNivel) * 100 : 0}%` }">
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Distribución por zona -->
    <div class="card">
      <h2 class="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2"><MapIcon class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('reportes.distribucionZona') }}</h2>
      <div v-if="!zonas.length" class="py-8 text-center text-gray-400 text-sm">{{ t('reportes.sinZonas') }}</div>
      <div v-else class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
        <div v-for="z in zonas" :key="z.codigo" class="bg-gray-50 rounded-xl p-3 text-center">
          <p class="text-xs font-mono font-bold text-adn-verde">{{ z.codigo }}</p>
          <p class="text-xl font-bold text-gray-900 mt-1">{{ z.casas }}</p>
          <p class="text-xs text-gray-500">{{ t('reportes.casas', z.casas) }}</p>
          <p class="text-xs text-gray-400 mt-0.5">{{ t('reportes.miembros', z.miembros) }}</p>
        </div>
      </div>
    </div>

    <!-- Últimas consolidaciones completadas -->
    <div class="card">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><CircleCheck class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('reportes.completadasRecientes') }}</h2>
      </div>
      <div v-if="!completadas.length" class="py-8 text-center text-gray-400 text-sm">
        {{ t('reportes.sinCompletadas') }}
      </div>
      <div v-else class="divide-y divide-gray-50">
        <div v-for="c in completadas" :key="c.id" class="flex items-center justify-between py-3">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 bg-green-100 rounded-full flex items-center justify-center">
              <span class="text-green-600 text-sm font-bold">{{ c.miembros?.nombre?.[0] ?? '?' }}</span>
            </div>
            <div>
              <p class="text-sm font-medium text-gray-900">{{ c.miembros?.nombre }} {{ c.miembros?.apellido }}</p>
              <p class="text-xs text-gray-400">{{ formatFecha(c.fecha_conversion) }}</p>
            </div>
          </div>
          <span class="text-xs bg-green-100 text-green-700 px-2 py-1 rounded-full font-medium inline-flex items-center gap-1"><Check class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('comun.completado') }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Check, CircleCheck, Clock, GraduationCap, HandHelping, HeartHandshake, House, Leaf, MapIcon, Rocket, Siren, Sprout, Star, TriangleAlert, Users } from '@lucide/vue'
import { ref, computed, onMounted, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { alertaDe } from '@/lib/alertas'
import { useI18n } from 'vue-i18n'
import { formatoFecha } from '@/i18n'

const { t } = useI18n()

const periodo = ref('30')
// label: clave de traducción
const periodos = [
  { valor: '7', label: 'reportes.periodos.semana' },
  { valor: '30', label: 'reportes.periodos.mes' },
  { valor: '90', label: 'reportes.periodos.trimestre' },
  { valor: '365', label: 'reportes.periodos.anio' },
]

const kpis = ref({ totalMiembros: 0, nuevosMiembros: 0, consolidacionesCompletadas: 0, tasaExito: 0, casasActivas: 0, progresoFormacion: 0 })
const consolidacionData = ref({ verde: 0, amarillo: 0, naranja: 0, rojo: 0, completadas: 0 })
const nivelesData = ref<Record<string, number>>({})
const zonas = ref<any[]>([])
const completadas = ref<any[]>([])

const estadosConsolidacion = computed(() => [
  { label: 'alertas.rango.verde', icono: CircleCheck, tono: 'text-emerald-600', count: consolidacionData.value.verde, color: 'bg-green-400' },
  { label: 'alertas.rango.amarillo', icono: Clock, tono: 'text-amber-600', count: consolidacionData.value.amarillo, color: 'bg-yellow-400' },
  { label: 'alertas.rango.naranja', icono: TriangleAlert, tono: 'text-orange-600', count: consolidacionData.value.naranja, color: 'bg-orange-400' },
  { label: 'alertas.rango.rojo', icono: Siren, tono: 'text-red-600', count: consolidacionData.value.rojo, color: 'bg-red-500' },
])

const totalConsolidaciones = computed(() =>
  estadosConsolidacion.value.reduce((a, e) => a + e.count, 0)
)

const nivelesFormacion = computed(() => [
  { clave: '1', nombre: 'formacion.niveles.fundamentos', icono: Sprout, count: nivelesData.value['1'] ?? 0 },
  { clave: '2', nombre: 'formacion.niveles.crecimiento', icono: Leaf, count: nivelesData.value['2'] ?? 0 },
  { clave: '3', nombre: 'formacion.niveles.servicio', icono: HandHelping, count: nivelesData.value['3'] ?? 0 },
  { clave: '4', nombre: 'formacion.niveles.liderazgo', icono: Star, count: nivelesData.value['4'] ?? 0 },
  { clave: '5', nombre: 'formacion.niveles.multiplicacion', icono: Rocket, count: nivelesData.value['5'] ?? 0 },
])

const maxNivel = computed(() => Math.max(...nivelesFormacion.value.map(n => n.count), 1))

function formatFecha(fecha: string) {
  return formatoFecha(fecha, { day: '2-digit', month: 'short', year: 'numeric' })
}

function fechaDesde() {
  const d = new Date()
  d.setDate(d.getDate() - parseInt(periodo.value))
  return d.toISOString()
}

async function cargarReportes() {
  const desde = fechaDesde()
  const [miembrosRes, miembrosNuevosRes, consolRes, consolCompRes, casasRes, formacionRes, zonasRes, completadasRes] = await Promise.all([
    supabase.from('miembros').select('*', { count: 'exact', head: true }).eq('activo', true),
    supabase.from('miembros').select('*', { count: 'exact', head: true }).gte('created_at', desde),
    supabase.from('consolidaciones').select('fecha_conversion').eq('completado', false),
    supabase.from('consolidaciones').select('*', { count: 'exact', head: true }).eq('completado', true).gte('updated_at', desde),
    supabase.from('casas_oracion').select('*', { count: 'exact', head: true }).eq('activa', true),
    supabase.from('progreso_formacion').select('nivel').is('fecha_completado', null),
    supabase.from('casas_oracion').select('codigo_zona, miembros(count)').eq('activa', true),
    supabase.from('consolidaciones').select('*, miembros(nombre, apellido)').eq('completado', true).gte('updated_at', desde).order('updated_at', { ascending: false }).limit(8),
  ])

  kpis.value.totalMiembros = miembrosRes.count ?? 0
  kpis.value.nuevosMiembros = miembrosNuevosRes.count ?? 0
  kpis.value.consolidacionesCompletadas = consolCompRes.count ?? 0
  kpis.value.casasActivas = casasRes.count ?? 0
  kpis.value.progresoFormacion = formacionRes.data?.length ?? 0

  const totalConsol = (consolRes.data?.length ?? 0) + (consolCompRes.count ?? 0)
  kpis.value.tasaExito = totalConsol > 0 ? Math.round(((consolCompRes.count ?? 0) / totalConsol) * 100) : 0

  // Consolidación por estado
  const cd = { verde: 0, amarillo: 0, naranja: 0, rojo: 0, completadas: consolCompRes.count ?? 0 }
  consolRes.data?.forEach((c: any) => { cd[alertaDe(c.fecha_conversion, false)]++ })
  consolidacionData.value = cd

  // Formación por nivel
  const nd: Record<string, number> = {}
  formacionRes.data?.forEach((p: any) => { nd[p.nivel] = (nd[p.nivel] ?? 0) + 1 })
  nivelesData.value = nd

  // Zonas
  const zonasMap: Record<string, { casas: number; miembros: number }> = {}
  zonasRes.data?.forEach((c: any) => {
    const cod = c.codigo_zona?.split('-')[0] ?? 'N/A'
    if (!zonasMap[cod]) zonasMap[cod] = { casas: 0, miembros: 0 }
    zonasMap[cod].casas++
    zonasMap[cod].miembros += c.miembros?.[0]?.count ?? 0
  })
  zonas.value = Object.entries(zonasMap).map(([codigo, v]) => ({ codigo, ...v }))

  completadas.value = completadasRes.data ?? []
}

watch(periodo, cargarReportes)
onMounted(cargarReportes)
</script>
