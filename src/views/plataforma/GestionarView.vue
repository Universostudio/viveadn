<template>
  <div class="space-y-6">
    <nav :aria-label="t('plataformaPanel.gestionar.migas')" class="text-sm">
      <RouterLink to="/plataforma/iglesias" class="text-adn-verde hover:underline inline-flex items-center gap-1"><ArrowLeft class="w-4 h-4" aria-hidden="true" />{{ t('plataformaPanel.gestionar.volver') }}</RouterLink>
    </nav>

    <div v-if="pm.cargando && !pm.cargada" class="py-12 text-center text-gray-500 text-sm">{{ t('plataforma.cargando') }}</div>
    <p v-else-if="!ig" role="alert" class="card text-sm text-gray-600" data-test="no-existe">{{ t('plataformaPanel.gestionar.noExiste') }}</p>

    <template v-else>
      <header class="flex items-start justify-between gap-3 flex-wrap">
        <div class="min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <h1 class="text-2xl font-bold text-gray-900 truncate" data-test="nombre-iglesia">{{ ig.nombre }}</h1>
            <span v-if="ig.es_demo" class="text-xs bg-adn-arena text-adn-profundo px-2 py-0.5 rounded-full font-medium">{{ t('plataforma.demo') }}</span>
            <span :class="['text-xs px-2 py-0.5 rounded-full font-medium', ig.activa ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800']">{{ t('plataforma.etapa.' + etapa) }}</span>
          </div>
          <p class="text-sm text-gray-500 mt-0.5">{{ ig.slug }}<span v-if="ig.ciudad"> · {{ ig.ciudad }}</span><span v-if="ig.pais">, {{ ig.pais }}</span></p>
          <p v-if="detalle.texto" :class="['text-sm mt-1', detalle.urgente ? 'text-red-700 font-medium' : 'text-gray-500']">{{ detalle.texto }}</p>
        </div>
      </header>

      <!-- En qué estado está y qué significa, en lenguaje llano, con los botones que hay para ese estado -->
      <section class="card space-y-3" aria-labelledby="g-estado" data-test="estado-vida" :data-situacion="situacion">
        <h2 id="g-estado" class="text-base font-semibold text-gray-900">{{ t(`plataformaPanel.ciclo.${situacion}.titulo`) }}</h2>
        <p class="text-sm text-gray-700" data-test="estado-texto">{{ t(`plataformaPanel.ciclo.${situacion}.texto`, { fecha: fechaCorta(ig.borrado_programado_en ?? ig.prueba_hasta), n: dias ?? 0 }, dias ?? 0) }}</p>
        <div v-if="acciones.length" class="flex flex-wrap gap-2">
          <button v-for="a in acciones" :key="a.clave" type="button" :data-test="a.clave" :class="a.principal ? 'btn-primary text-sm' : 'btn-secondary text-sm'" @click="a.ejecutar()">{{ t(`plataformaPanel.ciclo.boton.${a.clave}`) }}</button>
        </div>
      </section>

      <!-- Conteos: nunca datos de personas -->
      <section :aria-label="t('plataformaPanel.gestionar.resumen')" class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div class="card"><p class="text-xs text-gray-500">{{ t('plataformaPanel.gestionar.miembros') }}</p><p class="text-2xl font-bold text-gray-900 mt-1">{{ (ig.miembros ?? 0).toLocaleString(locale) }}</p>
          <p v-if="limite" class="text-xs text-gray-500 mt-1">{{ t('plataforma.limite', limite) }}</p></div>
        <div class="card"><p class="text-xs text-gray-500">{{ t('plataformaPanel.gestionar.usuarios') }}</p><p class="text-2xl font-bold text-gray-900 mt-1">{{ (ig.usuarios ?? 0).toLocaleString(locale) }}</p></div>
        <div class="card"><p class="text-xs text-gray-500">{{ t('plataformaPanel.gestionar.sedes') }}</p><p class="text-2xl font-bold text-gray-900 mt-1">{{ numeroSedes }}</p></div>
        <div class="card"><p class="text-xs text-gray-500">{{ t('plataformaPanel.gestionar.alta') }}</p><p class="text-lg font-bold text-gray-900 mt-1">{{ new Date(ig.created_at).toLocaleDateString(locale) }}</p></div>
      </section>

      <section class="card space-y-3" aria-labelledby="g-plan">
        <h2 id="g-plan" class="text-base font-semibold text-gray-900">{{ t('plataforma.plan') }}</h2>
        <div class="flex flex-wrap items-end gap-4">
          <div>
            <label for="g-plan-sel" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.plan') }}</label>
            <select id="g-plan-sel" :value="ig.plan" @change="cambiarPlan(($event.target as HTMLSelectElement).value)" data-test="plan"
              class="text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option v-for="p in pm.planes" :key="p.clave" :value="p.clave">{{ p.nombre }}</option>
            </select>
          </div>
          <div>
            <label for="g-etapa-sel" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataformaPanel.gestionar.etapa') }}</label>
            <select id="g-etapa-sel" :value="ig.etapa" @change="cambiarEtapa($event.target as HTMLSelectElement)" data-test="etapa"
              class="text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option v-for="e in ETAPAS" :key="e" :value="e">{{ t('plataforma.etapa.' + e) }}</option>
            </select>
          </div>
        </div>
      </section>

      <section class="card space-y-3" aria-labelledby="g-red">
        <h2 id="g-red" class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.gestionar.red') }}</h2>
        <div class="flex flex-wrap items-end gap-3">
          <div>
            <label for="g-madre" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.red.madre') }}</label>
            <select id="g-madre" :value="ig.iglesia_madre_id ?? ''" :disabled="numeroSedes > 0" @change="vincular(($event.target as HTMLSelectElement).value || null, ig.red_acceso)"
              class="text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde disabled:bg-gray-50 disabled:text-gray-500">
              <option value="">{{ t('plataforma.red.independiente') }}</option>
              <option v-for="m in posiblesMadres" :key="m.id" :value="m.id">{{ m.nombre }}</option>
            </select>
          </div>
          <div v-if="ig.iglesia_madre_id">
            <label for="g-acceso" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.red.acceso') }}</label>
            <select id="g-acceso" :value="ig.red_acceso" @change="vincular(ig.iglesia_madre_id, ($event.target as HTMLSelectElement).value)"
              class="text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option value="resumen">{{ t('plataforma.red.resumen') }}</option>
              <option value="ninguno">{{ t('plataforma.red.ninguno') }}</option>
            </select>
          </div>
          <p v-if="numeroSedes > 0" class="text-xs text-gray-500 pb-2">{{ t('plataforma.red.conSedes', { n: numeroSedes }) }}</p>
        </div>
      </section>

      <section class="card space-y-3" aria-labelledby="g-comp">
        <h2 id="g-comp" class="text-base font-semibold text-gray-900">{{ t('plataforma.complementos') }}</h2>
        <div class="flex flex-wrap gap-2">
          <button v-for="m in complementos" :key="m.clave" type="button" @click="alternarModulo(m)" :disabled="m.delPlan"
            :aria-pressed="m.activo" :title="m.delPlan ? t('plataforma.incluidoEnPlan') : ''"
            :class="['text-xs px-3 py-2 rounded-full border transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde',
              m.delPlan ? 'bg-gray-50 text-gray-500 border-gray-100 cursor-default' : m.activo ? 'bg-adn-verde text-white border-adn-verde' : 'bg-white text-gray-700 border-gray-200 hover:border-adn-verde']">
            <span class="inline-flex items-center gap-1.5"><component :is="m.delPlan ? Check : m.activo ? CircleCheck : Circle" class="w-3.5 h-3.5" aria-hidden="true" />{{ m.nombre }}<span v-if="m.delPlan" class="sr-only"> ({{ t('plataforma.incluidoEnPlan') }})</span></span>
          </button>
        </div>
      </section>

      <section class="card space-y-3" aria-labelledby="g-datos">
        <h2 id="g-datos" class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.gestionar.datos') }}</h2>
        <p class="text-sm text-gray-600">{{ t('plataformaPanel.gestionar.datosAyuda') }}</p>
        <p class="text-xs text-gray-500" data-test="datos-solo-propietario">{{ t('plataformaPanel.gestionar.datosSoloPropietario') }}</p>
      </section>

      <section class="card space-y-3 border-red-100" aria-labelledby="g-baja">
        <h2 id="g-baja" class="text-base font-semibold text-red-800">{{ t('plataformaPanel.gestionar.baja') }}</h2>
        <p v-if="ig.borrado_programado_en" :class="['text-sm font-medium', borradoVencido ? 'text-red-700' : 'text-amber-700']">{{ detalle.texto }}</p>
        <div class="flex flex-wrap gap-3 text-sm">
          <button v-if="borradoVencido" type="button" class="text-red-700 underline" @click="borrarAhora">{{ t('plataforma.borrarAhora') }}</button>
          <button v-if="!ig.borrado_programado_en && ['receso', 'suspendida'].includes(etapa)" type="button" class="text-gray-700 hover:text-red-700 underline" @click="programarBorrado">{{ t('plataforma.programarBorrado') }}</button>
          <button v-if="!ig.adn_borrada_en" type="button" class="text-red-700 underline" data-test="borrar-suave" @click="borrarSuave">{{ t('plataforma.borrarSuave') }}</button>
        </div>
      </section>

      <HistorialIglesia :iglesia-id="ig.id" />
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { ArrowLeft, Check, Circle, CircleCheck } from '@lucide/vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { usePlataformaStore } from '@/stores/plataforma'
import { borradoVencido as vencido, detalleDeEstado, diasDePrueba, diasParaPurga, etapaDe, modulosDe, situacionDe } from './adaptador'
import HistorialIglesia from './HistorialIglesia.vue'

