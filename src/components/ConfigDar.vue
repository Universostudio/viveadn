<template>
  <div class="space-y-6">
    <!-- Fondos -->
    <div class="card space-y-4">
      <div>
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><HandHeart class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('dar.config.fondosTitulo') }}</h2>
        <p class="text-sm text-gray-500 mt-0.5">{{ t('dar.config.fondosAyuda') }}</p>
      </div>

      <p v-if="cargando" class="text-sm text-gray-400" role="status">{{ t('comun.cargando') }}</p>
      <template v-else>
        <ul v-if="filas.length" class="space-y-3">
          <li v-for="(f, i) in filas" :key="f.id" class="rounded-xl border border-gray-100 p-3 space-y-2">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
              <input v-model="f.nombre" maxlength="80" :disabled="!puede" :aria-label="`${t('dar.config.nombre')} ${i + 1}`" :placeholder="t('dar.config.nombre')"
                class="px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde disabled:bg-gray-50" />
              <input v-model="f.url" type="url" inputmode="url" maxlength="500" :disabled="!puede" :aria-label="`${t('dar.config.enlace')} ${i + 1}`" :placeholder="t('dar.ejemploUrl')"
                class="px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde disabled:bg-gray-50" />
            </div>
            <input v-model="f.descripcion" maxlength="200" :disabled="!puede" :aria-label="`${t('dar.config.descripcion')} ${i + 1}`" :placeholder="t('dar.config.descripcion')"
              class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde disabled:bg-gray-50" />
            <p v-if="f.url.trim() && !urlDarValida(f.url.trim())" class="text-xs text-red-600">{{ t('dar.urlInvalida') }}</p>
            <p v-else-if="!f.url.trim()" class="text-xs text-gray-400">{{ t('dar.config.sinEnlaceSeOculta') }}</p>
            <div v-if="puede" class="flex justify-end gap-1">
              <button type="button" @click="mover(i, -1)" :disabled="i === 0" :aria-label="t('dar.config.subir')" class="p-1.5 rounded-lg text-gray-500 hover:bg-gray-100 disabled:opacity-30"><ArrowUp class="w-4 h-4" aria-hidden="true" /></button>
              <button type="button" @click="mover(i, 1)" :disabled="i === filas.length - 1" :aria-label="t('dar.config.bajar')" class="p-1.5 rounded-lg text-gray-500 hover:bg-gray-100 disabled:opacity-30"><ArrowDown class="w-4 h-4" aria-hidden="true" /></button>
              <button type="button" @click="quitar(i)" :aria-label="t('dar.config.quitar')" class="p-1.5 rounded-lg text-red-500 hover:bg-red-50"><Trash2 class="w-4 h-4" aria-hidden="true" /></button>
            </div>
          </li>
        </ul>
        <p v-else class="text-sm text-gray-400 py-2">{{ t('dar.config.sinFondos') }}</p>

        <div v-if="puede" class="flex flex-wrap items-center gap-3">
          <label for="dar-anadir" class="sr-only">{{ t('dar.config.anadir') }}</label>
          <select id="dar-anadir" v-model="preset" @change="anadir" :disabled="filas.length >= MAX_FONDOS" class="px-3 py-2 border border-gray-200 rounded-lg text-sm bg-white disabled:opacity-50">
            <option value="">{{ t('dar.config.anadir') }}</option>
            <option v-for="p in PRESETS" :key="p" :value="p">{{ t(`dar.config.preset.${p}`) }}</option>
            <option value="otro">{{ t('dar.config.preset.otro') }}</option>
          </select>
          <span class="text-xs text-gray-400">{{ t('dar.config.maximo', { n: MAX_FONDOS }) }}</span>
        </div>
      </template>
    </div>

    <!-- Apariencia -->
    <div class="card space-y-5">
      <div>
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><Palette class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('dar.config.aparienciaTitulo') }}</h2>
        <p class="text-sm text-gray-500 mt-0.5">{{ t('dar.config.aparienciaAyuda') }}</p>
      </div>

      <fieldset :disabled="!puede">
        <legend class="text-sm font-medium text-gray-700 mb-2">{{ t('dar.config.plantilla') }}</legend>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3" role="radiogroup">
          <label v-for="p in PLANTILLAS" :key="p"
            :class="['rounded-xl border p-3 cursor-pointer transition-colors', config.plantilla === p ? 'border-adn-verde ring-2 ring-adn-verde/30' : 'border-gray-200 hover:border-gray-300']">
            <input v-model="config.plantilla" type="radio" name="plantilla" :value="p" class="sr-only" />
            <!-- Miniatura con los colores elegidos -->
            <div class="rounded-lg overflow-hidden border border-gray-100 bg-gray-50 h-24 relative" aria-hidden="true">
              <template v-if="p === 'clasica'">
                <div class="h-9 flex items-center justify-center text-[10px] font-bold" :style="{ background: config.color_primario, color: config.color_acento }">{{ t('dar.pagina.tituloClasica') }}</div>
                <div class="mx-3 mt-2 h-10 rounded bg-white shadow-sm"></div>
              </template>
              <template v-else>
                <div class="mx-4 mt-3 h-10 rounded-lg flex items-center justify-center text-[10px] font-bold text-white" :style="{ background: `linear-gradient(135deg, ${config.color_acento}, ${config.color_primario})` }">{{ t('dar.pagina.tituloDia') }}</div>
                <div class="mx-4 mt-2 h-7 rounded bg-white shadow-sm"></div>
              </template>
            </div>
            <p class="mt-2 text-sm font-semibold text-gray-900">{{ t(`dar.config.plantillas.${p}.nombre`) }}</p>
            <p class="text-xs text-gray-500">{{ t(`dar.config.plantillas.${p}.descripcion`) }}</p>
          </label>
        </div>
      </fieldset>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <label for="dar-titulo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('dar.config.titulo') }}</label>
          <input id="dar-titulo" v-model="config.titulo" maxlength="100" :disabled="!puede" :placeholder="t(config.plantilla === 'dia' ? 'dar.pagina.tituloDia' : 'dar.pagina.tituloClasica')"
            class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde disabled:bg-gray-50" />
        </div>
        <div>
          <label for="dar-subtitulo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('dar.config.subtitulo') }}</label>
          <input id="dar-subtitulo" v-model="config.subtitulo" maxlength="200" :disabled="!puede"
            class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde disabled:bg-gray-50" />
        </div>
        <div class="flex items-end gap-3">
          <div>
            <label for="dar-c1" class="block text-sm font-medium text-gray-700 mb-1">{{ t('dar.config.colorPrimario') }}</label>
            <input id="dar-c1" v-model="config.color_primario" type="color" :disabled="!puede" class="h-11 w-20 rounded-lg border border-gray-200 bg-white p-1" />
          </div>
          <p class="pb-3 text-xs font-mono text-gray-500">{{ config.color_primario }}</p>
        </div>
        <div class="flex items-end gap-3">
          <div>
            <label for="dar-c2" class="block text-sm font-medium text-gray-700 mb-1">{{ t('dar.config.colorAcento') }}</label>
            <input id="dar-c2" v-model="config.color_acento" type="color" :disabled="!puede" class="h-11 w-20 rounded-lg border border-gray-200 bg-white p-1" />
          </div>
          <p class="pb-3 text-xs font-mono text-gray-500">{{ config.color_acento }}</p>
        </div>
        <div class="sm:col-span-2">
          <label for="dar-logo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('dar.config.logo') }}</label>
          <input id="dar-logo" v-model="logo" type="url" inputmode="url" maxlength="500" :disabled="!puede" placeholder="https://tu-iglesia.org/logo.png"
            class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde disabled:bg-gray-50" />
          <p v-if="logo.trim() && !urlDarValida(logo.trim())" class="text-xs text-red-600 mt-1">{{ t('dar.urlInvalida') }}</p>
          <p v-else class="text-xs text-gray-400 mt-1">{{ t('dar.config.logoAyuda') }}</p>
        </div>
        <div>
          <label for="dar-calc" class="block text-sm font-medium text-gray-700 mb-1">{{ t('dar.config.calculadora') }}</label>
          <select id="dar-calc" v-model="config.calculadora" :disabled="!puede" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm bg-white">
            <option v-for="m in MODOS_CALCULADORA" :key="m" :value="m">{{ t(`dar.config.calculadoras.${m}`) }}</option>
          </select>
        </div>
        <div>
          <label for="dar-moneda" class="block text-sm font-medium text-gray-700 mb-1">{{ t('dar.config.moneda') }}</label>
          <select id="dar-moneda" v-model="config.moneda" :disabled="!puede" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm bg-white">
            <option v-for="m in MONEDAS" :key="m" :value="m">{{ m }} ({{ simboloMoneda(m, locale) }})</option>
          </select>
        </div>
      </div>
    </div>

    <p v-if="mensaje" role="status" :class="['text-sm', mensajeError ? 'text-red-700' : 'text-gray-600']">{{ t(mensaje) }}</p>
    <div class="flex justify-end">
      <button v-if="puede" @click="guardar" :disabled="guardando || hayErrores" class="btn-primary disabled:opacity-60">{{ guardando ? t('comun.guardando') : t('configuracion.guardarCambios') }}</button>
      <p v-else class="text-xs text-gray-400">{{ t('dar.sinPermiso') }}</p>
    </div>

    <!-- Enlace a la página pública -->
    <div v-if="enlacePublico" class="card space-y-3">
      <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><ExternalLink class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('dar.publicaTitulo') }}</h2>
      <p class="text-sm text-gray-500">{{ t('dar.publicaDescripcion') }}</p>
      <div class="flex flex-col sm:flex-row gap-2">
        <input :value="enlacePublico" readonly aria-label="URL" @focus="($event.target as HTMLInputElement).select()" class="flex-1 px-3 py-2.5 border border-gray-200 rounded-lg text-sm bg-gray-50 font-mono" />
        <button @click="copiarEnlace" class="btn-secondary text-sm">{{ copiado ? t('dar.copiado') : t('dar.copiar') }}</button>
        <a :href="enlacePublico" target="_blank" rel="noopener noreferrer" class="btn-primary text-sm inline-flex items-center justify-center gap-2">
          {{ t('dar.abrirPagina') }} <ExternalLink class="w-4 h-4" aria-hidden="true" />
        </a>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { ArrowDown, ArrowUp, ExternalLink, HandHeart, Palette, Trash2 } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import {
  CONFIG_POR_DEFECTO, MAX_FONDOS, MODOS_CALCULADORA, MONEDAS, PLANTILLAS, TIPOS_DAR,
  claveFondo, colorValido, simboloMoneda, urlDarValida,
} from '@/lib/dar'
import type { ConfigDar } from '@/lib/dar'

