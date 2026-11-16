<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.sistema.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('plataformaPanel.sistema.subtitulo') }}</p>
    </div>

    <section class="card space-y-3" :aria-label="t('plataforma.purga.titulo')" data-test="purga-estado">
      <div class="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h2 class="text-base font-semibold text-gray-900">{{ t('plataforma.purga.titulo') }}</h2>
          <p class="text-sm text-gray-500 mt-0.5">{{ t('plataforma.purga.ayuda') }}</p>
        </div>
        <button type="button" @click="pm.cargarPurga()" class="btn-secondary text-sm">{{ t('plataforma.purga.reintentar') }}</button>
      </div>
      <p v-if="!pm.purga" role="status" class="text-sm px-4 py-3 rounded-lg border bg-amber-50 text-amber-800 border-amber-200">{{ t('plataforma.purga.noDisponible') }}</p>
      <template v-else>
        <p role="status" :class="['text-sm px-4 py-3 rounded-lg border font-medium', pm.purga.atrasada ? 'bg-red-50 text-red-700 border-red-200' : 'bg-green-50 text-green-700 border-green-200']">
          {{ pm.purga.atrasada ? t('plataforma.purga.atrasada') : t('plataforma.purga.sana') }}
        </p>
        <dl class="grid grid-cols-3 gap-3 text-center">
          <div><dd class="text-2xl font-bold text-gray-900">{{ pm.purga.en_borrado }}</dd><dt class="text-xs text-gray-500">{{ t('plataforma.purga.enBorrado') }}</dt></div>
          <div><dd class="text-2xl font-bold text-gray-900">{{ pm.purga.vencidas }}</dd><dt class="text-xs text-gray-500">{{ t('plataforma.purga.vencidas') }}</dt></div>
          <div><dd class="text-2xl font-bold text-gray-900">{{ pm.purga.horas_mas_atrasada }}</dd><dt class="text-xs text-gray-500">{{ t('plataforma.purga.horas') }}</dt></div>
        </dl>
      </template>
    </section>

    <section class="card space-y-3" aria-labelledby="si-envio" data-test="envio-estado">
      <div>
        <h2 id="si-envio" class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.sistema.envio') }}</h2>
        <p class="text-sm text-gray-500 mt-0.5">{{ t('plataformaPanel.sistema.envioAyuda') }}</p>
      </div>
      <p v-if="!pm.sistema?.envio" role="status" class="text-sm px-4 py-3 rounded-lg border bg-amber-50 text-amber-800 border-amber-200">{{ t('plataformaPanel.sistema.noDisponible') }}</p>
      <template v-else>
        <p :class="['inline-block text-xs font-medium px-2 py-0.5 rounded-full', pm.sistema.envio.activo ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-700']">
          {{ pm.sistema.envio.activo ? t('plataformaPanel.salud.envioActivo') : t('plataformaPanel.salud.envioApagado') }}
        </p>
        <p class="text-sm text-gray-700">{{ t('plataformaPanel.sistema.envioHoy', { n: pm.sistema.envio.hoy }) }} · {{ t('plataformaPanel.sistema.envioTope', { n: pm.sistema.envio.tope_global }) }}</p>
      </template>
    </section>

    <section class="card space-y-3" aria-labelledby="si-libro" data-test="libro-purgas">
      <div>
        <h2 id="si-libro" class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.sistema.libro') }}</h2>
        <p class="text-sm text-gray-500 mt-0.5">{{ t('plataformaPanel.sistema.libroAyuda') }}</p>
      </div>
      <p v-if="!pm.sistema || pm.sistema.libro === null" role="status" class="text-sm px-4 py-3 rounded-lg border bg-amber-50 text-amber-800 border-amber-200">{{ t('plataformaPanel.sistema.noDisponible') }}</p>
      <p v-else-if="!pm.sistema.libro.length" class="text-sm text-gray-400">{{ t('plataformaPanel.sistema.libroVacio') }}</p>
      <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
          <caption class="sr-only">{{ t('plataformaPanel.sistema.libro') }}</caption>
          <thead class="text-left text-xs text-gray-500 border-b border-gray-100"><tr>
            <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataformaPanel.sistema.libroColumnaFecha') }}</th>
            <th scope="col" class="py-2 font-medium">{{ t('plataformaPanel.sistema.libroColumnaId') }}</th></tr></thead>
          <tbody class="divide-y divide-gray-50">
            <tr v-for="f in pm.sistema.libro" :key="`${f.iglesia}-${f.purgada_en}`"><td class="py-2 pr-3 text-gray-700 whitespace-nowrap">{{ new Date(f.purgada_en).toLocaleString(locale) }}</td><td class="py-2 font-mono text-xs text-gray-600 break-all">{{ f.iglesia }}</td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <section data-test="auditoria-plataforma">
      <PanelActividad id="sistema" :titulo="t('plataformaPanel.sistema.auditoria')" :eventos="eventos" :vacio="pm.actividadEstado === 'no' ? t('plataformaPanel.sistema.noDisponible') : t('plataformaPanel.sistema.auditoriaVacia')" />
      <p class="text-xs text-gray-500 mt-2">{{ t('plataformaPanel.sistema.auditoriaAyuda') }}</p>
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import PanelActividad from '@/panel-maestro/PanelActividad.vue'
import { usePlataformaStore } from '@/stores/plataforma'
import { eventosParaPanel } from './adaptador'

const { t, te, locale } = useI18n()
const pm = usePlataformaStore()
onMounted(() => { void pm.asegurarCargada(); void pm.cargarSistema(); void pm.cargarActividad(30) })
const eventos = computed(() => eventosParaPanel(pm.actividad, t as any, te as any))
</script>
