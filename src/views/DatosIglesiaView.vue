<template>
  <div class="p-4 sm:p-6 space-y-6 max-w-3xl">
    <div>
      <RouterLink to="/configuracion" class="text-sm text-adn-verde underline">{{ t('datosIglesia.volver') }}</RouterLink>
      <h1 class="text-2xl font-bold text-gray-900 mt-2">{{ t('datosIglesia.titulo') }}</h1>
    </div>

    <p v-if="cargando" class="text-sm text-gray-500" role="status">{{ t('datosIglesia.cargando') }}</p>
    <p v-else-if="noPropietario" class="card border border-gray-200 text-sm text-gray-700" data-test="solo-propietario">{{ t('datosIglesia.soloPropietario') }}</p>
    <p v-else-if="errorCarga" class="card border border-red-200 text-sm text-red-700" role="alert">{{ errorCarga }}</p>

    <template v-else-if="estado">
      <p v-if="aviso" :class="['text-sm rounded-lg px-3 py-2', avisoError ? 'bg-red-50 text-red-700' : 'bg-adn-verde/10 text-adn-verde']" :role="avisoError ? 'alert' : 'status'" data-test="aviso">{{ aviso }}</p>

      <section class="card border border-gray-200 space-y-3" data-test="descarga">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><Download class="w-5 h-5" aria-hidden="true" /> {{ t('datosIglesia.descargaTitulo') }}</h2>
        <p class="text-sm text-gray-700">{{ t('datosIglesia.descargaTexto') }}</p>
        <p class="text-sm text-gray-500">{{ t('datosIglesia.tardaAviso') }}</p>
        <p class="text-sm text-gray-500">{{ t('datosIglesia.descargaRestantes', { n: estado.descargas_restantes }) }}</p>
        <button class="btn-primary" :disabled="descargando || estado.descargas_restantes < 1" @click="descargar" data-test="descargar">
          {{ descargando ? progreso : t('datosIglesia.descargar') }}
        </button>
      </section>

      <section class="card border border-gray-200 space-y-3" data-test="baja">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><Trash2 class="w-5 h-5" aria-hidden="true" /> {{ t('datosIglesia.bajaTitulo') }}</h2>

        <template v-if="estado.baja">
          <p class="text-sm text-gray-700" data-test="baja-activa">{{ t('datosIglesia.bajaActiva', { desde: fecha(estado.baja.solicitada_en), hasta: fecha(estado.baja.purga_el) }) }}</p>
          <p v-if="!estado.baja.por_la_iglesia" class="text-sm text-gray-700">{{ t('datosIglesia.bajaDePlataforma') }}</p>
          <p v-else-if="!estado.baja.cancelable" class="text-sm text-gray-700">{{ t('datosIglesia.bajaVencida') }}</p>
          <button v-else class="btn-primary" :disabled="trabajando" @click="cancelarBaja" data-test="cancelar-baja">{{ t('datosIglesia.bajaCancelar') }}</button>
        </template>

        <template v-else>
          <p class="text-sm text-gray-700">{{ t('datosIglesia.bajaTexto', { dias: estado.plazo_dias }) }}</p>
          <p class="text-sm font-medium text-gray-900">{{ t('datosIglesia.bajaAntes') }}</p>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1" for="baja-motivo">{{ t('datosIglesia.bajaMotivo') }}</label>
            <textarea id="baja-motivo" v-model="motivo" rows="2" maxlength="500" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde"></textarea>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1" for="baja-confirmar">{{ t('datosIglesia.bajaConfirmar', { slug: estado.slug }) }}</label>
            <input id="baja-confirmar" v-model="confirmar" type="text" autocomplete="off" spellcheck="false" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <label class="flex items-start gap-2 text-sm text-gray-700">
            <input v-model="entiendo" type="checkbox" class="mt-1" data-test="entiendo" />
            <span>{{ t('datosIglesia.bajaEntiendo', { dias: estado.plazo_dias }) }}</span>
          </label>
          <button class="px-4 py-2.5 rounded-lg text-sm font-medium bg-red-600 text-white hover:bg-red-700 disabled:opacity-50" :disabled="trabajando || !entiendo || confirmar.trim() !== estado.slug" @click="pedirBaja" data-test="pedir-baja">
            {{ t('datosIglesia.bajaPedir') }}
          </button>
        </template>
      </section>
    </template>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { Download, Trash2 } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { exportarPaginado, fuenteDePlataforma } from '@/lib/exportacionPaginada'

