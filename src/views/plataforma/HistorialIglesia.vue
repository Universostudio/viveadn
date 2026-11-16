<template>
  <section class="card" aria-labelledby="g-hist" data-test="historial">
    <h2 id="g-hist" class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.gestionar.historial') }}</h2>
    <p v-if="estado === 'cargando'" class="text-sm text-gray-500 mt-2">{{ t('plataforma.cargando') }}</p>
    <p v-else-if="estado === 'error'" role="status" class="text-sm text-amber-800 mt-2">{{ t('plataformaPanel.gestionar.historialNoDisponible') }}</p>
    <p v-else-if="!eventos.length" class="text-sm text-gray-500 mt-2">{{ t('plataformaPanel.gestionar.historialVacio') }}</p>
    <ul v-else class="mt-3 divide-y divide-gray-50">
      <li v-for="(e, i) in eventos" :key="i" class="py-2 flex items-start gap-3 text-sm">
        <span class="flex-1 text-gray-700">{{ textoDeAccion(e.accion) }}</span>
        <time :datetime="e.fecha" class="text-xs text-gray-500 flex-shrink-0">{{ new Date(e.fecha).toLocaleString(locale) }}</time>
      </li>
    </ul>
  </section>
</template>

<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { usePlataformaStore } from '@/stores/plataforma'
import { textoDeAccion as texto } from './acciones'

const props = defineProps<{ iglesiaId: string }>()
const { t, te, locale } = useI18n()
const pm = usePlataformaStore()
const eventos = ref<{ accion: string; fecha: string }[]>([])
const estado = ref<'cargando' | 'ok' | 'error'>('cargando')

const textoDeAccion = (accion: string) => texto(accion, t as any, te as any)

async function cargar() {
  estado.value = 'cargando'
  try {
    const d = await pm.llamar({ accion: 'detalle', iglesia_id: props.iglesiaId })
    eventos.value = Array.isArray(d?.historial) ? d.historial.map((e: any) => ({ accion: String(e.accion), fecha: String(e.fecha) })) : []
    estado.value = 'ok'
  } catch { eventos.value = []; estado.value = 'error' }
}
onMounted(cargar)
watch(() => props.iglesiaId, cargar)
</script>