const { t, locale } = useI18n()
const pm = usePlataformaStore()
const route = useRoute()
const ETAPAS = ['onboarding', 'prueba', 'activa', 'receso', 'suspendida']

onMounted(() => { void pm.asegurarCargada() })

const ig = computed(() => pm.iglesias.find(i => i.id === route.params.id) ?? null)
const etapa = computed(() => ig.value ? etapaDe(ig.value) : 'activa')
const catalogo = computed(() => ({ planes: pm.planes, modulos: pm.modulos, planModulos: pm.planModulos }))
const situacion = computed(() => ig.value ? situacionDe(ig.value) : 'activa')
// Días que importan en el texto: los de la prueba o los que faltan para la purga
const dias = computed(() => !ig.value ? null : ig.value.borrado_programado_en ? diasParaPurga(ig.value) : diasDePrueba(ig.value))
const fechaCorta = (iso: string | null) => iso ? new Date(iso).toLocaleDateString(locale.value) : ''
// Los botones de cada situación: reactivar, activar o convertir; recuperar o cancelar el borrado. La copia de los datos la descarga solo el propietario de la iglesia
const acciones = computed<{ clave: string; principal?: boolean; ejecutar: () => void }[]>(() => {
  const s = situacion.value
  const l: { clave: string; principal?: boolean; ejecutar: () => void }[] = []
  if (s === 'receso' || s === 'suspendida') l.push({ clave: 'reactivar', principal: true, ejecutar: () => pasarAActiva() })
  if (s === 'onboarding') l.push({ clave: 'activar', principal: true, ejecutar: () => pasarAActiva() })
  if (s === 'prueba') l.push({ clave: 'convertir', principal: true, ejecutar: () => pasarAActiva() })
  if (s === 'baja_suave') l.push({ clave: 'recuperar', principal: true, ejecutar: () => recuperar() })
  if (s === 'baja_programada') l.push({ clave: 'cancelar', principal: true, ejecutar: () => cancelarBorrado() })
  return l
})
function pasarAActiva() {
  const actual = ig.value!
  const nombre = t('plataforma.etapa.activa')
  if (!window.confirm(t('plataforma.confirmarEtapa', { iglesia: actual.nombre, etapa: nombre }))) return
  void pm.ejecutar({ accion: 'etapa', iglesia_id: actual.id, etapa: 'activa' }, () => t('plataforma.etapaCambiada', { iglesia: actual.nombre, etapa: nombre }))
}
const detalle = computed(() => ig.value ? detalleDeEstado(ig.value, t as any, iso => new Date(iso).toLocaleDateString(locale.value)) : {})
const borradoVencido = computed(() => !!ig.value && vencido(ig.value))
const limite = computed(() => pm.planes.find(p => p.clave === ig.value?.plan)?.max_miembros ?? null)
const numeroSedes = computed(() => pm.iglesias.filter(x => x.iglesia_madre_id === ig.value?.id).length)
const posiblesMadres = computed(() => pm.iglesias.filter(x => x.id !== ig.value?.id && !x.iglesia_madre_id))
const complementos = computed(() => ig.value ? modulosDe(ig.value, catalogo.value) : [])

