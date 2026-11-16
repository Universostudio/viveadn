<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.sistema.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('plataformaPanel.sistema.subtitulo') }}</p>
    </div>

    <section class="card space-y-3" :aria-label="t('plataforma.purga.titulo')" data-test="purga-estado">
      <div class="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h2 class="text-base font-semibold text-gray-900">{{ t('plataforma.purga.titulo') }}</h2>
          <p class="text-sm text-gray-500 mt-0.5">{{ t('plataforma.purga.ayuda') }}</p>
        </div>
        <button type="button" @click="pm.cargarPurga()" class="btn-secondary text-sm">{{ t('plataforma.purga.reintentar') }}</button>
      </div>
      <p v-if="!pm.purga" role="status" class="text-sm px-4 py-3 rounded-lg border bg-amber-50 text-amber-800 border-amber-200">{{ t('plataforma.purga.noDisponible') }}</p>
      <template v-else>
        <p role="status" :class="['text-sm px-4 py-3 rounded-lg border font-medium', pm.purga.atrasada ? 'bg-red-50 text-red-700 border-red-200' : 'bg-green-50 text-green-700 border-green-200']">
          {{ pm.purga.atrasada ? t('plataforma.purga.atrasada') : t('plataforma.purga.sana') }}
        </p>
        <dl class="grid grid-cols-3 gap-3 text-center">
          <div><dd class="text-2xl font-bold text-gray-900">{{ pm.purga.en_borrado }}</dd><dt class="text-xs text-gray-500">{{ t('plataforma.purga.enBorrado') }}</dt></div>
          <div><dd class="text-2xl font-bold text-gray-900">{{ pm.purga.vencidas }}</dd><dt class="text-xs text-gray-500">{{ t('plataforma.purga.vencidas') }}</dt></div>
          <div><dd class="text-2xl font-bold text-gray-900">{{ pm.purga.horas_mas_atrasada }}</dd><dt class="text-xs text-gray-500">{{ t('plataforma.purga.horas') }}</dt></div>
        </dl>
      </template>
    </section>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { usePlataformaStore } from '@/stores/plataforma'

const { t } = useI18n()
const pm = usePlataformaStore()
onMounted(() => { void pm.asegurarCargada() })
</script>