const { t, locale } = useI18n()
const auth = useAuthStore()
const puede = computed(() => auth.can('iglesia.configurar'))

// Atajos para añadir un fondo con su nombre en el idioma de quien configura
const PRESETS = ['diezmo', 'ofrenda', 'donacion', 'misiones', 'casas', 'escuelas', 'vmad'] as const

interface Fila { id: number; tipo: string | null; nombre: string; url: string; descripcion: string }

const cargando = ref(true)
const guardando = ref(false)
const mensaje = ref('')
const mensajeError = ref(false)
const copiado = ref(false)
const preset = ref('')
const filas = ref<Fila[]>([])
const claves = ref<string[]>([]) // fondos que ya están guardados
const config = ref<ConfigDar>({ ...CONFIG_POR_DEFECTO })
const logo = ref('')
let contador = 0

const nombreOriginal = (tipo: string) => ((TIPOS_DAR as readonly string[]).includes(tipo) ? t(`dar.${tipo}`) : tipo)

const hayErrores = computed(() =>
  filas.value.some(f => f.url.trim() && !urlDarValida(f.url.trim())) ||
  (logo.value.trim() !== '' && !urlDarValida(logo.value.trim())))

const enlacePublico = computed(() => (auth.iglesia?.slug && claves.value.length ? `${window.location.origin}/dar/${auth.iglesia.slug}` : ''))

