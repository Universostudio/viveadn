<template>
  <section class="card" :aria-labelledby="idTitulo" data-test="salud">
    <h2 :id="idTitulo" class="text-base font-semibold text-gray-900">{{ titulo }}</h2>
    <ul class="mt-3 space-y-3">
      <li v-for="s in servicios" :key="s.clave" :data-servicio="s.clave" :data-situacion="s.situacion">
        <div class="flex items-center gap-3 text-sm">
          <span class="flex-1 min-w-0 text-gray-700">{{ s.etiqueta }}</span>
          <span :class="['text-xs font-medium px-2 py-0.5 rounded-full', clase[s.situacion]]">{{ t('panelMaestro.situacion.' + s.situacion) }}</span>
        </div>
        <div v-if="s.porcentaje !== undefined" class="mt-1 h-1.5 rounded-full bg-gray-100 overflow-hidden" role="presentation">
          <span :class="['block h-full', s.situacion === 'alerta' ? 'bg-red-500' : 'bg-adn-verde']" :style="{ width: Math.max(0, Math.min(100, s.porcentaje)) + '%' }"></span>
        </div>
        <p v-if="s.detalle" class="text-xs text-gray-500 mt-1">{{ s.detalle }}</p>
      </li>
    </ul>
  </section>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { EstadoServicio, SituacionServicio } from './tipos'

const props = defineProps<{ titulo: string; servicios: EstadoServicio[]; id?: string }>()
const { t } = useI18n()
const idTitulo = `ps-${props.id ?? 'salud'}`
// Texto y color juntos: el estado nunca depende solo del color
const clase: Record<SituacionServicio, string> = {
  ok: 'bg-green-100 text-green-800',
  alerta: 'bg-red-100 text-red-800',
  apagado: 'bg-gray-100 text-gray-700',
  sin_conectar: 'bg-gray-100 text-gray-600',
}
</script>
