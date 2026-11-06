<template>
  <div class="card space-y-4">
    <div>
      <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><ScanLine class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('eventos.escaner.titulo') }}</h2>
      <p class="text-sm text-gray-500 mt-0.5">{{ t('eventos.escaner.descripcion') }}</p>
    </div>

    <div class="flex flex-wrap gap-2">
      <button v-if="!camaraActiva" @click="abrirCamara" class="btn-primary text-sm inline-flex items-center gap-1"><Camera class="w-4 h-4" aria-hidden="true" /> {{ t('eventos.escaner.abrir') }}</button>
      <button v-else @click="cerrarCamara" class="btn-secondary text-sm">{{ t('eventos.escaner.cerrar') }}</button>
    </div>
    <p v-if="errorCamara" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(errorCamara) }}</p>

    <div v-show="camaraActiva" class="relative max-w-sm">
      <video ref="video" class="w-full rounded-xl bg-black" playsinline muted :aria-label="t('eventos.escaner.camara')"></video>
      <canvas ref="lienzo" class="hidden"></canvas>
    </div>

    <form @submit.prevent="enviarManual" class="flex items-end gap-2 max-w-sm">
      <div class="flex-1">
        <label for="esc-manual" class="block text-xs font-medium text-gray-500 mb-1">{{ t('eventos.escaner.manual') }}</label>
        <input id="esc-manual" v-model="manual" autocomplete="off" autocapitalize="off" spellcheck="false" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm font-mono" />
      </div>
      <button type="submit" :disabled="!manual.trim() || ocupado" class="btn-secondary text-sm disabled:opacity-60">{{ t('eventos.escaner.enviar') }}</button>
    </form>

    <div role="status" aria-live="polite">
      <p v-if="resultado" :class="['text-sm font-medium rounded-lg px-4 py-3 border', claseResultado]">{{ t('eventos.escaner.resultado.' + resultado.estado, { nombre: resultado.nombre ?? '' }) }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onBeforeUnmount } from 'vue'
import { useI18n } from 'vue-i18n'
import jsQR from 'jsqr'
import { ScanLine, Camera } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { tokenDeQr } from '@/lib/credencial'

const props = defineProps<{ eventoId: string }>()
const emit = defineEmits<{ registrado: [] }>()
const { t } = useI18n()

const video = ref<HTMLVideoElement | null>(null)
const lienzo = ref<HTMLCanvasElement | null>(null)
const camaraActiva = ref(false)
const errorCamara = ref('')
const manual = ref('')
const ocupado = ref(false)
const resultado = ref<{ estado: string; nombre?: string } | null>(null)

let flujo: MediaStream | null = null
let temporizador: ReturnType<typeof setInterval> | null = null
let ultimo = { token: '', en: 0 }

const claseResultado = computed(() => {
  const e = resultado.value?.estado
  if (e === 'registrado') return 'bg-green-50 text-green-700 border-green-200'
  if (e === 'ya_registrado') return 'bg-blue-50 text-blue-700 border-blue-200'
  return 'bg-amber-50 text-amber-700 border-amber-200'
})

// Una credencial leida varias veces seguidas (la camara la ve muchos fotogramas) se procesa una sola vez
async function procesar(token: string) {
  const ahora = Date.now()
  if (ocupado.value || (token === ultimo.token && ahora - ultimo.en < 4000)) return
  ultimo = { token, en: ahora }
  ocupado.value = true
  const { data, error } = await supabase.rpc('registrar_asistencia_credencial', { p_evento: props.eventoId, p_token: token })
  ocupado.value = false
  if (error || !data) { resultado.value = { estado: 'error' }; return }
  resultado.value = data as { estado: string; nombre?: string }
  if (resultado.value.estado === 'registrado') { navigator.vibrate?.(60); emit('registrado') }
}

async function enviarManual() {
  const token = tokenDeQr(manual.value)
  manual.value = ''
  if (!token) { resultado.value = { estado: 'desconocida' }; return }
  ultimo = { token: '', en: 0 }
  await procesar(token)
}

function leerFotograma() {
  const v = video.value, c = lienzo.value
  if (!v || !c || v.readyState < 2 || !v.videoWidth) return
  const escala = Math.min(1, 640 / v.videoWidth)
  c.width = Math.round(v.videoWidth * escala)
  c.height = Math.round(v.videoHeight * escala)
  const ctx = c.getContext('2d', { willReadFrequently: true })
  if (!ctx) return
  ctx.drawImage(v, 0, 0, c.width, c.height)
  const img = ctx.getImageData(0, 0, c.width, c.height)
  const qr = jsQR(img.data, img.width, img.height, { inversionAttempts: 'dontInvert' })
  const token = qr ? tokenDeQr(qr.data) : null
  if (token) void procesar(token)
}

async function abrirCamara() {
  errorCamara.value = ''
  if (!navigator.mediaDevices?.getUserMedia) { errorCamara.value = 'eventos.escaner.sinCamara'; return }
  try {
    flujo = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false })
  } catch {
    errorCamara.value = 'eventos.escaner.errorCamara'
    return
  }
  camaraActiva.value = true
  const v = video.value
  if (v) { v.srcObject = flujo; await v.play().catch(() => undefined) }
  temporizador = setInterval(leerFotograma, 250)
}

function cerrarCamara() {
  if (temporizador) { clearInterval(temporizador); temporizador = null }
  flujo?.getTracks().forEach(p => p.stop())
  flujo = null
  if (video.value) video.value.srcObject = null
  camaraActiva.value = false
}

onBeforeUnmount(cerrarCamara)
</script>
