<template>
  <div class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50" @click.self="cerrar" role="dialog" aria-modal="true" :aria-label="t('miembros.importar.titulo')">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-2xl p-6 max-h-[90vh] overflow-y-auto">
      <div class="flex items-start justify-between gap-3 mb-4">
        <h2 class="text-lg font-bold text-gray-900 flex items-center gap-2"><Upload class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('miembros.importar.titulo') }}</h2>
        <button @click="cerrar" class="text-gray-400 hover:text-gray-600" :aria-label="t('comun.cerrar')"><X class="w-5 h-5" aria-hidden="true" /></button>
      </div>

      <!-- Paso 1: elegir archivo -->
      <div v-if="paso === 'elegir'" class="space-y-4">
        <p class="text-sm text-gray-600">{{ t('miembros.importar.descripcion') }}</p>
        <ul class="text-sm text-gray-600 list-disc pl-5 space-y-1">
          <li>{{ t('miembros.importar.reglaObligatorias') }}</li>
          <li>{{ t('miembros.importar.reglaFechas') }}</li>
          <li>{{ t('miembros.importar.reglaRepetidos') }}</li>
          <li>{{ t('miembros.importar.reglaLimite', { n: MAX_FILAS }) }}</li>
        </ul>
        <div class="flex flex-col sm:flex-row gap-3">
          <button type="button" @click="descargarPlantilla" class="btn-secondary inline-flex items-center justify-center gap-2 text-sm">
            <Download class="w-4 h-4" aria-hidden="true" /> {{ t('miembros.importar.descargarPlantilla') }}
          </button>
          <label class="btn-primary inline-flex items-center justify-center gap-2 text-sm cursor-pointer">
            <FileSpreadsheet class="w-4 h-4" aria-hidden="true" /> {{ t('miembros.importar.elegirArchivo') }}
            <input type="file" accept=".csv,.txt,text/csv" class="sr-only" @change="leerArchivo" />
          </label>
        </div>
        <p v-if="errorArchivo" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(errorArchivo, { n: MAX_FILAS }) }}</p>
      </div>

      <!-- Paso 2: revisar -->
      <div v-else-if="paso === 'revisar'" class="space-y-4">
        <div class="grid grid-cols-3 gap-3 text-center">
          <div class="rounded-xl bg-green-50 p-3"><p class="text-2xl font-bold text-green-700">{{ listas.length }}</p><p class="text-xs text-green-800">{{ t('miembros.importar.listas') }}</p></div>
          <div class="rounded-xl bg-amber-50 p-3"><p class="text-2xl font-bold text-amber-700">{{ duplicadas.length }}</p><p class="text-xs text-amber-800">{{ t('miembros.importar.duplicadas') }}</p></div>
          <div class="rounded-xl bg-red-50 p-3"><p class="text-2xl font-bold text-red-700">{{ conErrores.length }}</p><p class="text-xs text-red-800">{{ t('miembros.importar.conErrores') }}</p></div>
        </div>
        <p v-if="ignoradas.length" class="text-xs text-gray-500">{{ t('miembros.importar.ignoradas', { columnas: ignoradas.join(', ') }) }}</p>

        <div v-if="conErrores.length" class="border border-gray-100 rounded-xl overflow-hidden">
          <p class="text-sm font-medium text-gray-700 px-4 py-2 bg-gray-50">{{ t('miembros.importar.revisaErrores') }}</p>
          <ul class="divide-y divide-gray-50 max-h-48 overflow-y-auto text-sm">
            <li v-for="f in conErrores.slice(0, 50)" :key="f.linea" class="px-4 py-2">
              <span class="font-medium text-gray-800">{{ t('miembros.importar.linea', { n: f.linea }) }}</span>
              <span class="text-gray-500"> · {{ f.datos.nombre }} {{ f.datos.apellido }}</span>
              <span class="block text-red-600 text-xs">{{ f.errores.map(e => t(`miembros.importar.error.${e}`)).join(' · ') }}</span>
            </li>
          </ul>
          <p v-if="conErrores.length > 50" class="text-xs text-gray-400 px-4 py-2">{{ t('miembros.importar.yMas', { n: conErrores.length - 50 }) }}</p>
        </div>

        <p v-if="errorImportar" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(errorImportar) }}</p>
        <div class="flex justify-between gap-3">
          <button @click="reiniciar" class="btn-secondary text-sm">{{ t('miembros.importar.otroArchivo') }}</button>
          <button @click="importar" :disabled="!listas.length" class="btn-primary text-sm disabled:opacity-50">{{ t('miembros.importar.importarN', { n: listas.length }) }}</button>
        </div>
      </div>

      <!-- Paso 3: importando -->
      <div v-else-if="paso === 'importando'" class="py-8 text-center space-y-3" role="status">
        <p class="text-gray-700 font-medium">{{ t('miembros.importar.importando') }}</p>
        <div class="w-full h-2 bg-gray-100 rounded-full overflow-hidden"><div class="h-2 bg-adn-verde transition-all" :style="{ width: `${progreso}%` }"></div></div>
        <p class="text-xs text-gray-400">{{ t('miembros.importar.noCierres') }}</p>
      </div>

      <!-- Paso 4: resultado -->
      <div v-else class="space-y-4 text-center py-4">
        <CircleCheck v-if="!errorImportar" class="w-12 h-12 mx-auto text-green-600" aria-hidden="true" />
        <TriangleAlert v-else class="w-12 h-12 mx-auto text-amber-500" aria-hidden="true" />
        <p class="text-gray-900 font-semibold">{{ t('miembros.importar.hecho', { n: importados }) }}</p>
        <p v-if="errorImportar" role="alert" class="text-sm text-red-700">{{ t(errorImportar) }}</p>
        <p v-if="omitidas" class="text-sm text-gray-500">{{ t('miembros.importar.omitidas', { n: omitidas }) }}</p>
        <button @click="cerrar" class="btn-primary text-sm">{{ t('comun.cerrar') }}</button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { Upload, X, Download, FileSpreadsheet, CircleCheck, TriangleAlert } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { analizarCsv, marcarDuplicados, claveMiembro, MAX_FILAS, MAX_BYTES, PLANTILLA_CSV } from '@/lib/importarMiembros'
