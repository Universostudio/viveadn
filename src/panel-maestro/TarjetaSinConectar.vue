<template>
  <section class="card" :aria-labelledby="idTitulo" data-test="sin-conectar">
    <div class="flex items-start gap-3">
      <Unplug class="w-5 h-5 text-gray-400 mt-0.5 flex-shrink-0" aria-hidden="true" />
      <div>
        <h2 :id="idTitulo" class="text-base font-semibold text-gray-900">{{ titulo }}</h2>
        <p class="mt-1 inline-block text-xs font-medium bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full">{{ t('panelMaestro.sinConectar') }}</p>
        <p class="text-sm text-gray-600 mt-2">{{ falta }}</p>
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
import { Unplug } from '@lucide/vue'
import { useI18n } from 'vue-i18n'

const props = defineProps<{ titulo: string; falta: string; id?: string }>()
const { t } = useI18n()
const idTitulo = `sc-${props.id ?? props.titulo.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`
</script>
