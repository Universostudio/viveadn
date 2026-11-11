<template>
  <div class="p-4 sm:p-6 space-y-6">
    <!-- Header -->
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div class="min-w-0">
        <h1 class="text-2xl font-bold text-gray-900">{{ t('panel.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('panel.bienvenida', { nombre: auth.perfil?.nombre ?? '', fecha: fechaHoy }) }}</p>
      </div>
      <RouterLink :to="{ path: '/miembros', query: { nuevo: '1' } }" class="btn-primary inline-flex items-center gap-2 whitespace-nowrap">
        <UserPlus class="w-4 h-4" aria-hidden="true" /> {{ t('miembros.nuevo') }}
      </RouterLink>
    </div>

    <div v-if="faltaSegundoSuper" role="alert" class="rounded-lg border border-amber-300 bg-amber-50 text-amber-900 text-sm p-3">
      {{ t('panel.faltaSegundoSuper') }}
      <RouterLink to="/configuracion" class="underline font-medium">{{ t('panel.faltaSegundoSuperAccion') }}</RouterLink>
    </div>

    <BotonesDar />

    <!-- Stats principales -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      <div class="card-stat">
        <div class="w-12 h-12 bg-adn-verde/10 rounded-xl flex items-center justify-center flex-shrink-0">
          <Users class="w-6 h-6 text-adn-verde" aria-hidden="true" />
        </div>
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ stats.totalMiembros }}</p>
          <p class="text-sm text-gray-500">{{ t('panel.totalMiembros') }}</p>
        </div>
      </div>

      <div class="card-stat">
        <div class="w-12 h-12 bg-yellow-100 rounded-xl flex items-center justify-center flex-shrink-0">
          <House class="w-6 h-6 text-yellow-700" aria-hidden="true" />
        </div>
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ stats.totalCasas }}</p>
          <p class="text-sm text-gray-500">{{ t('panel.casas') }}</p>
        </div>
      </div>

      <div class="card-stat">
        <div class="w-12 h-12 bg-green-100 rounded-xl flex items-center justify-center flex-shrink-0">
          <HeartHandshake class="w-6 h-6 text-green-700" aria-hidden="true" />
        </div>
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ stats.consolidacionesActivas }}</p>
          <p class="text-sm text-gray-500">{{ t('panel.enConsolidacion') }}</p>
        </div>
      </div>

      <div class="card-stat border-l-4 border-red-400">
        <div class="w-12 h-12 bg-red-100 rounded-xl flex items-center justify-center flex-shrink-0">
          <Siren class="w-6 h-6 text-red-600" aria-hidden="true" />
        </div>
        <div>
          <p class="text-2xl font-bold text-red-600">{{ stats.alertasCriticas }}</p>
          <p class="text-sm text-gray-500">{{ t('panel.alertasCriticas') }}</p>
        </div>
      </div>
    </div>

    <p v-if="errorPanel" class="text-sm text-red-600" role="alert">{{ errorPanel }}</p>

    <!-- Bloques con datos reales de adn_panel_inicio; cada uno aparece según los permisos del rol -->
    <div v-if="panel" class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <!-- Asistencia -->
      <div v-if="auth.can('asistencia.ver')" class="card">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2 mb-1">
          <CalendarCheck class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('panel.asistencia.titulo') }}
        </h2>
        <p class="text-2xl font-bold text-gray-900">{{ panel.asistencia.semana_actual.presentes }}</p>
        <p class="text-xs text-gray-500 mb-3">
          {{ t('panel.asistencia.semanaActual') }} ·
          {{ variacion(panel.asistencia.semana_actual.presentes, panel.asistencia.semana_anterior.presentes) }}
        </p>
        <div class="flex items-end gap-1.5 h-24" role="img" :aria-label="t('panel.asistencia.grafico', { n: panel.asistencia.serie.length })">
          <div v-for="s in panel.asistencia.serie" :key="s.semana" class="flex-1 flex flex-col items-center justify-end h-full min-w-0">
            <div class="w-full rounded-t bg-adn-verde/70" :style="{ height: altura(s.presentes, maxAsistencia) }" :title="`${s.semana}: ${s.presentes}`"></div>
          </div>
        </div>
        <p class="text-xs text-gray-400 mt-1">{{ t('panel.asistencia.pie') }}</p>
      </div>

      <!-- Crecimiento -->
      <div v-if="auth.can('miembros.ver')" class="card">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2 mb-1">
          <TrendingUp class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('panel.crecimiento.titulo') }}
        </h2>
        <p class="text-2xl font-bold text-gray-900">{{ panel.miembros.nuevos_30d }}</p>
        <p class="text-xs text-gray-500 mb-3">
          {{ t('panel.crecimiento.nuevos30') }} ·
          {{ variacion(panel.miembros.nuevos_30d, panel.miembros.nuevos_30d_previos) }}
        </p>
        <div class="flex items-end gap-1.5 h-24" role="img" :aria-label="t('panel.crecimiento.grafico', { n: panel.crecimiento.length })">
          <div v-for="c in panel.crecimiento" :key="c.mes" class="flex-1 flex flex-col items-center justify-end h-full min-w-0">
            <div class="w-full rounded-t bg-amber-400/80" :style="{ height: altura(c.nuevos, maxCrecimiento) }" :title="`${c.mes.slice(0, 7)}: ${c.nuevos}`"></div>
            <span class="text-[10px] text-gray-400 mt-0.5">{{ c.mes.slice(5, 7) }}</span>
          </div>
        </div>
        <p class="text-xs text-gray-400 mt-1">
          {{ t('panel.crecimiento.detalle', { sinCasa: panel.miembros.sin_casa, bautizados: panel.miembros.bautizados }) }}
        </p>
      </div>

      <!-- Eventos próximos -->
      <div v-if="auth.can('eventos.ver')" class="card">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2">
            <CalendarDays class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('panel.eventos.titulo') }}
          </h2>
          <RouterLink to="/eventos" class="text-sm text-adn-verde hover:underline font-medium">{{ t('panel.verTodos') }}</RouterLink>
        </div>
        <p v-if="panel.eventos_proximos.length === 0" class="text-sm text-gray-400 py-4 text-center">{{ t('panel.eventos.vacio') }}</p>
        <ul v-else class="divide-y divide-gray-50">
          <li v-for="e in panel.eventos_proximos" :key="e.id" class="py-2 flex items-center justify-between gap-3">
            <div class="min-w-0">
              <RouterLink :to="`/eventos/${e.id}`" class="text-sm font-medium text-gray-900 hover:underline truncate block">{{ e.titulo }}</RouterLink>
              <p class="text-xs text-gray-500 truncate">{{ t(`eventos.tipo.${e.tipo}`) }}<span v-if="e.lugar"> · {{ e.lugar }}</span></p>
            </div>
            <p class="text-xs text-gray-600 whitespace-nowrap">
              {{ formatoFecha(new Date(e.inicia_en), { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) }}
            </p>
          </li>
        </ul>
      </div>

      <!-- Cumpleaños -->
      <div v-if="auth.can('miembros.ver')" class="card">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2 mb-3">
          <Cake class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('panel.cumpleanos.titulo') }}
        </h2>
        <p v-if="panel.cumpleanos.length === 0" class="text-sm text-gray-400 py-4 text-center">{{ t('panel.cumpleanos.vacio') }}</p>
        <ul v-else class="divide-y divide-gray-50">
          <li v-for="(c, i) in panel.cumpleanos" :key="i" class="py-2 flex items-center justify-between gap-3">
            <p class="text-sm text-gray-900 truncate">{{ c.nombre }} {{ c.apellido }}</p>
            <p class="text-xs text-gray-600 whitespace-nowrap">
              {{ c.en_dias === 0 ? t('panel.cumpleanos.hoy') : t('panel.cumpleanos.enDias', { n: c.en_dias }) }}
            </p>
          </li>
        </ul>
      </div>

      <!-- Formación -->
      <div v-if="auth.can('formacion.ver')" class="card">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2">
            <GraduationCap class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('panel.formacion.titulo') }}
          </h2>
          <RouterLink to="/formacion" class="text-sm text-adn-verde hover:underline font-medium">{{ t('panel.verTodos') }}</RouterLink>
        </div>
        <dl class="grid grid-cols-3 gap-2 text-center">
          <div><dd class="text-xl font-bold text-gray-900">{{ panel.formacion.en_curso }}</dd><dt class="text-xs text-gray-500">{{ t('panel.formacion.enCurso') }}</dt></div>
          <div><dd class="text-xl font-bold text-gray-900">{{ panel.formacion.completadas_mes }}</dd><dt class="text-xs text-gray-500">{{ t('panel.formacion.completadas') }}</dt></div>
          <div><dd class="text-xl font-bold text-gray-900">{{ panel.formacion.certificados_mes }}</dd><dt class="text-xs text-gray-500">{{ t('panel.formacion.certificados') }}</dt></div>
        </dl>
      </div>

      <!-- Comunicación -->
      <div v-if="auth.can('comunicacion.ver')" class="card">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2">
            <MessageSquare class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('panel.comunicacion.titulo') }}
          </h2>
          <RouterLink to="/comunicacion" class="text-sm text-adn-verde hover:underline font-medium">{{ t('panel.verTodos') }}</RouterLink>
        </div>
        <dl class="grid grid-cols-2 gap-2 text-center">
          <div><dd class="text-xl font-bold text-gray-900">{{ panel.comunicacion.mensajes_30d }}</dd><dt class="text-xs text-gray-500">{{ t('panel.comunicacion.mensajes') }}</dt></div>
          <div><dd class="text-xl font-bold text-gray-900">{{ panel.comunicacion.enviados_30d }}</dd><dt class="text-xs text-gray-500">{{ t('panel.comunicacion.enviados') }}</dt></div>
        </dl>
        <p class="text-xs text-gray-400 mt-2">{{ t('panel.comunicacion.nota') }}</p>
      </div>
    </div>

    <!-- Alertas 72h -->
    <div class="card">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><HeartHandshake class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('panel.consolidacion') }}</h2>
        <RouterLink to="/consolidacion" class="text-sm text-adn-verde hover:underline font-medium">
          {{ t('panel.verTodas') }}
        </RouterLink>
      </div>

      <div v-if="consolidaciones.length === 0" class="text-center py-8 text-gray-400">
        <CircleCheck class="w-10 h-10 mx-auto mb-2 text-emerald-500" aria-hidden="true" />
        <p>{{ t('panel.sinAlertas') }}</p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="c in consolidaciones"
          :key="c.id"
          :class="['flex items-center justify-between p-3 rounded-lg border', claseAlerta(c.estado_alerta)]"
        >
          <div class="flex items-center gap-3">
            <div>
              <p class="font-medium text-sm">{{ c.miembros?.nombre }} {{ c.miembros?.apellido }}</p>
              <p class="text-xs opacity-75">{{ t('panel.horasDesde', { horas: horasTranscurridas(c.fecha_conversion) }) }}</p>
            </div>
          </div>
          <EstadoAlerta :estado="c.estado_alerta" />
        </div>
      </div>
    </div>

    <!-- Miembros recientes -->
    <div class="card">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><UserPlus class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('panel.nuevosMiembros') }}</h2>
        <RouterLink to="/miembros" class="text-sm text-adn-verde hover:underline font-medium">
          {{ t('panel.verTodos') }}
        </RouterLink>
      </div>

      <div v-if="miembrosRecientes.length === 0" class="text-center py-8 text-gray-400">
        <p>{{ t('panel.sinMiembros') }}</p>
      </div>

      <div v-else class="divide-y divide-gray-50">
        <div
          v-for="m in miembrosRecientes"
          :key="m.id"
          class="flex items-center justify-between py-3"
        >
          <div class="flex items-center gap-3">
            <div class="w-9 h-9 bg-adn-verde rounded-full flex items-center justify-center flex-shrink-0">
              <span class="text-white text-sm font-bold">{{ m.nombre[0] }}</span>
            </div>
            <div>
              <p class="font-medium text-sm text-gray-900">{{ m.nombre }} {{ m.apellido }}</p>
              <p class="text-xs text-gray-400">{{ m.crm_id }}</p>
            </div>
          </div>
          <span class="text-xs bg-gray-100 text-gray-600 px-2 py-1 rounded-full">
            {{ etiquetaCompromiso(m.nivel_compromiso) }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { formatoFecha } from '@/i18n'
import { supabase } from '@/lib/supabase'
import { conAlerta, haceHoras } from '@/lib/alertas'
import {
  Users, House, HeartHandshake, Siren, CircleCheck, UserPlus,
  CalendarCheck, CalendarDays, TrendingUp, Cake, GraduationCap, MessageSquare,
} from '@lucide/vue'
import EstadoAlerta from '@/components/EstadoAlerta.vue'
import BotonesDar from '@/components/BotonesDar.vue'
import { useAuthStore } from '@/stores/auth'
import { ETIQUETAS_COMPROMISO } from '@/lib/supabase'
import type { AlertaColor, NivelCompromiso } from '@/lib/supabase'

const auth = useAuthStore()
const { t } = useI18n()

// Sigue al idioma elegido
const fechaHoy = computed(() => formatoFecha(new Date(), {
  weekday: 'long', day: 'numeric', month: 'long'
}))

function etiquetaCompromiso(nivel: string) {
  const clave = ETIQUETAS_COMPROMISO[nivel as NivelCompromiso]
  return clave ? t(clave) : nivel
}

const stats = ref({ totalMiembros: 0, totalCasas: 0, consolidacionesActivas: 0, alertasCriticas: 0 })
const consolidaciones = ref<any[]>([])
const miembrosRecientes = ref<any[]>([])

function claseAlerta(alerta: AlertaColor) {
  const clases: Record<AlertaColor, string> = {
    verde: 'alerta-verde', amarillo: 'alerta-amarillo',
    naranja: 'alerta-naranja', rojo: 'alerta-rojo',
  }
  return clases[alerta] ?? ''
}

function horasTranscurridas(fecha: string) {
  return Math.floor((Date.now() - new Date(fecha).getTime()) / 3600000)
}

interface PanelInicio {
  miembros: { activos: number; nuevos_30d: number; nuevos_30d_previos: number; sin_casa: number; bautizados: number }
  asistencia: {
    semana_actual: { semana: string; registros: number; presentes: number }
    semana_anterior: { semana: string; registros: number; presentes: number }
    serie: { semana: string; presentes: number }[]
  }
  eventos_proximos: { id: string; titulo: string; tipo: string; inicia_en: string; lugar: string | null }[]
  cumpleanos: { nombre: string; apellido: string | null; fecha: string; en_dias: number }[]
  formacion: { en_curso: number; completadas_mes: number; certificados_mes: number }
  comunicacion: { mensajes_30d: number; enviados_30d: number }
  crecimiento: { mes: string; nuevos: number }[]
}

const panel = ref<PanelInicio | null>(null)
const errorPanel = ref('')

const maxAsistencia = computed(() => Math.max(1, ...(panel.value?.asistencia.serie.map(s => s.presentes) ?? [1])))
const maxCrecimiento = computed(() => Math.max(1, ...(panel.value?.crecimiento.map(c => c.nuevos) ?? [1])))

// Altura de barra en porcentaje; una barra a cero queda como una línea fina, visible
function altura(valor: number, maximo: number) {
  return valor <= 0 ? '2px' : `${Math.max(4, Math.round((valor / maximo) * 100))}%`
}

// Texto de la variación frente al periodo anterior; sin base de comparación no se inventa un porcentaje
function variacion(actual: number, previo: number) {
  if (previo === 0) return actual === 0 ? t('panel.variacion.igual') : t('panel.variacion.sinBase')
  const pct = Math.round(((actual - previo) / previo) * 100)
  if (pct === 0) return t('panel.variacion.igual')
  return t(pct > 0 ? 'panel.variacion.sube' : 'panel.variacion.baja', { n: Math.abs(pct) })
}

const superadmins = ref<number | null>(null)
const faltaSegundoSuper = computed(() => auth.can('usuarios.gestionar') && superadmins.value !== null && superadmins.value < 2)

onMounted(async () => {
  supabase.rpc('adn_panel_inicio').then(({ data, error }) => {
    if (error) { errorPanel.value = t('panel.errorPanel'); return }
    panel.value = data as PanelInicio
  })
  supabase.from('perfiles').select('*', { count: 'exact', head: true }).eq('rol', 'propietario').eq('activo', true)
    .then(({ count }) => { superadmins.value = count ?? null })
  const [miembrosRes, casasRes, consolRes, recientesRes] = await Promise.all([
    supabase.from('miembros').select('*', { count: 'exact', head: true }).eq('activo', true),
    supabase.from('casas_oracion').select('*', { count: 'exact', head: true }).eq('activa', true),
    supabase.from('consolidaciones').select('*', { count: 'exact', head: true }).eq('completado', false),
    supabase.from('consolidaciones')
      .select('*, miembros(nombre, apellido)')
      .lt('fecha_conversion', haceHoras(48))
      .eq('completado', false)
      .order('fecha_conversion', { ascending: true })
      .limit(5),
  ])

  stats.value.totalMiembros = miembrosRes.count ?? 0
  stats.value.totalCasas = casasRes.count ?? 0
  stats.value.consolidacionesActivas = consolRes.count ?? 0
  consolidaciones.value = (recientesRes.data ?? []).map(conAlerta)
  stats.value.alertasCriticas = consolidaciones.value.filter(c => c.estado_alerta === 'rojo').length

  const { data: recientes } = await supabase
    .from('miembros')
    .select('id, nombre, apellido, crm_id, nivel_compromiso')
    .eq('activo', true)
    .order('created_at', { ascending: false })
    .limit(5)

  miembrosRecientes.value = recientes ?? []
})
</script>
