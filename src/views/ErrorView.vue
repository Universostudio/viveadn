<template>
  <main class="min-h-screen flex items-center justify-center bg-gray-50 px-6">
    <div class="max-w-md w-full text-center" role="alert">
      <h1 class="text-2xl font-semibold text-gray-900">{{ t('errorApp.titulo') }}</h1>
      <p class="mt-3 text-gray-600">{{ t(`errorApp.${tipo}`) }}</p>
      <div class="mt-6 flex flex-col sm:flex-row gap-3 justify-center">
        <button type="button" class="rounded-lg bg-adn-verde px-5 py-2.5 text-white font-medium" @click="recargar">{{ t('errorApp.reintentar') }}</button>
        <a href="/" class="rounded-lg border border-gray-300 px-5 py-2.5 text-gray-700 font-medium">{{ t('errorApp.irInicio') }}</a>
      </div>
    </div>
  </main>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { TipoError } from '@/lib/errorApp'

defineProps<{ tipo: TipoError }>()
const { t } = useI18n()
const recargar = () => window.location.reload()
</script>
