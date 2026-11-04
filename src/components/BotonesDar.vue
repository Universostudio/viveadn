<template>
  <div v-if="enlaces.length" class="card">
    <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2">
      <HandHeart class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('dar.titulo') }}
    </h2>
    <p class="text-sm text-gray-500 mt-0.5 mb-4">{{ t('dar.descripcion') }}</p>
    <div class="flex flex-wrap gap-3">
      <a
        v-for="e in enlaces"
        :key="e.tipo"
        :href="e.url"
        target="_blank"
        rel="noopener noreferrer"
        class="btn-primary inline-flex items-center gap-2"
      >
        {{ t(`dar.${e.tipo}`) }} <ExternalLink class="w-4 h-4" aria-hidden="true" />
        <span class="sr-only">{{ t('dar.seAbreEnOtraPagina') }}</span>
      </a>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { HandHeart, ExternalLink } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { TIPOS_DAR, urlDarValida } from '@/lib/dar'
import type { EnlaceDar } from '@/lib/dar'

const { t } = useI18n()
const enlaces = ref<EnlaceDar[]>([])

onMounted(async () => {
  const { data } = await supabase.from('enlaces_dar').select('tipo, url, activo').eq('activo', true)
  const lista = ((data ?? []) as EnlaceDar[]).filter(e => urlDarValida(e.url))
  enlaces.value = TIPOS_DAR.flatMap(tipo => lista.filter(e => e.tipo === tipo))
})
</script>