const cambiarPlan = (plan: string) =>
  pm.ejecutar({ accion: 'cambiar_plan', iglesia_id: ig.value!.id, plan }, () => t('plataforma.planActualizado', { iglesia: ig.value!.nombre }))

function cambiarEtapa(el: HTMLSelectElement) {
  const actual = ig.value!
  const nueva = el.value
  if (nueva === actual.etapa) return
  const nombre = t('plataforma.etapa.' + nueva)
  if (!window.confirm(t('plataforma.confirmarEtapa', { iglesia: actual.nombre, etapa: nombre }))) { el.value = actual.etapa; return }
  void pm.ejecutar({ accion: 'etapa', iglesia_id: actual.id, etapa: nueva }, () => t('plataforma.etapaCambiada', { iglesia: actual.nombre, etapa: nombre }))
}

const vincular = (madre: string | null, acceso: string) =>
  pm.ejecutar({ accion: 'vincular_red', iglesia_id: ig.value!.id, madre_id: madre, red_acceso: acceso }, () => t('plataforma.red.guardada', { iglesia: ig.value!.nombre }))

function alternarModulo(m: { clave: string; nombre: string; activo: boolean }) {
  const actual = ig.value!
  const clave = m.activo ? 'plataforma.moduloQuitado' : 'plataforma.moduloActivado'
  void pm.ejecutar({ accion: 'modulo_addon', iglesia_id: actual.id, modulo: m.clave, activo: !m.activo }, () => t(clave, { modulo: m.nombre, iglesia: actual.nombre }))
}

