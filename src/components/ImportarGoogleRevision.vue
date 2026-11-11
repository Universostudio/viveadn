<template>
  <!-- Revisión e importación de un archivo de contactos de Google -->
  <div v-if="paso === 'cargando'" class="py-8 text-center space-y-3" role="status">
    <p class="text-gray-700 font-medium">{{ t('miembros.importar.google.comprobando') }}</p>
  </div>

  <div v-else-if="paso === 'revisar'" class="space-y-4">
    <p class="text-sm text-gray-600">{{ t(r.formato === 'wix' ? 'miembros.importar.google.detectadoWix' : 'miembros.importar.google.detectado') }}</p>
    <div class="grid grid-cols-3 gap-3 text-center">
      <div class="rounded-xl bg-green-50 p-3"><p class="text-2xl font-bold text-green-700">{{ nuevas.length }}</p><p class="text-xs text-green-800">{{ t('miembros.importar.google.nuevos') }}</p></div>
      <div class="rounded-xl bg-amber-50 p-3"><p class="text-2xl font-bold text-amber-700">{{ yaExisten.length }}</p><p class="text-xs text-amber-800">{{ t('miembros.importar.duplicadas') }}</p></div>
      <div class="rounded-xl bg-gray-50 p-3"><p class="text-2xl font-bold text-gray-700">{{ sinNombreTotal }}</p><p class="text-xs text-gray-600">{{ t('miembros.importar.google.sinNombre') }}</p></div>
    </div>

    <label v-if="sinNombreTotal" class="flex items-start gap-2 text-sm text-gray-700 bg-gray-50 rounded-xl p-3 cursor-pointer">
      <input type="checkbox" v-model="incluirSinNombre" class="mt-0.5" />
      <span>
        {{ t('miembros.importar.google.incluirSinNombre') }}
        <span class="block text-xs text-gray-500">{{ t('miembros.importar.google.sinNombreAyuda', { n: sinNombreTotal }) }}</span>
      </span>
    </label>

    <div class="border border-gray-100 rounded-xl overflow-hidden">
      <p class="text-sm font-medium text-gray-700 px-4 py-2 bg-gray-50">{{ t('miembros.importar.google.resumen') }}</p>
      <ul class="text-sm text-gray-600 px-4 py-3 space-y-1 list-disc pl-8">
        <li>{{ t('miembros.importar.google.filasLeidas', { n: r.filas, p: r.personas }) }}</li>
        <li v-if="r.fusionadas">{{ t('miembros.importar.google.fusionadas', { n: r.fusionadas }) }}</li>
        <li v-if="r.descartadasVacias">{{ t('miembros.importar.google.vacias', { n: r.descartadasVacias }) }}</li>
        <li v-if="r.telefonosInvalidos">{{ t('miembros.importar.google.telefonosInvalidos', { n: r.telefonosInvalidos }) }}</li>
        <li v-if="r.correosInvalidos">{{ t('miembros.importar.google.correosInvalidos', { n: r.correosInvalidos }) }}</li>
        <li v-if="r.fechasInvalidas">{{ t('miembros.importar.google.fechasInvalidas', { n: r.fechasInvalidas }) }}</li>
        <li v-if="r.cumpleanosSinAnio">{{ t('miembros.importar.google.cumpleanosSinAnio', { n: r.cumpleanosSinAnio }) }}</li>
        <li v-if="r.notasConClave">{{ t('miembros.importar.google.notasConClave', { n: r.notasConClave }) }}</li>
        <li v-if="r.notasRecortadas">{{ t('miembros.importar.google.notasRecortadas', { n: r.notasRecortadas }) }}</li>
      </ul>
    </div>

    <div v-if="r.formato === 'wix'" class="border border-gray-100 rounded-xl overflow-hidden">
      <p class="text-sm font-medium text-gray-700 px-4 py-2 bg-gray-50">{{ t('miembros.importar.google.consentimientoTitulo') }}</p>
      <ul class="text-sm text-gray-600 px-4 py-3 space-y-1">
        <li v-for="canal in (['email', 'sms'] as const)" :key="canal">
          <span class="font-medium">{{ t(`miembros.importar.google.canal.${canal}`) }}:</span>
          {{ ESTADOS.map(e => t(`miembros.importar.google.estado.${e}`, { n: r.consentimiento[canal][e] })).join(' · ') }}
        </li>
      </ul>
      <p class="text-xs text-gray-500 px-4 pb-3">{{ t('miembros.importar.google.consentimientoAviso') }}</p>
      <p v-if="r.estadosDesconocidos" class="text-xs text-amber-800 px-4 pb-3">{{ t('miembros.importar.google.estadosDesconocidos', { n: r.estadosDesconocidos }) }}</p>
    </div>

    <p v-if="analisis.columnasSensibles.length" class="text-sm text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-4 py-3">
      {{ t('miembros.importar.google.sensibles', { columnas: analisis.columnasSensibles.join(', ') }) }}
    </p>
    <p v-if="analisis.ignoradas.length" class="text-xs text-gray-500">{{ t('miembros.importar.google.ignoradas', { columnas: analisis.ignoradas.join(', ') }) }}</p>

    <div v-if="ejemplos.length" class="border border-gray-100 rounded-xl overflow-hidden">
      <p class="text-sm font-medium text-gray-700 px-4 py-2 bg-gray-50">{{ t('miembros.importar.google.ejemplos') }}</p>
      <ul class="divide-y divide-gray-50 text-sm">
        <li v-for="p in ejemplos" :key="p.linea" class="px-4 py-2">
          <span class="font-medium text-gray-800">{{ p.nombre }} {{ p.apellido }}</span>
          <span class="block text-xs text-gray-500">{{ [p.emails[0], p.telefonos[0]?.valor].filter(Boolean).join(' · ') }}</span>
        </li>
      </ul>
    </div>

    <p v-if="errorImportar" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(errorImportar) }}</p>
    <div class="flex justify-between gap-3">
      <button @click="emit('volver')" class="btn-secondary text-sm">{{ t('miembros.importar.otroArchivo') }}</button>
      <button @click="importar" :disabled="!nuevas.length && !paraEndurecer.length" class="btn-primary text-sm disabled:opacity-50">{{ t('miembros.importar.google.importarN', { n: nuevas.length }) }}</button>
    </div>
  </div>

  <div v-else-if="paso === 'importando'" class="py-8 text-center space-y-3" role="status">
    <p class="text-gray-700 font-medium">{{ t('miembros.importar.google.importando') }}</p>
    <div class="w-full h-2 bg-gray-100 rounded-full overflow-hidden"><div class="h-2 bg-adn-verde transition-all" :style="{ width: `${progreso}%` }"></div></div>
    <p class="text-xs text-gray-400">{{ t('miembros.importar.noCierres') }}</p>
  </div>

  <div v-else class="space-y-4 text-center py-4">
    <CircleCheck v-if="!errorImportar" class="w-12 h-12 mx-auto text-green-600" aria-hidden="true" />
    <TriangleAlert v-else class="w-12 h-12 mx-auto text-amber-500" aria-hidden="true" />
    <p class="text-gray-900 font-semibold">{{ t('miembros.importar.google.hecho', { n: importados }) }}</p>
    <p v-if="omitidosBase" class="text-sm text-gray-500">{{ t('miembros.importar.google.omitidos', { n: omitidosBase }) }}</p>
    <p v-if="errorImportar" role="alert" class="text-sm text-red-700">{{ t(errorImportar) }}</p>
    <button @click="emit('cerrar')" class="btn-primary text-sm">{{ t('comun.cerrar') }}</button>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { CircleCheck, TriangleAlert } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { esLimitePlan } from '@/lib/plan'
