<template>
  <div class="space-y-6" data-test="pm-reportes">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.reportes.titulo') }}</h1>
        <p class="text-gray-600 text-sm mt-0.5">{{ t('plataformaPanel.reportes.subtitulo') }}</p>
      </div>
      <InterruptorDemo />
    </div>

    <div v-if="pm.cargando && !pm.cargada" class="py-12 text-center text-gray-500 text-sm" role="status">{{ t('plataforma.cargando') }}</div>
    <template v-else>
      <!-- Personas -->
      <section class="card" aria-labelledby="r-personas" data-test="rep-personas">
        <h2 id="r-personas" class="text-base font-semibold text-gray-900 mb-3">{{ t('plataformaPanel.reportes.personas') }}</h2>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
          <div><p class="text-xs text-gray-500">{{ t('plataformaPanel.reportes.totalPersonas') }}</p><p class="text-2xl font-bold tabular-nums" data-test="rep-total-personas">{{ per.miembros.toLocaleString(locale) }}</p></div>
          <div><p class="text-xs text-gray-500">{{ t('plataformaPanel.reportes.cuentas') }}</p><p class="text-2xl font-bold tabular-nums">{{ per.usuarios.toLocaleString(locale) }}</p></div>
          <div><p class="text-xs text-gray-500">{{ t('plataformaPanel.reportes.iglesiasVivas') }}</p><p class="text-2xl font-bold tabular-nums">{{ per.iglesias }}</p></div>
          <div><p class="text-xs text-gray-500">{{ t('plataformaPanel.reportes.promedio') }}</p><p class="text-2xl font-bold tabular-nums" data-test="rep-promedio">{{ per.promedio === null ? t('plataformaPanel.reportes.sinDato') : per.promedio.toLocaleString(locale) }}</p></div>
        </div>
      </section>

      <!-- Crecimiento -->
      <section class="card" aria-labelledby="r-crec" data-test="rep-crecimiento">
        <h2 id="r-crec" class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.reportes.crecimiento') }}</h2>
        <p class="text-xs text-gray-500 mb-3">{{ t('plataformaPanel.reportes.crecimientoNota') }}</p>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="text-left text-xs text-gray-500 border-b border-gray-100"><tr>
              <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataformaPanel.reportes.mes') }}</th>
              <th scope="col" class="py-2 px-3 font-medium text-right">{{ t('plataformaPanel.reportes.altas') }}</th>
              <th scope="col" class="py-2 px-3 font-medium text-right">{{ t('plataformaPanel.reportes.bajas') }}</th>
              <th scope="col" class="py-2 pl-3 font-medium">{{ t('plataformaPanel.reportes.vivas') }}</th></tr></thead>
            <tbody class="divide-y divide-gray-50">
              <tr v-for="m in crec" :key="m.mes" :data-mes="m.mes">
                <th scope="row" class="py-1.5 pr-3 text-left font-normal text-gray-700">{{ m.mes }}</th>
                <td class="py-1.5 px-3 text-right tabular-nums" data-campo="altas">{{ m.altas }}</td>
                <td class="py-1.5 px-3 text-right tabular-nums" data-campo="bajas">{{ m.bajas }}</td>
                <td class="py-1.5 pl-3"><div class="flex items-center gap-2"><div class="h-2 rounded bg-adn-verde" :style="{ width: ancho(m.acumuladas) }" aria-hidden="true"></div><span class="tabular-nums text-gray-800" data-campo="vivas">{{ m.acumuladas }}</span></div></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Distribución -->
      <section class="card" aria-labelledby="r-dist" data-test="rep-distribucion">
        <h2 id="r-dist" class="text-base font-semibold text-gray-900 mb-3">{{ t('plataformaPanel.reportes.distribucion') }}</h2>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="text-left text-xs text-gray-500 border-b border-gray-100"><tr>
              <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataformaPanel.facturacion.plan') }}</th>
              <th v-for="e in dist.etapas" :key="e" scope="col" class="py-2 px-3 font-medium text-right">{{ t('plataformaPanel.soporte.etapas.' + e) }}</th>
              <th scope="col" class="py-2 pl-3 font-medium text-right">{{ t('plataformaPanel.reportes.total') }}</th></tr></thead>
            <tbody class="divide-y divide-gray-50">
              <tr v-for="f in dist.filas" :key="f.plan" :data-plan="f.plan">
                <th scope="row" class="py-1.5 pr-3 text-left font-medium text-gray-900">{{ nombrePlan(f.plan) }}</th>
                <td v-for="e in dist.etapas" :key="e" class="py-1.5 px-3 text-right tabular-nums" :data-etapa="e">{{ f.porEtapa[e] }}</td>
                <td class="py-1.5 pl-3 text-right tabular-nums font-semibold" data-campo="total">{{ f.total }}</td>
              </tr>
              <tr class="font-semibold"><th scope="row" class="py-1.5 pr-3 text-left">{{ t('plataformaPanel.reportes.total') }}</th>
                <td v-for="e in dist.etapas" :key="e" class="py-1.5 px-3 text-right tabular-nums">{{ dist.totalPorEtapa[e] }}</td>
                <td class="py-1.5 pl-3 text-right tabular-nums" data-test="rep-dist-total">{{ dist.total }}</td></tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Módulos -->
      <section class="card" aria-labelledby="r-mod" data-test="rep-modulos">
        <h2 id="r-mod" class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.reportes.modulos') }}</h2>
        <p class="text-xs text-gray-500 mb-3">{{ t('plataformaPanel.reportes.modulosNota') }}</p>
        <ul class="divide-y divide-gray-50 text-sm">
          <li v-for="m in mods" :key="m.clave" class="py-1.5 flex items-center justify-between gap-3" :data-modulo="m.clave">
            <span class="text-gray-900">{{ m.nombre }}</span>
            <span class="tabular-nums text-gray-700">{{ m.conAcceso }} / {{ m.deTotal }}<span v-if="m.porComplemento" class="text-xs text-gray-500"> · {{ t('plataformaPanel.reportes.porComplemento', { n: m.porComplemento }) }}</span></span>
          </li>
        </ul>
      </section>

      <TarjetaSinConectar id="uso-real" :titulo="t('plataformaPanel.reportes.usoReal')" :falta="t('plataformaPanel.reportes.faltaUsoReal')" />
      <TarjetaSinConectar id="retencion" :titulo="t('plataformaPanel.reportes.retencion')" :falta="t('plataformaPanel.reportes.faltaRetencion')" />
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import TarjetaSinConectar from '@/panel-maestro/TarjetaSinConectar.vue'
import InterruptorDemo from './InterruptorDemo.vue'
import { usePlataformaStore } from '@/stores/plataforma'
import { crecimiento, distribucion, modulos, personas } from './reportes'

const { t, locale } = useI18n()
const pm = usePlataformaStore()
onMounted(() => { void pm.asegurarCargada() })
const lista = computed(() => pm.visibles as any[])
const crec = computed(() => crecimiento(lista.value))
const dist = computed(() => distribucion(lista.value, pm.planes))
const per = computed(() => personas(lista.value))
const mods = computed(() => modulos(lista.value, { planes: pm.planes, modulos: pm.modulos, planModulos: pm.planModulos }))
const maximo = computed(() => Math.max(1, ...crec.value.map(m => m.acumuladas)))
const ancho = (n: number) => `${Math.round((n / maximo.value) * 100)}%`
const nombrePlan = (clave: string) => pm.planes.find(p => p.clave === clave)?.nombre ?? clave
</script>
