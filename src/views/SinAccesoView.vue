<template>
  <div class="p-4 sm:p-6 max-w-xl mx-auto">
    <div class="card text-center space-y-4 py-10" role="alert" data-test="sin-acceso">
      <ShieldAlert class="w-10 h-10 mx-auto text-amber-600" aria-hidden="true" />
      <h1 class="text-xl font-bold text-gray-900">{{ t('sinAcceso.titulo') }}</h1>
      <p class="text-sm text-gray-600">{{ t('sinAcceso.texto', { rol: auth.nombreRol }) }}</p>
      <p v-if="desde" class="text-xs text-gray-500">{{ t('sinAcceso.intentaste', { ruta: desde }) }}</p>
      <div class="flex flex-wrap justify-center gap-3 pt-2">
        <RouterLink :to="{ name: auth.aterrizaje }" class="btn-primary" data-test="sin-acceso-inicio">{{ t('sinAcceso.volver') }}</RouterLink>
      </div>
      <p class="text-xs text-gray-500">{{ t('sinAcceso.pedir') }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { ShieldAlert } from '@lucide/vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
const route = useRoute()
// Solo se muestra la ruta si es una ruta interna de la aplicación (nunca un enlace externo escrito en la dirección)
const desde = computed(() => { const d = route.query.desde; return typeof d === 'string' && /^\/[A-Za-z0-9/_-]*$/.test(d) ? d : '' })
</script>
