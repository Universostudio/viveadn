<template>
  <div :style="variables" class="min-h-screen bg-gray-50 text-gray-900">
    <p v-if="estado === 'cargando'" class="text-center text-gray-500 text-sm pt-24" role="status">{{ t('comun.cargando') }}</p>

    <div v-else-if="estado === 'noDisponible'" class="max-w-md mx-auto pt-24 px-4 text-center space-y-3">
      <TriangleAlert class="w-10 h-10 mx-auto text-amber-500" aria-hidden="true" />
      <p class="text-gray-700 font-medium">{{ t('dar.paginaNoDisponible') }}</p>
    </div>

    <template v-else>
      <!-- Estilo clásico: logo, banda de color con el título y calculadora a la vista -->
      <template v-if="config.plantilla === 'clasica'">
        <header class="bg-white border-b border-gray-100 py-5 text-center">
          <img v-if="logoVisible" :src="config.logo_url!" alt="" referrerpolicy="no-referrer" @error="logoFalla = true" class="h-14 mx-auto object-contain" />
          <p v-else class="font-bold text-lg" style="color: var(--dar-primario)">{{ iglesia }}</p>
        </header>
        <section class="px-4 py-12 text-center" style="background: linear-gradient(135deg, var(--dar-primario), color-mix(in srgb, var(--dar-primario) 70%, black)); color: var(--dar-primario-texto)">
          <h1 class="text-3xl sm:text-4xl font-bold max-w-2xl mx-auto" style="color: var(--dar-acento)">{{ titulo }}</h1>
          <p class="mt-3 max-w-xl mx-auto opacity-90">{{ subtitulo }}</p>
        </section>
      </template>

      <!-- Estilo «ingreso de un día»: tarjeta de color con el botón de la calculadora -->
      <template v-else>
        <section class="px-4 pt-10">
          <div class="max-w-xl mx-auto rounded-2xl px-6 py-10 text-center shadow-lg"
            style="background: linear-gradient(135deg, var(--dar-acento), var(--dar-primario)); color: var(--dar-mezcla-texto)">
            <img v-if="logoVisible" :src="config.logo_url!" alt="" referrerpolicy="no-referrer" @error="logoFalla = true" class="h-12 mx-auto mb-4 object-contain" />
            <p v-else class="text-sm font-semibold opacity-90 mb-2">{{ iglesia }}</p>
            <h1 class="text-2xl sm:text-3xl font-bold">{{ titulo }}</h1>
            <p class="mt-3 opacity-95">{{ subtitulo }}</p>
            <button v-if="modo !== 'ninguna'" type="button" @click="calculando = true"
              class="mt-6 px-8 py-3 rounded-full bg-white font-bold shadow-md hover:shadow-lg transition-shadow" style="color: var(--dar-primario)">
              {{ t('dar.pagina.calcula') }}
            </button>
          </div>
        </section>
      </template>

      <main class="max-w-xl mx-auto px-4 py-8 space-y-6">
        <section v-if="config.plantilla === 'clasica' && modo !== 'ninguna'" class="bg-white rounded-2xl shadow-sm p-6">
          <h2 class="text-lg font-bold mb-4">{{ t('dar.pagina.calculadoraTitulo') }}</h2>
          <CalculadoraAporte :modo="modo" :moneda="config.moneda" id-base="calc" @usar="usar" />
        </section>

        <section class="bg-white rounded-2xl shadow-sm p-6 space-y-5">
          <h2 class="text-lg font-bold">{{ t('dar.pagina.completa') }}</h2>

          <div class="rounded-xl bg-gray-50 p-4 flex items-center justify-between gap-3">
            <div>
              <p class="text-xs text-gray-500">{{ t('dar.pagina.tuAporte') }}</p>
              <p class="text-2xl font-bold">{{ monto ? formatoMoneda(monto, config.moneda, locale) : '—' }}</p>
            </div>
            <button v-if="monto" type="button" @click="copiarMonto" class="text-sm font-medium underline-offset-2 hover:underline" style="color: var(--dar-primario)">
              {{ copiado ? t('dar.copiado') : t('dar.pagina.copiarCantidad') }}
            </button>
          </div>
          <p v-if="monto" class="text-xs text-gray-500 -mt-2">{{ t('dar.pagina.indicaEnSitio') }}</p>

          <fieldset>
            <legend class="text-sm font-medium text-gray-700 mb-2">{{ t('dar.pagina.elegirFondo') }}</legend>
            <div class="space-y-2">
              <label v-for="f in fondos" :key="f.tipo"
                :class="['flex items-start gap-3 rounded-xl border p-3 cursor-pointer transition-colors', elegido === f.tipo ? 'border-[var(--dar-primario)] bg-gray-50' : 'border-gray-200 hover:border-gray-300']">
                <input v-model="elegido" type="radio" name="fondo" :value="f.tipo" class="mt-1" style="accent-color: var(--dar-primario)" />
                <span>
                  <span class="block font-medium">{{ nombreDe(f) }}</span>
                  <span v-if="f.descripcion" class="block text-sm text-gray-500">{{ f.descripcion }}</span>
                </span>
              </label>
            </div>
          </fieldset>

          <a v-if="fondoElegido" :href="fondoElegido.url" target="_blank" rel="noopener noreferrer"
            class="flex items-center justify-center gap-2 w-full py-3.5 rounded-xl font-bold text-base shadow-sm hover:shadow-md transition-shadow"
            style="background-color: var(--dar-acento); color: var(--dar-acento-texto)">
            {{ t('dar.pagina.continuar', { fondo: nombreDe(fondoElegido) }) }} <ExternalLink class="w-4 h-4" aria-hidden="true" />
            <span class="sr-only">{{ t('dar.seAbreEnOtraPagina') }}</span>
          </a>
          <p class="text-xs text-gray-400 text-center">{{ t('dar.paginaAviso') }}</p>
        </section>

        <SelectorIdioma id="selector-idioma-dar" class="max-w-xs mx-auto" />
        <p class="text-center text-xs text-gray-400">© 2026 ViveADN</p>
      </main>

      <!-- Calculadora en ventana (estilo «ingreso de un día») -->
      <div v-if="calculando" class="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50" @click.self="calculando = false" role="dialog" aria-modal="true" :aria-label="t('dar.pagina.calculadoraTitulo')">
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 max-h-[90vh] overflow-y-auto">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-bold">{{ t('dar.pagina.calculadoraTitulo') }}</h2>
            <button type="button" @click="calculando = false" class="text-gray-400 hover:text-gray-600" :aria-label="t('comun.cerrar')"><X class="w-5 h-5" aria-hidden="true" /></button>
          </div>
          <CalculadoraAporte :modo="modo === 'diezmo' ? 'diezmo' : 'dia'" :moneda="config.moneda" id-base="calc-modal" @usar="usar" />
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ExternalLink, TriangleAlert, X } from '@lucide/vue'
import SelectorIdioma from '@/components/SelectorIdioma.vue'
import CalculadoraAporte from '@/components/CalculadoraAporte.vue'
import { supabase } from '@/lib/supabase'
import { CONFIG_POR_DEFECTO, colorValido, colorTextoSobre, formatoMoneda, mezclarColores, urlDarValida } from '@/lib/dar'
import type { ConfigDar, Fondo } from '@/lib/dar'

