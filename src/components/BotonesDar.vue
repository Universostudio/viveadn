<template>
  <div v-if="fondos.length" class="card">
    <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2">
      <HandHeart class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('dar.titulo') }}
    </h2>
    <p class="text-sm text-gray-500 mt-0.5 mb-4">{{ t('dar.descripcion') }}</p>
    <div class="flex flex-wrap gap-3">
      <a
        v-for="f in fondos"
        :key="f.tipo"
        :href="f.url"
        target="_blank"
        rel="noopener noreferrer"
        class="btn-primary inline-flex items-center gap-2"
      >
        {{ nombreDe(f) }} <ExternalLink class="w-4 h-4" aria-hidden="true" />
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

const { t } = useI18n()
const fondos = ref<{ tipo: string; url: string; nombre: string | null }[]>([])

// Los tres tipos originales se traducen si no tienen nombre propio
const nombreDe = (f: { tipo: string; nombre: string | null }) =>
  f.nombre || ((TIPOS_DAR as readonly string[]).includes(f.tipo) ? t(`dar.${f.tipo}`) : f.tipo)

onMounted(async () => {
  const { data } = await supabase.from('enlaces_dar').select('tipo, url, nombre, orden').eq('activo', true).order('orden').order('tipo')
  fondos.value = (data ?? []).filter(f => urlDarValida(f.url))
})
</script>
