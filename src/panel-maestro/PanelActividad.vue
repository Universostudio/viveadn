<template>
  <section class="card" :aria-labelledby="idTitulo" data-test="actividad">
    <h2 :id="idTitulo" class="text-base font-semibold text-gray-900">{{ titulo }}</h2>
    <p v-if="!eventos.length" class="text-sm text-gray-500 mt-3">{{ vacio ?? t('panelMaestro.actividadVacia') }}</p>
    <ul v-else class="mt-3 divide-y divide-gray-50">
      <li v-for="e in eventos" :key="e.id" class="py-2 flex items-start gap-3 text-sm">
        <span :class="['mt-1.5 w-2 h-2 rounded-full flex-shrink-0', e.tono === 'alerta' ? 'bg-red-500' : 'bg-adn-verde']" aria-hidden="true"></span>
        <span class="flex-1 min-w-0 text-gray-700">{{ e.texto }}</span>
        <time :datetime="e.fecha" class="text-xs text-gray-500 flex-shrink-0">{{ formato(e.fecha) }}</time>
      </li>
    </ul>
  </section>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { EventoActividad } from './tipos'

const props = defineProps<{ titulo: string; eventos: EventoActividad[]; vacio?: string; id?: string }>()
const { t, locale } = useI18n()
const idTitulo = `pa-${props.id ?? 'actividad'}`
const formato = (iso: string) => new Date(iso).toLocaleString(locale.value, { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
</script>
