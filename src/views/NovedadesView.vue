<template>
  <div class="p-4 sm:p-6 max-w-3xl mx-auto space-y-6" data-test="novedades">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('novedades.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('novedades.subtitulo') }}</p>
    </div>
    <p v-if="cargando" class="text-sm text-gray-400" role="status">{{ t('comun.cargando') }}</p>
    <p v-else-if="error" class="text-sm text-red-600" role="alert" data-test="novedades-error">{{ t('novedades.error') }}</p>
    <p v-else-if="!lista.length" class="card text-sm text-gray-500" data-test="novedades-vacio">{{ t('novedades.vacio') }}</p>
    <ol v-else class="space-y-4">
      <li v-for="n in lista" :key="n.id" class="card space-y-2" :data-novedad="n.id">
        <div class="flex items-center gap-2 flex-wrap">
          <h2 class="text-base font-semibold text-gray-900">{{ n.titulo }}</h2>
          <span class="text-xs bg-gray-100 text-gray-700 px-2 py-0.5 rounded-full">{{ t('novedades.version', { v: n.version }) }}</span>
          <span v-if="n.nueva" class="text-xs bg-adn-verde text-white px-2 py-0.5 rounded-full" data-test="novedad-nueva">{{ t('novedades.nueva') }}</span>
        </div>
        <p class="text-xs text-gray-500">{{ new Date(n.publicada_en).toLocaleDateString(locale) }}</p>
        <p class="text-sm text-gray-700 whitespace-pre-line">{{ n.texto }}</p>
      </li>
    </ol>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { supabase } from '@/lib/supabase'
import { useSoporteStore } from '@/stores/soporte'

const { t, locale } = useI18n()
const soporte = useSoporteStore()
const cargando = ref(true)
const error = ref(false)
const lista = ref<{ id: string; version: string; titulo: string; texto: string; publicada_en: string; nueva: boolean }[]>([])

onMounted(async () => {
  if (!(await soporte.asegurar())) { cargando.value = false; error.value = true; return }
  const [{ data: vista }, { data, error: e }] = await Promise.all([
    supabase.from('adn_novedades_vistas').select('vista_en').maybeSingle(),
    supabase.from('adn_novedades').select('id, version, titulo, texto, publicada_en').order('publicada_en', { ascending: false }).limit(50),
  ])
  cargando.value = false
  if (e) { error.value = true; return }
  const desde = vista?.vista_en ? new Date(vista.vista_en).getTime() : 0
  lista.value = (data ?? []).map((n: any) => ({ ...n, nueva: new Date(n.publicada_en).getTime() > desde }))
  // Verlas las marca como vistas: el aviso de «novedades» del menú desaparece
  await soporte.marcarNovedadesVistas()
})
</script>
