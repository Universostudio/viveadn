<template>
  <label v-if="pm.hayDemos" class="inline-flex items-center gap-2 text-sm text-gray-700 cursor-pointer" data-test="interruptor-demo">
    <input type="checkbox" role="switch" class="rounded accent-adn-verde" :checked="pm.incluirDemo" data-test="incluir-demo" @change="pm.fijarIncluirDemo(($event.target as HTMLInputElement).checked)" />
    <span>{{ t('plataformaPanel.demo.incluir') }}</span>
    <span class="text-xs text-gray-500" data-test="demo-nota">{{ pm.incluirDemo ? t('plataformaPanel.demo.dentro', { n: pm.totalDemos }, pm.totalDemos) : t('plataformaPanel.demo.fuera', { n: pm.totalDemos }, pm.totalDemos) }}</span>
  </label>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { usePlataformaStore } from '@/stores/plataforma'
const { t } = useI18n()
const pm = usePlataformaStore()
</script>
