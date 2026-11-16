<template>
  <div class="space-y-6">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.iglesias.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('plataformaPanel.iglesias.subtitulo') }}</p>
      </div>
      <div class="flex items-center gap-4 flex-wrap">
        <InterruptorDemo />
        <RouterLink to="/plataforma/nueva-iglesia" class="btn-primary inline-flex items-center gap-2" data-test="nueva-iglesia"><Plus class="w-4 h-4" aria-hidden="true" /> {{ t('plataforma.nueva') }}</RouterLink>
      </div>
    </div>

    <div v-if="pm.cargando && !pm.cargada" class="py-12 text-center text-gray-500 text-sm">{{ t('plataforma.cargando') }}</div>
    <TablaInquilinos v-else :titulo="t('plataformaPanel.iglesias.tabla')" :inquilinos="inquilinos" :acciones="acciones"
      :busqueda-inicial="busqueda" :etiqueta-nombre="t('plataformaPanel.iglesias.columna')" @accion="alAccion" />

    <NuevaIglesiaModal v-if="route.meta.abrirNueva" @cerrar="router.replace({ name: 'pm-iglesias' })" />
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { Plus } from '@lucide/vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import TablaInquilinos from '@/panel-maestro/TablaInquilinos.vue'
import type { AccionInquilino, Inquilino } from '@/panel-maestro/tipos'
import { usePlataformaStore } from '@/stores/plataforma'
import { aInquilino } from './adaptador'
import NuevaIglesiaModal from './NuevaIglesiaModal.vue'
import InterruptorDemo from './InterruptorDemo.vue'

const { t, locale } = useI18n()
const pm = usePlataformaStore()
const route = useRoute()
const router = useRouter()

onMounted(() => { void pm.asegurarCargada() })

const fecha = (iso: string) => new Date(iso).toLocaleDateString(locale.value)
const catalogo = computed(() => ({ planes: pm.planes, modulos: pm.modulos, planModulos: pm.planModulos }))
const inquilinos = computed(() => pm.visibles.map(ig => aInquilino(ig, catalogo.value, t as any, fecha)))
const busqueda = computed(() => typeof route.query.q === 'string' ? route.query.q : '')

// Acciones por estado, como en la referencia: gestionar siempre; convertir una prueba; activar una iglesia en alta o en receso
function acciones(i: Inquilino): AccionInquilino[] {
  const lista: AccionInquilino[] = [{ clave: 'gestionar', etiqueta: t('plataformaPanel.accion.gestionar'), ruta: `/plataforma/iglesias/${i.id}` }]
  if (i.estado === 'prueba') lista.push({ clave: 'convertir', etiqueta: t('plataformaPanel.accion.convertir') })
  if (i.estado === 'onboarding' || i.estado === 'receso') lista.push({ clave: 'activar', etiqueta: t('plataformaPanel.accion.activar') })
  return lista
}

function alAccion(clave: string, i: Inquilino) {
  if (clave !== 'convertir' && clave !== 'activar') return
  const etapa = 'activa'
  const nombre = t('plataforma.etapa.' + etapa)
  if (!window.confirm(t('plataforma.confirmarEtapa', { iglesia: i.nombre, etapa: nombre }))) return
  void pm.ejecutar({ accion: 'etapa', iglesia_id: i.id, etapa }, () => t('plataforma.etapaCambiada', { iglesia: i.nombre, etapa: nombre }))
}
</script>
