<template>
  <div class="card space-y-4">
    <div>
      <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><FileDown class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('reportes.descargas.titulo') }}</h2>
      <p class="text-sm text-gray-500 mt-0.5">{{ t('reportes.descargas.descripcion') }}</p>
    </div>

    <p v-if="!tiposDisponibles.length" class="text-sm text-gray-500">{{ t('reportes.descargas.sinPermiso') }}</p>
    <div v-else class="grid grid-cols-1 sm:grid-cols-3 gap-3">
      <label class="text-sm text-gray-700 space-y-1">
        <span class="font-medium">{{ t('reportes.descargas.informe') }}</span>
        <select v-model="tipo" class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-adn-verde">
          <option v-for="x in tiposDisponibles" :key="x" :value="x">{{ t(`reportes.descargas.tipos.${x}`) }}</option>
        </select>
      </label>
      <label v-if="tipo === 'asistencia'" class="text-sm text-gray-700 space-y-1">
        <span class="font-medium">{{ t('reportes.descargas.semanas') }}</span>
        <select v-model.number="semanas" class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-adn-verde">
          <option v-for="n in [4, 8, 12, 26, 52]" :key="n" :value="n">{{ t('reportes.descargas.ultimasSemanas', n) }}</option>
        </select>
      </label>
      <label v-else-if="tipo === 'crecimiento'" class="text-sm text-gray-700 space-y-1">
        <span class="font-medium">{{ t('reportes.descargas.meses') }}</span>
        <select v-model.number="meses" class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-adn-verde">
          <option v-for="n in [6, 12, 24, 36]" :key="n" :value="n">{{ t('reportes.descargas.ultimosMeses', n) }}</option>
        </select>
      </label>
      <div v-else class="hidden sm:block"></div>
      <div class="flex items-end gap-2">
        <button @click="descargar('pdf')" :disabled="generando" class="btn-primary text-sm flex-1 inline-flex items-center justify-center gap-2 disabled:opacity-50">
          <FileText class="w-4 h-4" aria-hidden="true" /> PDF
        </button>
        <button @click="descargar('xlsx')" :disabled="generando" class="btn-secondary text-sm flex-1 inline-flex items-center justify-center gap-2 disabled:opacity-50">
          <FileSpreadsheet class="w-4 h-4" aria-hidden="true" /> Excel
        </button>
      </div>
    </div>

    <p v-if="generando" role="status" class="text-sm text-gray-500">{{ t('reportes.descargas.generando') }}</p>
    <p v-if="error" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(error) }}</p>
    <p v-if="listo" role="status" class="text-sm text-green-700">{{ t('reportes.descargas.listo', { archivo: listo }) }}</p>
    <p v-if="tipo === 'miembros'" class="text-xs text-gray-500">{{ t('reportes.descargas.avisoMiembros') }}</p>
    <p class="text-xs text-gray-400">{{ t('reportes.descargas.avisoPdf') }}</p>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { FileDown, FileText, FileSpreadsheet } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { crearPdf } from '@/lib/pdf'
import { crearXlsx } from '@/lib/xlsx'
import { informeMiembros, informeAsistencia, informeCrecimiento } from '@/lib/informes'
import { datosMiembros, datosAsistencia, datosCrecimiento, ErrorInforme } from '@/lib/informesDatos'

type Tipo = 'miembros' | 'asistencia' | 'crecimiento'
const { t, locale } = useI18n()
const auth = useAuthStore()

// El informe de miembros trae datos personales: pide el permiso de exportar; los otros, el de ver reportes
const tiposDisponibles = computed<Tipo[]>(() => [
  ...(auth.can('reportes.ver') ? (['asistencia', 'crecimiento'] as Tipo[]) : []),
  ...(auth.can('miembros.exportar') ? (['miembros'] as Tipo[]) : []),
])
const tipo = ref<Tipo>(tiposDisponibles.value[0] ?? 'asistencia')
watch(tiposDisponibles, v => { if (!v.includes(tipo.value)) tipo.value = v[0] ?? 'asistencia' })
const semanas = ref(12)
const meses = ref(12)
const generando = ref(false)
const error = ref('')
const listo = ref('')

const iso = (d: Date) => d.toISOString().slice(0, 10)

async function descargar(formato: 'pdf' | 'xlsx') {
  generando.value = true; error.value = ''; listo.value = ''
  try {
    const ahora = new Date()
    const ctx = { t: (k: string, p?: Record<string, unknown>) => t(k, p ?? {}) as string, locale: locale.value, iglesia: auth.nombreIglesia, ahora }
    let informe
    if (tipo.value === 'miembros') { const d = await datosMiembros(); informe = informeMiembros(d.resumen, d.filas, ctx) }
    else if (tipo.value === 'asistencia') {
      const hasta = iso(ahora); const desde = iso(new Date(ahora.getTime() - (semanas.value * 7 - 1) * 86_400_000))
      informe = informeAsistencia(await datosAsistencia(desde, hasta), ctx)
    } else informe = informeCrecimiento(await datosCrecimiento(meses.value), ctx)
    const bytes = formato === 'pdf' ? crearPdf(informe) : crearXlsx(informe)
    const slug = (auth.iglesia?.slug ?? 'iglesia').replace(/[^a-z0-9-]/gi, '')
    const nombre = `viveadn-${slug}-${tipo.value}-${iso(ahora)}.${formato}`
    const blob = new Blob([bytes as BlobPart], { type: formato === 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob); a.download = nombre; a.click()
    URL.revokeObjectURL(a.href)
    listo.value = nombre
  } catch (e) {
    error.value = e instanceof ErrorInforme ? e.clave : 'reportes.descargas.errorGenerico'
  } finally {
    generando.value = false
  }
}
</script>
