<template>
  <div class="space-y-6">
    <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.menu.soporte') }}</h1>
    <TarjetaSinConectar id="tickets" :titulo="t('plataformaPanel.soporte.tickets')" :falta="t('plataformaPanel.soporte.faltaTickets')" />
    <TarjetaSinConectar id="cambios" :titulo="t('plataformaPanel.soporte.cambios')" :falta="t('plataformaPanel.soporte.faltaCambios')" />
  </div>
</template>
<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import TarjetaSinConectar from '@/panel-maestro/TarjetaSinConectar.vue'
const { t } = useI18n()
</script>
