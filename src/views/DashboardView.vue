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
import { Users, House, HeartHandshake, Siren, CircleCheck, UserPlus } from '@lucide/vue'
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

const superadmins = ref<number | null>(null)
const faltaSegundoSuper = computed(() => auth.can('usuarios.gestionar') && superadmins.value !== null && superadmins.value < 2)

onMounted(async () => {
  supabase.from('perfiles').select('*', { count: 'exact', head: true }).eq('rol', 'propietario').eq('activo', true)
    .then(({ count }) => { superadmins.value = count ?? null })
  const [miembrosRes, casasRes, consolRes, recientesRes] = await Promise.all([
    supabase.from('miembros').select('*', { count: 'exact', head: true }).eq('activo', true),
    supabase.from('casas_oracion').select('*', { count: 'exact', head: true }).eq('activa', true),
    supabase.from('consolidaciones').select('*', { count: 'exact', head: true }).eq('completado', false),
    supabase.from('consolidaciones')
      .select('*, miembros(nombre, apellido)')
      .in('estado_alerta', ['naranja', 'rojo'])
      .eq('completado', false)
      .order('fecha_conversion', { ascending: true })
      .limit(5),
  ])

  stats.value.totalMiembros = miembrosRes.count ?? 0
  stats.value.totalCasas = casasRes.count ?? 0
  stats.value.consolidacionesActivas = consolRes.count ?? 0
  consolidaciones.value = recientesRes.data ?? []
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