const route = useRoute()
const { t, locale } = useI18n()

const estado = ref<'cargando' | 'lista' | 'noDisponible'>('cargando')
const iglesia = ref('')
const config = ref<ConfigDar>({ ...CONFIG_POR_DEFECTO })
const fondos = ref<Fondo[]>([])
const elegido = ref('')
const monto = ref(0)
const calculando = ref(false)
const copiado = ref(false)
const logoFalla = ref(false)

const modo = computed(() => config.value.calculadora)
const fondoElegido = computed(() => fondos.value.find(f => f.tipo === elegido.value) ?? null)
const logoVisible = computed(() => !!config.value.logo_url && !logoFalla.value)
const titulo = computed(() => config.value.titulo || t(config.value.plantilla === 'dia' ? 'dar.pagina.tituloDia' : 'dar.pagina.tituloClasica'))
const subtitulo = computed(() => config.value.subtitulo || t(config.value.plantilla === 'dia' ? 'dar.pagina.subtituloDia' : 'dar.pagina.subtituloClasica', { iglesia: iglesia.value }))

// Los colores solo llegan a la página si tienen forma de color; cada texto se calcula para que se lea sobre su fondo
const variables = computed(() => {
  const p = colorValido(config.value.color_primario) ? config.value.color_primario : CONFIG_POR_DEFECTO.color_primario
  const a = colorValido(config.value.color_acento) ? config.value.color_acento : CONFIG_POR_DEFECTO.color_acento
  return {
    '--dar-primario': p, '--dar-acento': a,
    '--dar-primario-texto': colorTextoSobre(p), '--dar-acento-texto': colorTextoSobre(a),
    // El degradado va del acento al primario: el texto se elige sobre su color intermedio
    '--dar-mezcla-texto': colorTextoSobre(mezclarColores(a, p)),
  }
})

const TIPOS_CON_TRADUCCION = ['diezmo', 'ofrenda', 'donacion']
const nombreDe = (f: Fondo) => f.nombre || (TIPOS_CON_TRADUCCION.includes(f.tipo) ? t(`dar.${f.tipo}`) : f.tipo)

function usar(m: number) {
  monto.value = m
  calculando.value = false
}

async function copiarMonto() {
  try { await navigator.clipboard.writeText(String(monto.value).replace('.', ',')); copiado.value = true; setTimeout(() => { copiado.value = false }, 2000) } catch { /* se puede copiar a mano */ }
}

onMounted(async () => {
  const slug = String(route.params.slug ?? '')
  const { data, error } = await supabase.functions.invoke('dar-publico', { body: { slug } })
  // La versión anterior de la función solo devolvía "enlaces"; se sigue entendiendo
  const lista: Fondo[] = (data?.fondos ?? (data?.enlaces ?? []).map((e: { tipo: string; url: string }, i: number) => ({ ...e, nombre: null, descripcion: null, orden: i })))
    .filter((f: Fondo) => urlDarValida(f.url))
  if (error || !data?.iglesia || !lista.length) { estado.value = 'noDisponible'; return }
  iglesia.value = data.iglesia
  config.value = { ...CONFIG_POR_DEFECTO, ...(data.config ?? {}) }
  fondos.value = lista
  elegido.value = lista[0]!.tipo
  estado.value = 'lista'
})
</script>
