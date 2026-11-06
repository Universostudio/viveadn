<template>
  <div class="card space-y-4">
    <div>
      <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><QrCode class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('checkin.qr.titulo') }}</h2>
      <p class="text-sm text-gray-500 mt-0.5">{{ t('checkin.qr.descripcion') }}</p>
    </div>

    <p v-if="cargando" class="text-sm text-gray-400" role="status">{{ t('comun.cargando') }}</p>

    <button v-else-if="!enlace" @click="activar" :disabled="trabajando" class="btn-primary text-sm disabled:opacity-60">{{ t('checkin.qr.activar') }}</button>

    <template v-else>
      <div class="flex flex-col sm:flex-row gap-5 items-start">
        <img v-if="imagen" :src="imagen" :alt="t('checkin.qr.qrAlt')" width="180" height="180" :class="['rounded-xl border border-gray-100 flex-shrink-0', !enlace.activo && 'opacity-30']" />
        <div class="space-y-3 min-w-0 flex-1">
          <p v-if="!enlace.activo" role="status" class="text-sm font-medium text-amber-700 bg-amber-50 rounded-lg px-3 py-2">{{ t('checkin.qr.pausado') }}</p>
          <div>
            <label for="qr-url" class="block text-xs font-medium text-gray-500 mb-1">{{ t('checkin.qr.enlace') }}</label>
            <input id="qr-url" :value="url" readonly @focus="($event.target as HTMLInputElement).select()" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-xs font-mono bg-gray-50" />
          </div>
          <div class="flex flex-wrap gap-2">
            <button @click="copiar" class="btn-secondary text-sm">{{ copiado ? t('checkin.qr.copiado') : t('checkin.qr.copiar') }}</button>
            <a :href="url" target="_blank" rel="noopener noreferrer" class="btn-secondary text-sm inline-flex items-center gap-1">{{ t('checkin.qr.abrir') }} <ExternalLink class="w-4 h-4" aria-hidden="true" /></a>
            <a v-if="imagen" :href="imagen" download="registro-qr.png" class="btn-secondary text-sm inline-flex items-center gap-1"><Download class="w-4 h-4" aria-hidden="true" /> {{ t('checkin.qr.descargar') }}</a>
            <button v-if="enlace.activo" @click="abrirCartel" class="btn-secondary text-sm inline-flex items-center gap-1"><Printer class="w-4 h-4" aria-hidden="true" /> {{ t('checkin.qr.cartel.boton') }}</button>
          </div>
          <p class="text-sm text-gray-600">{{ t('checkin.qr.registros', { n: totales.registros, nuevos: totales.nuevos }) }}</p>
          <p class="text-xs text-gray-400">{{ t('checkin.qr.ventana') }}</p>
        </div>
      </div>

      <div class="flex flex-wrap items-end gap-3 pt-3 border-t border-gray-50">
        <button @click="alternarActivo" :disabled="trabajando" class="btn-secondary text-sm">{{ t(enlace.activo ? 'checkin.qr.pausar' : 'checkin.qr.reanudar') }}</button>
        <button @click="nuevoEnlace" :disabled="trabajando" class="btn-secondary text-sm inline-flex items-center gap-1"><RefreshCw class="w-4 h-4" aria-hidden="true" /> {{ t('checkin.qr.nuevoEnlace') }}</button>
        <div class="flex items-end gap-2 ml-auto">
          <div>
            <label for="qr-max" class="block text-xs font-medium text-gray-500 mb-1">{{ t('checkin.qr.maxRegistros') }}</label>
            <input id="qr-max" v-model.number="maximo" type="number" min="1" max="2000" class="w-24 px-2 py-1.5 border border-gray-200 rounded-lg text-sm" />
          </div>
          <button @click="guardarMaximo" :disabled="trabajando || !maximoValido" class="btn-secondary text-sm disabled:opacity-60">{{ t('checkin.qr.guardar') }}</button>
        </div>
      </div>
      <p class="text-xs text-gray-400">{{ t('checkin.qr.aviso') }}</p>
    </template>
    <!-- Cartel para imprimir y pegar en el lugar del evento -->
    <div v-if="cartelAbierto" class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50 overflow-y-auto" @click.self="cartelAbierto = false" role="dialog" aria-modal="true" :aria-label="t('checkin.qr.cartel.boton')">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-xl p-6 my-6">
        <div class="cartel-imprimible border-4 border-adn-verde rounded-xl p-8 text-center bg-white">
          <p class="text-sm uppercase tracking-widest text-gray-500">{{ auth.nombreIglesia }}</p>
          <h2 class="text-3xl font-bold text-gray-900 mt-2">{{ eventoTitulo }}</h2>
          <p class="text-xl font-semibold text-adn-verde mt-6">{{ t('checkin.qr.cartel.titulo') }}</p>
          <img v-if="imagenCartel" :src="imagenCartel" :alt="t('checkin.qr.qrAlt')" class="mx-auto mt-4" width="320" height="320" />
          <ol class="text-left text-gray-700 mt-6 space-y-1 text-base list-decimal list-inside">
            <li>{{ t('checkin.qr.cartel.paso1') }}</li>
            <li>{{ t('checkin.qr.cartel.paso2') }}</li>
            <li>{{ t('checkin.qr.cartel.paso3') }}</li>
          </ol>
          <p class="text-xs text-gray-400 mt-6">{{ t('checkin.qr.cartel.privacidad') }}</p>
        </div>
        <div class="flex gap-3 mt-4">
          <button @click="cartelAbierto = false" class="btn-secondary flex-1">{{ t('checkin.qr.cartel.cerrar') }}</button>
          <button @click="imprimirCartel" class="btn-primary flex-1">{{ t('checkin.qr.cartel.imprimir') }}</button>
        </div>
      </div>
    </div>

    <p v-if="error" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(error) }}</p>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import QRCode from 'qrcode'
