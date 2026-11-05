<template>
  <div class="space-y-4">
    <div role="tablist" :aria-label="t('dar.pagina.calculadoraTitulo')" class="flex border-b border-gray-200">
      <button v-for="p in PERIODOS" :key="p" type="button" role="tab" :aria-selected="periodo === p" @click="cambiar(p)"
        :class="['flex-1 px-2 py-2.5 text-xs sm:text-sm font-medium border-b-2 -mb-px transition-colors', periodo === p ? 'border-[var(--dar-acento)] text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-700']">
        {{ t(`dar.pagina.tabs.${p}`) }}
      </button>
    </div>

    <div role="tabpanel">
      <label :for="`${idBase}-importe`" class="block text-sm font-medium text-gray-700 mb-1">
        {{ t(periodo === 'personalizado' ? 'dar.pagina.cantidadPersonalizada' : `dar.pagina.ingreso.${periodo}`) }}
      </label>
      <div class="relative">
        <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 font-semibold" aria-hidden="true">{{ simbolo }}</span>
        <input :id="`${idBase}-importe`" v-model="texto" inputmode="decimal" autocomplete="off" placeholder="0"
          class="w-full pl-9 pr-3 py-3 border border-gray-200 rounded-lg text-lg focus:outline-none focus:ring-2 focus:ring-[var(--dar-acento)]" />
      </div>
      <p v-if="texto.trim() && importe === null" role="alert" class="text-xs text-red-600 mt-1">{{ t('dar.pagina.importeInvalido') }}</p>
    </div>

    <div class="rounded-xl p-4 text-center" style="background-color: color-mix(in srgb, var(--dar-acento) 14%, white)">
      <p class="text-sm text-gray-600">{{ t(modo === 'diezmo' ? 'dar.pagina.resultadoDiezmo' : periodo === 'personalizado' ? 'dar.pagina.resultadoPersonalizado' : 'dar.pagina.resultadoDia') }}</p>
      <p class="text-3xl font-bold text-gray-900 mt-1" aria-live="polite">{{ formato }}</p>
    </div>

    <button type="button" :disabled="!aporte" @click="emit('usar', aporte)"
      class="w-full py-3 rounded-xl font-semibold transition-opacity disabled:opacity-40"
      style="background-color: var(--dar-primario); color: var(--dar-primario-texto)">
      {{ t('dar.pagina.usarCantidad') }}
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { PERIODOS, calcularAporte, formatoMoneda, leerImporte, simboloMoneda } from '@/lib/dar'
import type { Periodo } from '@/lib/dar'

// Calcula una cantidad sugerida. Los colores llegan por variables CSS (--dar-*) de la página que la contiene.
const props = defineProps<{ modo: 'dia' | 'diezmo'; moneda: string; idBase: string }>()
const emit = defineEmits<{ usar: [monto: number] }>()
const { t, locale } = useI18n()

const periodo = ref<Periodo>('anual')
const texto = ref('')
const importe = computed(() => leerImporte(texto.value))
const aporte = computed(() => (importe.value === null ? 0 : calcularAporte(importe.value, periodo.value, props.modo)))
const formato = computed(() => formatoMoneda(aporte.value, props.moneda, locale.value))
const simbolo = computed(() => simboloMoneda(props.moneda, locale.value))

function cambiar(p: Periodo) { periodo.value = p }
</script>