import type { FilaImportar } from '@/lib/importarMiembros'

const emit = defineEmits<{ cerrar: []; importado: [] }>()
const { t } = useI18n()

const LOTE = 200
const paso = ref<'elegir' | 'revisar' | 'importando' | 'hecho'>('elegir')
const filas = ref<FilaImportar[]>([])
const ignoradas = ref<string[]>([])
const errorArchivo = ref('')
const errorImportar = ref('')
const progreso = ref(0)
const importados = ref(0)

const listas = computed(() => filas.value.filter(f => !f.errores.length && !f.duplicado))
const duplicadas = computed(() => filas.value.filter(f => !f.errores.length && f.duplicado))
const conErrores = computed(() => filas.value.filter(f => f.errores.length))
const omitidas = computed(() => duplicadas.value.length + conErrores.value.length)

function descargarPlantilla() {
  const url = URL.createObjectURL(new Blob([PLANTILLA_CSV], { type: 'text/csv;charset=utf-8' }))
  const a = document.createElement('a')
  a.href = url
  a.download = 'plantilla-miembros.csv'
  a.click()
  URL.revokeObjectURL(url)
}

// Excel en español suele guardar en Windows-1252; si no es UTF-8 válido se lee así
async function leerTexto(archivo: File): Promise<string> {
  const bytes = await archivo.arrayBuffer()
  try { return new TextDecoder('utf-8', { fatal: true }).decode(bytes) } catch { return new TextDecoder('windows-1252').decode(bytes) }
}

// Claves de los miembros que ya tiene la iglesia, para no duplicarlos
async function clavesExistentes(): Promise<Set<string> | null> {
  const claves = new Set<string>()
  for (let desde = 0; ; desde += 1000) {
    const { data, error } = await supabase.from('miembros').select('nombre, apellido, email').range(desde, desde + 999)
    if (error) return null
    for (const m of data ?? []) claves.add(claveMiembro({ nombre: m.nombre, apellido: m.apellido, email: m.email }))
    if ((data ?? []).length < 1000) return claves
  }
}

async function leerArchivo(ev: Event) {
  const input = ev.target as HTMLInputElement
  const archivo = input.files?.[0]
  input.value = ''
  errorArchivo.value = ''
  if (!archivo) return
  if (archivo.size > MAX_BYTES) { errorArchivo.value = 'miembros.importar.errorArchivo.grande'; return }
  let analisis
  try { analisis = analizarCsv(await leerTexto(archivo)) } catch { errorArchivo.value = 'miembros.importar.errorArchivo.lectura'; return }
  if (analisis.error) { errorArchivo.value = `miembros.importar.errorArchivo.${analisis.error}`; return }
  const existentes = await clavesExistentes()
  if (!existentes) { errorArchivo.value = 'miembros.importar.errorArchivo.lectura'; return }
  filas.value = marcarDuplicados(analisis.filas, existentes)
  ignoradas.value = analisis.ignoradas
  errorImportar.value = ''
  paso.value = 'revisar'
}

async function importar() {
  const lista = listas.value
  paso.value = 'importando'
  progreso.value = 0
  importados.value = 0
  errorImportar.value = ''
  for (let i = 0; i < lista.length; i += LOTE) {
    const lote = lista.slice(i, i + LOTE).map(f => ({ ...f.datos, activo: true }))
    const { error } = await supabase.from('miembros').insert(lote)
    if (error) { errorImportar.value = 'miembros.importar.errorImportar'; break }
    importados.value += lote.length
    progreso.value = Math.round((importados.value / lista.length) * 100)
  }
  paso.value = 'hecho'
  if (importados.value > 0) emit('importado')
}

function reiniciar() { paso.value = 'elegir'; filas.value = []; errorArchivo.value = ''; errorImportar.value = '' }
function cerrar() { if (paso.value !== 'importando') emit('cerrar') }
</script>