import { QrCode, ExternalLink, Download, RefreshCw, Printer } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'

const props = defineProps<{ eventoId: string; eventoTitulo: string }>()
const auth = useAuthStore()
const { t } = useI18n()

const cargando = ref(true)
const trabajando = ref(false)
const error = ref('')
const copiado = ref(false)
const enlace = ref<{ id: string; token: string; activo: boolean; max_registros: number } | null>(null)
const imagen = ref('')
const maximo = ref(300)
const totales = ref({ registros: 0, nuevos: 0 })

const url = computed(() => (enlace.value ? `${window.location.origin}/checkin/${enlace.value.token}` : ''))
const maximoValido = computed(() => Number.isInteger(maximo.value) && maximo.value >= 1 && maximo.value <= 2000)

// El QR se dibuja en el navegador a partir del enlace; nunca se envía a ningún servicio externo
watch(url, async (u) => { imagen.value = u ? await QRCode.toDataURL(u, { width: 360, margin: 2, errorCorrectionLevel: 'M' }) : '' }, { immediate: true })

async function cargar() {
  cargando.value = true
  const { data } = await supabase.from('evento_checkin').select('id, token, activo, max_registros').eq('evento_id', props.eventoId).maybeSingle()
  enlace.value = data
  if (data) {
    maximo.value = data.max_registros
    const [todos, nuevos] = await Promise.all([
      supabase.from('checkin_registros').select('id', { count: 'exact', head: true }).eq('evento_id', props.eventoId),
      supabase.from('checkin_registros').select('id', { count: 'exact', head: true }).eq('evento_id', props.eventoId).eq('creado', true),
    ])
    totales.value = { registros: todos.count ?? 0, nuevos: nuevos.count ?? 0 }
  }
  cargando.value = false
}

async function activar() {
  error.value = ''
  trabajando.value = true
  const { error: err } = await supabase.from('evento_checkin').insert({ evento_id: props.eventoId })
  trabajando.value = false
  if (err) { error.value = 'checkin.qr.error'; return }
  await cargar()
}

async function actualizar(cambios: Record<string, unknown>) {
  if (!enlace.value) return
  error.value = ''
  trabajando.value = true
  const { data, error: err } = await supabase.from('evento_checkin').update(cambios).eq('id', enlace.value.id).select('id')
  trabajando.value = false
  if (err || !data?.length) { error.value = 'checkin.qr.error'; return }
  await cargar()
}

const alternarActivo = () => actualizar({ activo: !enlace.value?.activo })
const guardarMaximo = () => maximoValido.value && actualizar({ max_registros: maximo.value })

// Enlace nuevo: 256 bits aleatorios en el navegador; el anterior (y su QR impreso) deja de funcionar
function nuevoEnlace() {
  if (!window.confirm(t('checkin.qr.confirmarNuevo'))) return
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  actualizar({ token: [...bytes].map(b => b.toString(16).padStart(2, '0')).join('') })
}

async function copiar() {
  try { await navigator.clipboard.writeText(url.value); copiado.value = true; setTimeout(() => { copiado.value = false }, 2000) } catch { /* se puede copiar a mano */ }
}

// Cartel: el QR se redibuja a mayor resolucion para que se lea bien impreso
const cartelAbierto = ref(false)
const imagenCartel = ref('')
async function abrirCartel() {
  imagenCartel.value = await QRCode.toDataURL(url.value, { width: 900, margin: 2, errorCorrectionLevel: 'M' })
  cartelAbierto.value = true
}
const imprimirCartel = () => window.print()

onMounted(cargar)
</script>

<style>
/* Al imprimir solo sale el cartel */
@media print {
  body * { visibility: hidden; }
  .cartel-imprimible, .cartel-imprimible * { visibility: visible; }
  .cartel-imprimible { position: fixed; left: 0; top: 0; width: 100%; border-width: 8px; }
}
</style>
