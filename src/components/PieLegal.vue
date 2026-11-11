<template>
  <nav :aria-label="t('legal.pie')" class="flex flex-wrap items-center justify-center gap-x-3 gap-y-1 text-xs" :class="claro ? 'text-white/60' : 'text-gray-400'">
    <span>© 2026 Vive ADN</span>
    <RouterLink v-for="d in CLAVES_LEGALES" :key="d" :to="RUTAS_LEGALES[d]" class="underline underline-offset-2" :class="claro ? 'hover:text-adn-oro' : 'hover:text-adn-verde'">{{ t(`legal.${d}`) }}</RouterLink>
    <a v-if="CONFIG_LEGAL.emailSoporte" :href="`mailto:${CONFIG_LEGAL.emailSoporte}`" class="underline underline-offset-2" :class="claro ? 'hover:text-adn-oro' : 'hover:text-adn-verde'">{{ t('legal.soporte') }}</a>
  </nav>
</template>

<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { CLAVES_LEGALES, RUTAS_LEGALES } from '@/legal/tipos'
import { CONFIG_LEGAL } from '@/lib/legalConfig'

defineProps<{ claro?: boolean }>()
const { t } = useI18n()
</script>
