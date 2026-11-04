<template>
  <div class="min-h-screen bg-gradient-to-br from-adn-verde to-adn-oscuro flex items-center justify-center p-4">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-8">
      <div class="text-center mb-6">
        <div class="w-16 h-16 bg-adn-verde rounded-2xl flex items-center justify-center mx-auto mb-4">
          <HandHeart class="w-8 h-8 text-white" aria-hidden="true" />
        </div>
        <h1 class="text-2xl font-bold text-adn-verde">{{ t('dar.titulo') }}</h1>
        <p v-if="estado === 'lista'" class="text-gray-900 font-semibold mt-1">{{ iglesia }}</p>
      </div>

      <p v-if="estado === 'cargando'" class="text-center text-gray-500 text-sm">{{ t('comun.cargando') }}</p>

      <div v-else-if="estado === 'noDisponible'" class="text-center space-y-3">
        <TriangleAlert class="w-10 h-10 mx-auto text-amber-500" aria-hidden="true" />
        <p class="text-gray-700 font-medium">{{ t('dar.paginaNoDisponible') }}</p>
      </div>

      <div v-else class="space-y-4">
        <p class="text-sm text-gray-500 text-center">{{ t('dar.paginaDescripcion', { iglesia }) }}</p>
        <a
          v-for="e in enlaces"
          :key="e.tipo"
          :href="e.url"
          target="_blank"
          rel="noopener noreferrer"
          class="w-full btn-primary py-3 text-base inline-flex items-center justify-center gap-2"
        >
          {{ t(`dar.${e.tipo}`) }} <ExternalLink class="w-4 h-4" aria-hidden="true" />
          <span class="sr-only">{{ t('dar.seAbreEnOtraPagina') }}</span>
        </a>
        <p class="text-xs text-gray-400 text-center">{{ t('dar.paginaAviso') }}</p>
      </div>

      <SelectorIdioma id="selector-idioma-dar" class="mt-6 max-w-xs mx-auto" />
      <p class="text-center text-xs text-gray-400 mt-6">© 2026 ViveADN</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { HandHeart, ExternalLink, TriangleAlert } from '@lucide/vue'
import SelectorIdioma from '@/components/SelectorIdioma.vue'
import { supabase } from '@/lib/supabase'
import { TIPOS_DAR, urlDarValida } from '@/lib/dar'
import type { TipoDar } from '@/lib/dar'

const route = useRoute()
const { t } = useI18n()
const estado = ref<'cargando' | 'lista' | 'noDisponible'>('cargando')
const iglesia = ref('')
const enlaces = ref<{ tipo: TipoDar; url: string }[]>([])

onMounted(async () => {
  const slug = String(route.params.slug ?? '')
  const { data, error } = await supabase.functions.invoke('dar-publico', { body: { slug } })
  const lista = ((data?.enlaces ?? []) as { tipo: TipoDar; url: string }[]).filter(e => urlDarValida(e.url))
  if (error || !data?.iglesia || !lista.length) { estado.value = 'noDisponible'; return }
  iglesia.value = data.iglesia
  enlaces.value = TIPOS_DAR.flatMap(tipo => lista.filter(e => e.tipo === tipo))
  estado.value = 'lista'
})
</script>
