<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.pruebas.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('plataformaPanel.pruebas.subtitulo', { n: DIAS_POR_VENCER }) }}</p>
    </div>
    <div v-if="pm.cargando && !pm.cargada" class="py-12 text-center text-gray-500 text-sm">{{ t('plataforma.cargando') }}</div>
    <p v-else-if="!filas.length" class="card text-sm text-gray-500" data-test="sin-pruebas">{{ t('plataformaPanel.pruebas.vacio') }}</p>
    <section v-else class="card" aria-labelledby="pr-tabla">
      <h2 id="pr-tabla" class="sr-only">{{ t('plataformaPanel.pruebas.titulo') }}</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm" data-test="tabla-pruebas">
          <thead class="text-left text-xs text-gray-500 border-b border-gray-100"><tr>
            <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataformaPanel.iglesias.columna') }}</th>
            <th scope="col" class="py-2 pr-3 font-medium">{{ t('panelMaestro.tabla.columna.plan') }}</th>
            <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataformaPanel.pruebas.vence') }}</th>
            <th scope="col" class="py-2 pr-3 font-medium text-right">{{ t('panelMaestro.tabla.columna.miembros') }}</th>
            <th scope="col" class="py-2 font-medium text-right">{{ t('panelMaestro.tabla.columna.acciones') }}</th></tr></thead>
          <tbody class="divide-y divide-gray-50">
            <tr v-for="f in filas" :key="f.ig.id" :data-inquilino="f.ig.id">
              <td class="py-3 pr-3"><p class="font-medium text-gray-900">{{ f.ig.nombre }}</p><p class="text-xs text-gray-400">{{ f.ig.slug }}</p></td>
              <td class="py-3 pr-3">{{ nombrePlan(f.ig.plan) }}</td>
              <td class="py-3 pr-3"><span :class="f.urgente ? 'text-red-700 font-medium' : 'text-gray-700'">{{ f.texto }}</span></td>
              <td class="py-3 pr-3 text-right tabular-nums">{{ (f.ig.miembros ?? 0).toLocaleString(locale) }}</td>
              <td class="py-3 text-right whitespace-nowrap">
                <RouterLink :to="`/plataforma/iglesias/${f.ig.id}`" class="text-xs px-2 py-1 text-adn-verde hover:underline">{{ t('plataformaPanel.accion.gestionar') }}<span class="sr-only"> {{ f.ig.nombre }}</span></RouterLink>
                <button type="button" class="text-xs px-2 py-1 text-adn-verde hover:underline" @click="convertir(f.ig)">{{ t('plataformaPanel.accion.convertir') }}<span class="sr-only"> {{ f.ig.nombre }}</span></button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { usePlataformaStore } from '@/stores/plataforma'
import { DIAS_POR_VENCER, detalleDeEstado, diasDePrueba, etapaDe } from './adaptador'

const { t, locale } = useI18n()
const pm = usePlataformaStore()
onMounted(() => { void pm.asegurarCargada() })

const nombrePlan = (clave: string) => pm.planes.find(p => p.clave === clave)?.nombre ?? clave
// Las pruebas de la lista que se ve (respeta «Incluir demostraciones») por orden de vencimiento: las que vencen antes, primero
const filas = computed(() => [...pm.visibles]
  .filter(i => etapaDe(i) === 'prueba')
  .sort((a, b) => (diasDePrueba(a) ?? Infinity) - (diasDePrueba(b) ?? Infinity))
  .map(ig => {
    const d = detalleDeEstado(ig, t as any, iso => new Date(iso).toLocaleDateString(locale.value))
    return { ig, texto: d.texto ?? t('plataformaPanel.pruebas.sinFecha'), urgente: !!d.urgente }
  }))

function convertir(ig: any) {
  const nombre = t('plataforma.etapa.activa')
  if (!window.confirm(t('plataforma.confirmarEtapa', { iglesia: ig.nombre, etapa: nombre }))) return
  void pm.ejecutar({ accion: 'etapa', iglesia_id: ig.id, etapa: 'activa' }, () => t('plataforma.etapaCambiada', { iglesia: ig.nombre, etapa: nombre }))
}
</script>