import { normalizar } from '@/lib/importarMiembros'
import { aFilaImportacion, esDuplicadoDeExistente, telefonoCanonico, ESTADOS, LOTE_GOOGLE } from '@/lib/importarGoogle'
import type { AnalisisGoogle, Existentes } from '@/lib/importarGoogle'

const props = defineProps<{ analisis: AnalisisGoogle }>()
const emit = defineEmits<{ cerrar: []; volver: []; importado: [] }>()
const { t } = useI18n()

const paso = ref<'cargando' | 'revisar' | 'importando' | 'hecho'>('cargando')
const existentes = ref<Existentes>({ correos: new Set(), telefonos: new Set(), nombres: new Set() })
const incluirSinNombre = ref(false)
const errorImportar = ref('')
const progreso = ref(0)
const importados = ref(0)
const omitidosBase = ref(0)

const r = computed(() => props.analisis.resumen)
const sinNombreTotal = computed(() => props.analisis.personas.filter(p => p.nombreDerivado).length)
// Las personas sin nombre quedan fuera salvo que se pida lo contrario
const candidatas = computed(() => props.analisis.personas.filter(p => incluirSinNombre.value || !p.nombreDerivado))
const yaExisten = computed(() => candidatas.value.filter(p => esDuplicadoDeExistente(p, existentes.value)))
const nuevas = computed(() => candidatas.value.filter(p => !esDuplicadoDeExistente(p, existentes.value)))
// Quienes ya existen y traen un estado de suscripción también viajan: la base solo puede endurecer su consentimiento
// (una baja del archivo se respeta aunque ya estuvieran), nunca relajarlo, y no los duplica
const paraEndurecer = computed(() => yaExisten.value.filter(p => Object.values(p.consentimiento).some(e => e !== 'sin_dato')))
const ejemplos = computed(() => nuevas.value.slice(0, 5))

