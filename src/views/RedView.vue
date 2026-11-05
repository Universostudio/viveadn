<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('red.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('red.subtitulo', { iglesia: auth.nombreIglesia }) }}</p>
    </div>

    <p v-if="error" role="alert" class="text-sm px-4 py-3 rounded-lg border bg-red-50 text-red-700 border-red-200">{{ t(error) }}</p>
    <div v-else-if="cargando" class="py-12 text-center text-gray-400 text-sm" role="status">{{ t('comun.cargando') }}</div>
    <p v-else-if="!datos?.sedes.length" class="text-sm text-gray-500 py-8 text-center">{{ t('red.sinSedes') }}</p>

    <template v-else-if="datos">
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <div v-for="k in tarjetas" :key="k.clave" :class="['card-stat', k.clave === 'alertas' && datos.totales && datos.totales.alertas > 0 ? 'border-l-4 border-red-400' : '']">
          <div class="w-11 h-11 rounded-xl flex items-center justify-center flex-shrink-0" :class="k.fondo"><component :is="k.icono" class="w-5 h-5" :class="k.color" aria-hidden="true" /></div>
          <div>
            <p class="text-2xl font-bold" :class="k.clave === 'alertas' && k.valor > 0 ? 'text-red-600' : 'text-gray-900'">{{ k.valor.toLocaleString(locale) }}</p>
            <p class="text-xs text-gray-500">{{ t(`red.${k.clave}`) }}</p>
          </div>
        </div>
      </div>
      <p class="text-xs text-gray-400 -mt-2">{{ t('red.totalesNota') }}</p>

      <div class="card overflow-x-auto p-0">
        <table class="w-full text-sm">
          <thead class="text-left text-xs text-gray-500 border-b border-gray-100">
            <tr>
              <th scope="col" class="px-4 py-3 font-medium">{{ t('red.iglesia') }}</th>
              <th scope="col" class="px-4 py-3 font-medium text-right">{{ t('red.miembros') }}</th>
              <th scope="col" class="px-4 py-3 font-medium text-right">{{ t('red.casas') }}</th>
              <th scope="col" class="px-4 py-3 font-medium text-right">{{ t('red.consolidacion') }}</th>
              <th scope="col" class="px-4 py-3 font-medium text-right">{{ t('red.alertas') }}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-50">
            <tr class="bg-adn-arena/40">
              <th scope="row" class="px-4 py-3 text-left font-semibold text-gray-900">{{ auth.nombreIglesia }} <span class="text-xs font-normal text-gray-400">· {{ t('red.estaIglesia') }}</span></th>
              <td class="px-4 py-3 text-right">{{ datos.propia?.miembros ?? 0 }}</td>
              <td class="px-4 py-3 text-right">{{ datos.propia?.casas ?? 0 }}</td>
              <td class="px-4 py-3 text-right">{{ datos.propia?.consolidaciones ?? 0 }}</td>
              <td class="px-4 py-3 text-right" :class="(datos.propia?.alertas ?? 0) > 0 ? 'text-red-600 font-semibold' : ''">{{ datos.propia?.alertas ?? 0 }}</td>
            </tr>
            <tr v-for="s in datos.sedes" :key="s.id">
              <th scope="row" class="px-4 py-3 text-left font-medium text-gray-900">
                {{ s.nombre }}
                <span class="block text-xs font-normal text-gray-400">{{ [s.ciudad, s.pais].filter(Boolean).join(', ') }}</span>
              </th>
              <template v-if="s.resumen">
                <td class="px-4 py-3 text-right">{{ s.resumen.miembros }}</td>
                <td class="px-4 py-3 text-right">{{ s.resumen.casas }}</td>
                <td class="px-4 py-3 text-right">{{ s.resumen.consolidaciones }}</td>
                <td class="px-4 py-3 text-right" :class="s.resumen.alertas > 0 ? 'text-red-600 font-semibold' : ''">{{ s.resumen.alertas }}</td>
              </template>
              <td v-else colspan="4" class="px-4 py-3 text-right text-xs text-gray-400">{{ t(!s.activa ? 'red.suspendida' : 'red.sinAcceso') }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { HeartHandshake, House, Siren, Users } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'

interface Cifras { miembros: number; casas: number; consolidaciones: number; alertas: number }
interface Sede { id: string; nombre: string; pais: string | null; ciudad: string | null; activa: boolean; acceso: string; resumen: Cifras | null }
interface Datos { sedes: Sede[]; propia: Cifras | null; totales: Cifras | null }

const { t, locale } = useI18n()
const auth = useAuthStore()
const cargando = ref(true)
const error = ref('')
const datos = ref<Datos | null>(null)

const tarjetas = computed(() => {
  const x = datos.value?.totales
  return [
    { clave: 'miembros', valor: x?.miembros ?? 0, icono: Users, fondo: 'bg-adn-verde/10', color: 'text-adn-verde' },
    { clave: 'casas', valor: x?.casas ?? 0, icono: House, fondo: 'bg-yellow-100', color: 'text-yellow-700' },
    { clave: 'consolidacion', valor: x?.consolidaciones ?? 0, icono: HeartHandshake, fondo: 'bg-green-100', color: 'text-green-700' },
    { clave: 'alertas', valor: x?.alertas ?? 0, icono: Siren, fondo: 'bg-red-100', color: 'text-red-600' },
  ]
})

onMounted(async () => {
  const { data, error: e } = await supabase.functions.invoke('red-resumen', { body: {} })
  if (e) error.value = 'red.errorCargar'
  else datos.value = data
  cargando.value = false
})
</script>
