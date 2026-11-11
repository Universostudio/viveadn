<template>
  <div class="min-h-screen bg-gray-50">
    <header class="bg-adn-verde text-white">
      <div class="max-w-3xl mx-auto px-5 py-4 flex items-center justify-between gap-4">
        <RouterLink to="/" class="font-display font-bold">Vive ADN</RouterLink>
        <SelectorIdioma id="selector-idioma-legal" ocultar-etiqueta />
      </div>
    </header>

    <main class="max-w-3xl mx-auto px-5 py-8">
      <p v-if="cargando" role="status" class="text-gray-500">{{ t('comun.cargando') }}</p>
      <p v-else-if="falloCarga" role="alert" class="text-red-700">{{ t('legal.noDisponible') }}</p>
      <article v-else-if="doc">
        <h1 class="text-2xl font-bold text-gray-900">{{ doc.titulo }}</h1>
        <p class="mt-2 text-gray-600">{{ doc.resumen }}</p>
        <p class="mt-3 text-xs text-gray-500">{{ t('legal.version', { v: version.version }) }} · {{ t('legal.actualizado', { fecha: fechaLarga }) }}</p>

        <p v-if="faltan.length" role="alert" class="mt-4 rounded-lg border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          {{ t('legal.datosPendientes', { datos: faltan.join(', ') }) }}
        </p>

        <nav class="mt-6 rounded-lg bg-white border border-gray-200 px-4 py-3" :aria-label="t('legal.indice')">
          <p class="text-sm font-semibold text-gray-700">{{ t('legal.indice') }}</p>
          <ol class="mt-1 text-sm space-y-0.5">
            <li v-for="s in doc.secciones" :key="s.id"><a :href="`#${s.id}`" class="text-adn-verde hover:underline">{{ s.titulo }}</a></li>
          </ol>
        </nav>

        <section v-for="s in doc.secciones" :id="s.id" :key="s.id" class="mt-8 scroll-mt-4">
          <h2 class="text-lg font-semibold text-gray-900">{{ s.titulo }}</h2>
          <template v-for="(p, i) in visibles(s.parrafos)" :key="`p${i}`"><p class="mt-3 text-gray-700 leading-relaxed">{{ sustituir(textoDe(p)) }}</p></template>
          <ul v-if="s.lista?.length" class="mt-3 list-disc pl-6 space-y-2 text-gray-700 leading-relaxed">
            <li v-for="(it, i) in s.lista" :key="`l${i}`">{{ sustituir(it) }}</li>
          </ul>
          <template v-for="(p, i) in visibles(s.cierre ?? [])" :key="`c${i}`"><p class="mt-3 text-gray-700 leading-relaxed">{{ sustituir(textoDe(p)) }}</p></template>
        </section>

        <section class="mt-10 border-t border-gray-200 pt-4" aria-labelledby="historial">
          <h2 id="historial" class="text-sm font-semibold text-gray-700">{{ t('legal.historial') }}</h2>
          <ul class="mt-1 text-sm text-gray-600">
            <li v-for="v in [...versiones].reverse()" :key="v.version">{{ t('legal.version', { v: v.version }) }} · {{ fecha(v.fecha) }}</li>
          </ul>
        </section>
      </article>
    </main>

    <footer class="max-w-3xl mx-auto px-5 pb-10"><PieLegal /></footer>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import SelectorIdioma from '@/components/SelectorIdioma.vue'
import PieLegal from '@/components/PieLegal.vue'
import { cargarTextos, versionActual, versionesDe, type ClaveDocumento, type Documento, type Parrafo } from '@/legal'
import { CONFIG_LEGAL, pendientes, sustituir } from '@/lib/legalConfig'

const { t, locale } = useI18n()
const route = useRoute()
const clave = computed(() => route.meta.documentoLegal as ClaveDocumento)
const doc = ref<Documento | null>(null)
const cargando = ref(true)
const falloCarga = ref(false)

const version = computed(() => versionActual(clave.value))
const versiones = computed(() => versionesDe(clave.value))
const faltan = computed(() => pendientes())
const fecha = (iso: string) => new Intl.DateTimeFormat(locale.value, { dateStyle: 'long', timeZone: 'UTC' }).format(new Date(`${iso}T00:00:00Z`))
const fechaLarga = computed(() => fecha(version.value.fecha))

const textoDe = (p: Parrafo) => (typeof p === 'string' ? p : p.texto)
// Un párrafo condicionado a un dato (por ejemplo, el registro público) solo se muestra si el dato está configurado
const visibles = (ps: Parrafo[]) => ps.filter(p => typeof p === 'string' || CONFIG_LEGAL[p.si])

watch([locale, clave], async () => {
  cargando.value = true; falloCarga.value = false
  try { doc.value = (await cargarTextos(locale.value))[clave.value] ?? null; if (!doc.value) falloCarga.value = true }
  catch (e) { console.error('textos legales', e); falloCarga.value = true }
  finally { cargando.value = false }
  document.title = `${doc.value?.titulo ?? t('legal.privacidad')} · Vive ADN`
}, { immediate: true })
</script>
