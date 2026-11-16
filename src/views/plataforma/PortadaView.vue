<template>
  <div class="space-y-6">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.portada.titulo') }}</h1>
        <p class="text-gray-600 text-sm mt-0.5" data-test="resumen-linea">{{ t('plataformaPanel.portada.linea', { activas: resumen.activas, prueba: resumen.prueba, miembros: resumen.miembros.toLocaleString(locale) }) }}</p>
      </div>
      <RouterLink to="/plataforma/nueva-iglesia" class="btn-primary inline-flex items-center gap-2"><Plus class="w-4 h-4" aria-hidden="true" /> {{ t('plataforma.nueva') }}</RouterLink>
    </div>

    <div v-if="pm.cargando && !pm.cargada" class="py-12 text-center text-gray-500 text-sm">{{ t('plataforma.cargando') }}</div>
    <template v-else>
      <section :aria-label="t('plataformaPanel.portada.kpis')" class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <KpiTarjeta v-for="k in kpis" :key="k.clave" :kpi="k" />
      </section>

      <section v-if="alertas.length" role="status" class="card border-red-200 bg-red-50" data-test="alertas">
        <h2 class="text-base font-semibold text-red-800">{{ t('plataformaPanel.portada.alertas') }}</h2>
        <ul class="mt-2 space-y-1 text-sm">
          <li v-for="a in alertas" :key="a.clave"><RouterLink :to="a.ruta" class="text-red-800 underline">{{ a.texto }}</RouterLink></li>
        </ul>
      </section>

      <TablaInquilinos :titulo="t('plataformaPanel.iglesias.tabla')" :inquilinos="inquilinos" :acciones="acciones" id="portada" :etiqueta-nombre="t('plataformaPanel.iglesias.columna')">
        <template #cabecera><RouterLink to="/plataforma/iglesias" class="text-sm text-adn-verde hover:underline">{{ t('plataformaPanel.portada.verTodas') }}</RouterLink></template>
      </TablaInquilinos>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { Plus } from '@lucide/vue'
import { useI18n } from 'vue-i18n'
import KpiTarjeta from '@/panel-maestro/KpiTarjeta.vue'
import TablaInquilinos from '@/panel-maestro/TablaInquilinos.vue'
import type { AccionInquilino, Inquilino } from '@/panel-maestro/tipos'
import { usePlataformaStore } from '@/stores/plataforma'
import { aInquilino, alertasGlobales, kpisDe, resumir } from './adaptador'

const { t, locale } = useI18n()
const pm = usePlataformaStore()
onMounted(() => { void pm.asegurarCargada() })

const fecha = (iso: string) => new Date(iso).toLocaleDateString(locale.value)
const catalogo = computed(() => ({ planes: pm.planes, modulos: pm.modulos, planModulos: pm.planModulos }))
const resumen = computed(() => resumir(pm.iglesias))
const alertas = computed(() => alertasGlobales(pm.iglesias, pm.purga, t as any))
const kpis = computed(() => kpisDe(resumen.value, alertas.value, t as any, n => n.toLocaleString(locale.value)))
// La portada enseña las iglesias más recientes; la lista completa está en Iglesias
const inquilinos = computed(() => [...pm.iglesias]
  .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
  .slice(0, 8).map(ig => aInquilino(ig, catalogo.value, t as any, fecha)))
const acciones = (i: Inquilino): AccionInquilino[] => [{ clave: 'gestionar', etiqueta: t('plataformaPanel.accion.gestionar'), ruta: `/plataforma/iglesias/${i.id}` }]
</script>