async function cargar() {
  cargando.value = true
  const [fondos, conf] = await Promise.all([
    supabase.from('enlaces_dar').select('tipo, url, nombre, descripcion, orden').order('orden').order('tipo'),
    supabase.from('dar_config').select('plantilla, titulo, subtitulo, color_primario, color_acento, logo_url, calculadora, moneda').maybeSingle(),
  ])
  filas.value = (fondos.data ?? []).map(f => ({ id: ++contador, tipo: f.tipo, nombre: f.nombre ?? nombreOriginal(f.tipo), url: f.url, descripcion: f.descripcion ?? '' }))
  claves.value = (fondos.data ?? []).map(f => f.tipo)
  config.value = { ...CONFIG_POR_DEFECTO, ...(conf.data ?? {}) }
  logo.value = config.value.logo_url ?? ''
  cargando.value = false
}

function anadir() {
  const p = preset.value
  preset.value = ''
  if (!p || filas.value.length >= MAX_FONDOS) return
  const nombre = p === 'otro' ? '' : t(`dar.config.preset.${p}`)
  // Diezmo, ofrenda y donación conservan su clave original si está libre
  const clave = (TIPOS_DAR as readonly string[]).includes(p) && !filas.value.some(f => f.tipo === p) ? p : null
  filas.value = [...filas.value, { id: ++contador, tipo: clave, nombre, url: '', descripcion: '' }]
}