function programarBorrado() {
  const actual = ig.value!
  const dias = window.prompt(t('plataforma.pedirDias', { iglesia: actual.nombre }), '30')
  if (!dias) return
  const confirmar = window.prompt(t('plataforma.pedirDireccion', { slug: actual.slug }))
  if (!confirmar) return
  void pm.ejecutar({ accion: 'programar_borrado', iglesia_id: actual.id, dias: Number(dias), confirmar }, () => t('plataforma.borradoPlanificado', { iglesia: actual.nombre }))
}

// Borrado suave: suspende la iglesia y la purga a los 30 dias; hasta entonces se recupera
function borrarSuave() {
  const actual = ig.value!
  if (!window.confirm(t('plataforma.confirmarBorradoSuave', { iglesia: actual.nombre }))) return
  const confirmar = window.prompt(t('plataforma.pedirDireccion', { slug: actual.slug }))
  if (!confirmar) return
  const motivo = window.prompt(t('plataforma.pedirMotivo')) ?? ''
  const fecha = new Date(Date.now() + 30 * 86400000).toLocaleDateString(locale.value)
  void pm.ejecutar({ accion: 'borrar_suave', iglesia_id: actual.id, confirmar, motivo }, () => t('plataforma.borradoSuaveHecho', { iglesia: actual.nombre, fecha }))
}

function recuperar() {
  const actual = ig.value!
  if (!window.confirm(t('plataforma.confirmarRecuperar', { iglesia: actual.nombre }))) return
  void pm.ejecutar({ accion: 'recuperar', iglesia_id: actual.id }, () => t('plataforma.recuperada', { iglesia: actual.nombre }))
}

const cancelarBorrado = () =>
  pm.ejecutar({ accion: 'cancelar_borrado', iglesia_id: ig.value!.id }, () => t('plataforma.borradoCancelado', { iglesia: ig.value!.nombre }))

function borrarAhora() {
  const actual = ig.value!
  if (!window.confirm(t('plataforma.confirmarBorrarAhora', { iglesia: actual.nombre }))) return
  const confirmar = window.prompt(t('plataforma.pedirDireccion', { slug: actual.slug }))
  if (!confirmar) return
  void pm.ejecutar({ accion: 'borrar_iglesia', iglesia_id: actual.id, confirmar }, () => t('plataforma.iglesiaBorrada', { iglesia: actual.nombre }))
}
</script>
