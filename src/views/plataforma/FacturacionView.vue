<template>
  <div class="space-y-6">
    <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.menu.facturacion') }}</h1>
    <TarjetaSinConectar id="facturacion" :titulo="t('plataformaPanel.facturacion.titulo')" :falta="t('plataformaPanel.faltaFacturacion')" />
  </div>
</template>
<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import TarjetaSinConectar from '@/panel-maestro/TarjetaSinConectar.vue'
const { t } = useI18n()
</script>
