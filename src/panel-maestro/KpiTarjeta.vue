<template>
  <div class="card" data-test="kpi" :data-kpi="kpi.clave">
    <p class="text-xs text-gray-500">{{ kpi.etiqueta }}</p>
    <template v-if="kpi.valor !== null">
      <p :class="['text-2xl font-bold mt-1', kpi.tono === 'alerta' ? 'text-red-700' : 'text-gray-900']">{{ kpi.valor }}</p>
      <p v-if="kpi.nota" :class="['text-xs mt-1', kpi.tono === 'alerta' ? 'text-red-700' : kpi.tono === 'bien' ? 'text-emerald-700' : 'text-gray-500']">{{ kpi.nota }}</p>
    </template>
    <template v-else>
      <p class="mt-1 inline-block text-xs font-medium bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full">{{ t('panelMaestro.sinConectar') }}</p>
      <p v-if="kpi.sinConectar" class="text-xs text-gray-500 mt-1">{{ kpi.sinConectar }}</p>
    </template>
  </div>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { Kpi } from './tipos'

defineProps<{ kpi: Kpi }>()
const { t } = useI18n()
</script>