interface Estado {
  nombre: string; slug: string; etapa: string; descargas_restantes: number; plazo_dias: number
  baja: { solicitada_en: string; purga_el: string; por_la_iglesia: boolean; cancelable: boolean } | null
}

const { t, locale } = useI18n()
const estado = ref<Estado | null>(null)
const cargando = ref(true)
const noPropietario = ref(false)
const errorCarga = ref('')
const aviso = ref('')
const avisoError = ref(false)
const descargando = ref(false)
const progreso = ref('')
const trabajando = ref(false)
const motivo = ref('')
const confirmar = ref('')
const entiendo = ref(false)

const fecha = (iso: string) => new Date(iso).toLocaleDateString(locale.value, { day: 'numeric', month: 'long', year: 'numeric' })

// Llama a la función `datos-iglesia`. Devuelve los datos o lanza con el motivo que da la función (y el estado HTTP en `estado`)
async function llamar(cuerpo: Record<string, unknown>) {
  const { data, error } = await supabase.functions.invoke('datos-iglesia', { body: cuerpo })
  if (error) {
    let motivoError = t('datosIglesia.errorGenerico')
    let http = 0
    try {
      const resp = (error as any).context
      http = resp?.status ?? 0
      if (resp?.json) motivoError = (await resp.json()).error ?? motivoError
    } catch { /* se queda el mensaje genérico */ }
    throw Object.assign(new Error(motivoError), { estado: http })
  }
  return data
}

function mostrar(texto: string, error = false) { aviso.value = texto; avisoError.value = error }

async function cargar() {
  cargando.value = true
  try {
    estado.value = (await llamar({ accion: 'estado' })).estado
  } catch (e: any) {
    if (e.estado === 403) noPropietario.value = true
    else errorCarga.value = e.message
  } finally { cargando.value = false }
}

async function descargar() {
  if (!estado.value || descargando.value) return
  descargando.value = true
  mostrar('')
  progreso.value = t('datosIglesia.preparando')
  try {
    const partes: Uint8Array[] = []
    const r = await exportarPaginado(fuenteDePlataforma(llamar, ''), {
      slug: estado.value.slug, hoy: new Date(), leeme: t('plataforma.exportLeeme'), destino: p => { partes.push(p) },
      progreso: p => { progreso.value = t('datosIglesia.descargando', { indice: p.indice, tablas: p.tablas, tabla: p.tabla }) },
    })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob(partes as BlobPart[], { type: 'application/zip' }))
    a.download = r.nombre
    a.click()
    URL.revokeObjectURL(a.href)
    mostrar(t(r.cambios ? 'datosIglesia.descargaConCambios' : 'datosIglesia.descargaLista'), r.cambios)
  } catch (e: any) {
    mostrar(e.message, true)
  } finally {
    descargando.value = false
    await cargar()
  }
}

async function pedirBaja() {
  if (!estado.value || trabajando.value) return
  trabajando.value = true
  try {
    const d = await llamar({ accion: 'solicitar_baja', confirmar: confirmar.value.trim(), motivo: motivo.value })
    mostrar(t('datosIglesia.bajaPedida', { fecha: fecha(d.purga_el) }))
    confirmar.value = ''; motivo.value = ''; entiendo.value = false
    await cargar()
  } catch (e: any) {
    mostrar(e.message, true)
  } finally { trabajando.value = false }
}

async function cancelarBaja() {
  if (trabajando.value) return
  trabajando.value = true
  try {
    await llamar({ accion: 'cancelar_baja' })
    mostrar(t('datosIglesia.bajaCancelada'))
    await cargar()
  } catch (e: any) {
    mostrar(e.message, true)
  } finally { trabajando.value = false }
}

onMounted(cargar)
</script>