// Lo que la iglesia ya tiene, para no duplicarlo. La base lo vuelve a comprobar al importar.
async function leerExistentes(): Promise<boolean> {
  const e: Existentes = { correos: new Set(), telefonos: new Set(), nombres: new Set() }
  for (let desde = 0; ; desde += 1000) {
    const { data, error } = await supabase.from('miembros').select('nombre, apellido, email, telefono').order('id').range(desde, desde + 999)
    if (error) return false
    for (const m of data ?? []) {
      if (m.email) e.correos.add(m.email.toLowerCase())
      const tel = m.telefono ? telefonoCanonico(m.telefono) : null
      if (tel) e.telefonos.add(tel)
      e.nombres.add(normalizar(`${m.nombre} ${m.apellido}`))
    }
    if ((data ?? []).length < 1000) break
  }
  for (let desde = 0; ; desde += 1000) {
    const { data, error } = await supabase.from('adn_miembro_contactos').select('tipo, valor').in('tipo', ['correo', 'telefono']).order('id').range(desde, desde + 999)
    if (error) return false
    for (const c of data ?? []) {
      if (c.tipo === 'correo') e.correos.add(String(c.valor).toLowerCase())
      else { const tel = telefonoCanonico(String(c.valor)); if (tel) e.telefonos.add(tel) }
    }
    if ((data ?? []).length < 1000) break
  }
  existentes.value = e
  return true
}

onMounted(async () => {
  if (!(await leerExistentes())) { errorImportar.value = 'miembros.importar.google.errorLectura'; paso.value = 'hecho'; return }
  paso.value = 'revisar'
})

function errorDe(err: { message?: string } | null): string {
  if (esLimitePlan(err)) return 'plan.limiteMiembrosImportar'
  const m = String(err?.message ?? '')
  if (/ADN_SIN_PERMISO/.test(m)) return 'miembros.importar.google.errorPermiso'
  if (/ADN_MODO_ALIAS/.test(m)) return 'miembros.importar.google.errorModoAlias'
  return 'miembros.importar.google.errorImportar'
}

async function importar() {
  const lista = [...nuevas.value, ...paraEndurecer.value]
  paso.value = 'importando'
  progreso.value = 0
  importados.value = 0
  omitidosBase.value = 0
  errorImportar.value = ''
  for (let i = 0; i < lista.length; i += LOTE_GOOGLE) {
    const lote = lista.slice(i, i + LOTE_GOOGLE).map(aFilaImportacion)
    const { data, error } = await supabase.rpc('adn_importar_miembros', { p_filas: lote, p_origen: r.value.formato })
    if (error) { errorImportar.value = errorDe(error); break }
    const res = (data ?? {}) as Record<string, number>
    importados.value += res.importados ?? 0
    omitidosBase.value += (res.duplicados_correo ?? 0) + (res.duplicados_telefono ?? 0) + (res.duplicados_nombre ?? 0)
    progreso.value = Math.round(((i + lote.length) / lista.length) * 100)
  }
  paso.value = 'hecho'
  if (importados.value > 0) emit('importado')
}
</script>