function mover(i: number, d: -1 | 1) {
  const j = i + d
  if (j < 0 || j >= filas.value.length) return
  const copia = [...filas.value]
  ;[copia[i], copia[j]] = [copia[j]!, copia[i]!]
  filas.value = copia
}

function quitar(i: number) { filas.value = filas.value.filter((_, k) => k !== i) }

function aviso(clave: string, error = false) { mensaje.value = clave; mensajeError.value = error }

async function guardar() {
  const iglesiaId = auth.iglesiaId
  if (!iglesiaId || hayErrores.value) return
  aviso('')
  // Sin enlace, un fondo no tiene botón: se quita. Con enlace, hace falta un nombre.
  const conEnlace = filas.value.filter(f => f.url.trim())
  if (conEnlace.some(f => !f.nombre.trim())) return aviso('dar.config.errorNombre', true)
  if (!colorValido(config.value.color_primario) || !colorValido(config.value.color_acento)) return aviso('dar.config.errorDatos', true)

  guardando.value = true
  const usadas = new Set(conEnlace.map(f => f.tipo).filter((x): x is string => !!x))
  const filasGuardar = conEnlace.map((f, i) => {
    const tipo = f.tipo ?? claveFondo(f.nombre, usadas)
    usadas.add(tipo)
    return { iglesia_id: iglesiaId, tipo, url: f.url.trim(), nombre: f.nombre.trim(), descripcion: f.descripcion.trim() || null, orden: i, activo: true }
  })
  const quedan = new Set(filasGuardar.map(f => f.tipo))
  const sobran = claves.value.filter(c => !quedan.has(c))

  const errores: unknown[] = []
  // Primero se borra lo quitado: con 20 fondos, quitar uno y añadir otro superaría el tope si se guardara al revés
  if (sobran.length) errores.push((await supabase.from('enlaces_dar').delete().eq('iglesia_id', iglesiaId).in('tipo', sobran)).error)
  if (filasGuardar.length) errores.push((await supabase.from('enlaces_dar').upsert(filasGuardar, { onConflict: 'iglesia_id,tipo' })).error)
  errores.push((await supabase.from('dar_config').upsert({
    iglesia_id: iglesiaId, plantilla: config.value.plantilla, titulo: config.value.titulo?.trim() || null, subtitulo: config.value.subtitulo?.trim() || null,
    color_primario: config.value.color_primario, color_acento: config.value.color_acento, logo_url: logo.value.trim() || null,
    calculadora: config.value.calculadora, moneda: config.value.moneda, updated_at: new Date().toISOString(),
  }, { onConflict: 'iglesia_id' })).error)
  guardando.value = false

  if (errores.some(Boolean)) { aviso('configuracion.errorGuardar', true); await cargar(); return }
  aviso('configuracion.guardado')
  await cargar()
}

async function copiarEnlace() {
  try { await navigator.clipboard.writeText(enlacePublico.value); copiado.value = true; setTimeout(() => { copiado.value = false }, 2000) } catch { /* se puede copiar a mano */ }
}

onMounted(cargar)
</script>
