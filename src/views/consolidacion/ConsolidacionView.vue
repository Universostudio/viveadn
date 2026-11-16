<template>
  <div class="p-4 sm:p-6 space-y-6">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('consolidacion.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('consolidacion.subtitulo') }}</p>
      </div>
      <button v-if="puedeCrear" @click="abrirNuevo = true" class="btn-primary flex items-center gap-2" data-test="nuevo-convertido">
        <UserPlus class="w-4 h-4" aria-hidden="true" /> {{ t('consolidacion.nuevo') }}
      </button>
    </div>

    <p v-if="aviso" role="status" data-test="aviso" :class="['text-sm px-4 py-3 rounded-lg border', aviso.error ? 'bg-red-50 text-red-700 border-red-200' : 'bg-green-50 text-green-700 border-green-200']">{{ aviso.texto }}</p>

    <!-- Indicadores de estado -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div
        v-for="estado in estados"
        :key="estado.alerta"
        :class="['card-stat cursor-pointer border-l-4 transition-all', estado.clase,
          filtroActivo === estado.alerta ? 'ring-2 ring-offset-1 ring-adn-verde' : '']"
        @click="toggleFiltro(estado.alerta)"
      >
        <component :is="estado.icono" :class="['w-6 h-6 flex-shrink-0', estado.color]" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold">{{ estado.count }}</p>
          <p class="text-xs text-gray-600">{{ t(estado.label) }}</p>
        </div>
      </div>
    </div>

    <!-- OP72 avanzado: metricas del seguimiento. Sin el modulo, una tarjeta informativa -->
    <div v-if="verMetricas" class="card space-y-4">
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><ChartColumn class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('consolidacion.metricas.titulo') }}</h2>
        <select v-model.number="diasMetricas" @change="cargarMetricas" :aria-label="t('consolidacion.metricas.periodo')"
          class="text-sm border border-gray-200 rounded-lg px-2 py-1.5 bg-white">
          <option :value="7">{{ t('consolidacion.metricas.dias', { n: 7 }) }}</option>
          <option :value="30">{{ t('consolidacion.metricas.dias', { n: 30 }) }}</option>
          <option :value="90">{{ t('consolidacion.metricas.dias', { n: 90 }) }}</option>
        </select>
      </div>
      <p v-if="errorMetricas" class="text-sm text-red-600" role="alert">{{ t('consolidacion.metricas.error') }}</p>
      <p v-else-if="!metricas" class="text-sm text-gray-500" role="status">{{ t('comun.cargando') }}</p>
      <p v-else-if="metricas.total === 0" class="text-sm text-gray-500">{{ t('consolidacion.metricas.sinDatos') }}</p>
      <template v-else>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div v-for="k in tarjetasMetricas" :key="k.etiqueta" class="bg-gray-50 rounded-xl p-3">
            <p class="text-2xl font-bold text-gray-900">{{ k.valor }}</p>
            <p class="text-xs text-gray-500">{{ t(k.etiqueta) }}</p>
          </div>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div v-for="g in gruposMetricas" :key="g.titulo">
            <h3 class="text-sm font-semibold text-gray-700 mb-2">{{ t(g.titulo) }}</h3>
            <ul class="divide-y divide-gray-100 text-sm">
              <li v-for="f in g.filas" :key="f.id ?? 'sin'" class="flex items-center justify-between py-1.5 gap-3">
                <span class="truncate text-gray-700">{{ f.nombre || t('consolidacion.metricas.sinAsignar') }}</span>
                <span class="text-gray-500 whitespace-nowrap">{{ f.total }}<span v-if="f.vencidos" class="text-red-600"> · {{ t('consolidacion.metricas.vencidosN', { n: f.vencidos }) }}</span></span>
              </li>
            </ul>
          </div>
        </div>
      </template>
    </div>
    <div v-else-if="ofrecerMetricas" class="card flex items-start gap-3 bg-adn-arena/40">
      <ChartColumn class="w-6 h-6 text-adn-verde flex-shrink-0" aria-hidden="true" />
      <div>
        <p class="font-semibold text-gray-900">{{ t('consolidacion.metricas.promo') }}</p>
        <p class="text-sm text-gray-600">{{ t('consolidacion.metricas.promoAyuda') }}</p>
      </div>
    </div>

    <!-- Lista de consolidaciones -->
    <div class="card">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-gray-900">
          {{ t('consolidacion.activas') }}
          <span class="ml-2 text-sm font-normal text-gray-400">({{ consolidacionesFiltradas.length }})</span>
        </h2>
        <div class="flex items-center gap-2">
          <button
            v-if="filtroActivo"
            @click="filtroActivo = null"
            class="text-xs text-adn-verde hover:underline"
          >
            {{ t('consolidacion.limpiarFiltro') }}
          </button>
          <select
            v-model="ordenar"
            class="text-sm border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-adn-verde"
          >
            <option value="urgente">{{ t('consolidacion.ordenUrgente') }}</option>
            <option value="reciente">{{ t('consolidacion.ordenReciente') }}</option>
            <option value="nombre">{{ t('consolidacion.ordenNombre') }}</option>
          </select>
        </div>
      </div>

      <div v-if="cargando" class="py-12 text-center text-gray-400">
        <LoaderCircle class="w-8 h-8 mx-auto mb-2 animate-spin text-gray-300" aria-hidden="true" />
        <p>{{ t('consolidacion.cargando') }}</p>
      </div>

      <div v-else-if="consolidacionesFiltradas.length === 0" class="py-12 text-center text-gray-400">
        <CircleCheck class="w-10 h-10 mx-auto mb-2 text-emerald-500" aria-hidden="true" />
        <p class="font-medium">
          {{ filtroActivo ? t('consolidacion.sinEnEstado') : t('consolidacion.sinPendientes') }}
        </p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="c in consolidacionesFiltradas"
          :key="c.id"
          :data-consolidacion="c.id"
          :class="['border rounded-xl p-4 transition-all hover:shadow-sm', claseBorde(c.estado_alerta)]"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="flex items-start gap-3">
              <!-- Avatar con alerta -->
              <div class="relative flex-shrink-0">
                <div class="w-11 h-11 bg-adn-verde rounded-full flex items-center justify-center">
                  <span class="text-white font-bold">{{ c.miembros?.nombre?.[0] ?? '?' }}</span>
                </div>
              </div>

              <!-- Info -->
              <div>
                <p class="font-semibold text-gray-900">
                  {{ c.miembros?.nombre }} {{ c.miembros?.apellido }}
                </p>
                <p class="text-xs text-gray-500 mt-0.5">{{ c.miembros?.crm_id }}</p>
                <div class="flex flex-wrap gap-3 mt-2 text-xs text-gray-500">
                  <span class="inline-flex items-center gap-1"><CalendarDays class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.conversionFecha', { fecha: formatFecha(c.fecha_conversion) }) }}</span>
                  <span class="inline-flex items-center gap-1"><Timer class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.transcurridas', { horas: horasTranscurridas(c.fecha_conversion) }) }}</span>
                  <span v-if="c.consolidador_perfil" class="inline-flex items-center gap-1">
                    <UserRound class="w-3.5 h-3.5" aria-hidden="true" /> {{ c.consolidador_perfil.nombre }} {{ c.consolidador_perfil.apellido }}
                  </span>
                  <span v-else class="inline-flex items-center gap-1 text-amber-700" data-test="sin-asignar">
                    <UserRound class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.sinAsignar') }}
                  </span>
                  <span class="inline-flex items-center gap-1" data-test="n-contactos">{{ t('consolidacion.contactos.titulo') }}: {{ contactosDe(c).length }}/3</span>
                </div>
                <p v-if="c.notas" class="text-xs text-gray-600 mt-2 bg-gray-50 rounded px-2 py-1 italic">
                  "{{ c.notas }}"
                </p>
              </div>
            </div>

            <!-- Acciones -->
            <div class="flex flex-col items-end gap-2 flex-shrink-0">
              <EstadoAlerta :estado="c.estado_alerta" />
              <div class="flex gap-2">
                <button
                  @click="verDetalle(c)"
                  class="text-xs text-adn-verde hover:underline font-medium"
                  data-test="ver-detalles"
                >
                  {{ t('consolidacion.verDetalles') }}
                </button>
                <button
                  v-if="puedeContactar"
                  @click="marcarCompletado(c.id)"
                  class="text-xs text-green-700 hover:underline font-medium inline-flex items-center gap-1"
                  data-test="completar"
                >
                  <Check class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.completar') }}
                </button>
              </div>
            </div>
          </div>

          <!-- Llamar y escribir: enlaces que abre quien está en pantalla; no se envía nada desde aquí -->
          <div class="mt-3 flex flex-wrap gap-2" v-if="c.miembros">
            <a v-if="enlaceLlamar(c.miembros.telefono)" :href="enlaceLlamar(c.miembros.telefono)!" data-test="llamar"
              :aria-label="t('consolidacion.llamarA', { nombre: nombreDe(c) })"
              class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-gray-200 text-adn-verde hover:border-adn-verde focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde">
              <Phone class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.llamar') }}
            </a>
            <a v-if="enlaceWhatsApp(c.miembros.telefono, auth.iglesia?.pais)" :href="enlaceWhatsApp(c.miembros.telefono, auth.iglesia?.pais)!" target="_blank" rel="noopener noreferrer" data-test="whatsapp"
              :aria-label="t('consolidacion.whatsappA', { nombre: nombreDe(c) })"
              class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg border border-gray-200 text-adn-verde hover:border-adn-verde focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde">
              <MessageCircle class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.whatsapp') }}
            </a>
            <span v-if="!c.miembros.telefono" class="text-xs text-gray-500 py-2" data-test="sin-telefono">{{ t('consolidacion.sinTelefono') }}</span>
            <span v-else-if="!enlaceWhatsApp(c.miembros.telefono, auth.iglesia?.pais)" class="text-xs text-gray-500 py-2" data-test="sin-prefijo">{{ t('consolidacion.sinPrefijo') }}</span>
            <button v-if="puedeContactar" type="button" class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg bg-adn-verde text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde" data-test="registrar-contacto" @click="verDetalle(c)">
              <ClipboardPen class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.contactos.registrar') }}
            </button>
          </div>

          <!-- Barra de progreso hacia el plazo del método -->
          <div class="mt-3">
            <div class="flex justify-between text-xs text-gray-400 mb-1">
              <span>{{ t('consolidacion.progreso', { horas: plazoDe(c) }) }}</span>
              <span>{{ t('consolidacion.limiteFecha', { fecha: formatFecha(c.fecha_limite) }) }}</span>
            </div>
            <div class="h-2 bg-gray-100 rounded-full overflow-hidden">
              <div
                :class="['h-full rounded-full transition-all', claseBarra(c.estado_alerta)]"
                :style="{ width: `${Math.min(progresoHoras(c), 100)}%` }"
              ></div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal: Nuevo convertido -->
    <div
      v-if="abrirNuevo"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="abrirNuevo = false"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ t('consolidacion.registrarTitulo') }}</h2>
        <form @submit.prevent="crearConsolidacion" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('consolidacion.miembro') }}</label>
            <select
              v-model="nuevo.miembro_id"
              required
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm"
            >
              <option value="">{{ t('consolidacion.seleccionarMiembro') }}</option>
              <option v-for="m in miembrosDisponibles" :key="m.id" :value="m.id">
                {{ m.nombre }} {{ m.apellido }} ({{ m.crm_id }})
              </option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('consolidacion.fechaConversion') }}</label>
            <input
              v-model="nuevo.fecha_conversion"
              type="datetime-local"
              required
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('consolidacion.notas') }}</label>
            <textarea
              v-model="nuevo.notas"
              rows="3"
              :placeholder="t('consolidacion.notasPlaceholder')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm resize-none"
            ></textarea>
          </div>
          <div class="flex gap-3 pt-2">
            <button type="button" @click="abrirNuevo = false" class="btn-secondary flex-1">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="guardando" class="btn-primary flex-1 disabled:opacity-60">
              {{ guardando ? t('consolidacion.registrando') : t('consolidacion.registrar') }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- Modal: Detalle consolidación -->
    <div
      v-if="detalleActivo"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="detalleActivo = null" @keydown.esc="detalleActivo = null"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto" role="dialog" aria-modal="true" aria-labelledby="cs-titulo-detalle" data-test="detalle" tabindex="-1" ref="dialogoDetalle">
        <div class="flex items-center justify-between mb-4">
          <h2 id="cs-titulo-detalle" class="text-lg font-bold text-gray-900">{{ t('consolidacion.detalleTitulo') }}</h2>
          <button @click="detalleActivo = null" class="text-gray-400 hover:text-gray-600 text-xl" :aria-label="t('comun.cerrar')">×</button>
        </div>
        <div v-if="detalleActivo" class="space-y-3 text-sm">
          <div class="bg-gray-50 rounded-xl p-4">
            <p class="font-semibold text-gray-900 text-base">
              {{ detalleActivo.miembros?.nombre }} {{ detalleActivo.miembros?.apellido }}
            </p>
            <p class="text-gray-500">{{ detalleActivo.miembros?.crm_id }}</p>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div class="bg-gray-50 rounded-lg p-3">
              <p class="text-xs text-gray-400">{{ t('consolidacion.estado') }}</p>
              <p class="font-semibold capitalize">{{ te(`alertas.color.${detalleActivo.estado_alerta}`) ? t(`alertas.color.${detalleActivo.estado_alerta}`) : detalleActivo.estado_alerta }}</p>
            </div>
            <div class="bg-gray-50 rounded-lg p-3">
              <p class="text-xs text-gray-400">{{ t('consolidacion.horasTranscurridas') }}</p>
              <p class="font-semibold">{{ horasTranscurridas(detalleActivo.fecha_conversion) }}h</p>
            </div>
            <div class="bg-gray-50 rounded-lg p-3">
              <p class="text-xs text-gray-400">{{ t('consolidacion.conversion') }}</p>
              <p class="font-semibold">{{ formatFecha(detalleActivo.fecha_conversion) }}</p>
            </div>
            <div v-if="detalleActivo.metodo?.nombre" class="bg-gray-50 rounded-lg p-3" data-test="detalle-metodo">
              <p class="text-xs text-gray-400">{{ t('consolidacion.metodo') }}</p>
              <p class="font-semibold">{{ detalleActivo.metodo.nombre }}</p>
            </div>
            <div class="bg-gray-50 rounded-lg p-3">
              <p class="text-xs text-gray-400">{{ t('consolidacion.limite') }}</p>
              <p class="font-semibold">{{ formatFecha(detalleActivo.fecha_limite) }}</p>
            </div>
          </div>
          <div v-if="puedeReasignar" class="bg-gray-50 rounded-lg p-3">
            <label for="cs-consolidador" class="text-xs text-gray-500 block mb-1">{{ t('consolidacion.asignar.etiqueta') }}</label>
            <select id="cs-consolidador" data-test="asignar" :value="detalleActivo.consolidador_id ?? ''" @change="asignar(($event.target as HTMLSelectElement).value || null)"
              class="w-full text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option value="">{{ t('consolidacion.asignar.ninguno') }}</option>
              <option v-for="p in consolidadores" :key="p.id" :value="p.id">{{ p.nombre }} {{ p.apellido }}</option>
            </select>
          </div>
          <section class="bg-gray-50 rounded-lg p-3 space-y-2" aria-labelledby="cs-contactos" data-test="contactos">
            <h3 id="cs-contactos" class="text-sm font-semibold text-gray-800">{{ t('consolidacion.contactos.titulo') }}</h3>
            <p v-if="!contactosDe(detalleActivo).length" class="text-xs text-gray-500">{{ t('consolidacion.contactos.ninguno') }}</p>
            <ul v-else class="space-y-2">
              <li v-for="k in contactosDe(detalleActivo)" :key="k.n" class="text-sm" data-test="contacto">
                <p class="text-xs text-gray-500">{{ t('consolidacion.contactos.n', { n: k.n }) }} · {{ formatFecha(k.fecha) }}</p>
                <p v-if="k.notas" class="text-gray-700">{{ k.notas }}</p>
              </li>
            </ul>
            <form v-if="puedeContactar && siguienteHueco(detalleActivo)" class="space-y-2 pt-2 border-t border-gray-200" @submit.prevent="guardarContacto">
              <div>
                <label for="cs-fecha" class="text-xs text-gray-500 block mb-1">{{ t('consolidacion.contactos.fecha') }}</label>
                <input id="cs-fecha" v-model="contacto.fecha" type="datetime-local" required data-test="contacto-fecha"
                  class="w-full text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" />
              </div>
              <div>
                <label for="cs-nota" class="text-xs text-gray-500 block mb-1">{{ t('consolidacion.contactos.nota') }}</label>
                <textarea id="cs-nota" v-model="contacto.nota" rows="2" maxlength="1000" data-test="contacto-nota" :placeholder="t('consolidacion.contactos.notaEjemplo')"
                  class="w-full text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde resize-none"></textarea>
              </div>
              <p v-if="errorContacto" role="alert" class="text-xs text-red-700" data-test="error-contacto">{{ errorContacto }}</p>
              <button type="submit" :disabled="guardando" class="btn-primary w-full text-sm disabled:opacity-60" data-test="guardar-contacto">{{ t('consolidacion.contactos.guardar') }}</button>
            </form>
            <p v-else-if="!siguienteHueco(detalleActivo)" class="text-xs text-gray-500" data-test="contactos-completos">{{ t('consolidacion.contactos.completos') }}</p>
          </section>
          <div v-if="detalleActivo.notas" class="bg-yellow-50 rounded-lg p-3">
            <p class="text-xs text-gray-400 mb-1">{{ t('consolidacion.notas') }}</p>
            <p class="italic text-gray-700">"{{ detalleActivo.notas }}"</p>
          </div>
          <button
            v-if="puedeContactar"
            @click="marcarCompletado(detalleActivo.id); detalleActivo = null"
            class="w-full btn-primary mt-2 inline-flex items-center justify-center gap-2"
          >
            <Check class="w-4 h-4" aria-hidden="true" /> {{ t('consolidacion.marcarCompletado') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import EstadoAlerta from '@/components/EstadoAlerta.vue'
import { CalendarDays, ChartColumn, Check, CircleCheck, ClipboardPen, Clock, LoaderCircle, MessageCircle, Phone, Siren, Timer, TriangleAlert, UserPlus, UserRound } from '@lucide/vue'
import { ref, computed, nextTick, onMounted, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { conAlerta, plazoDe } from '@/lib/alertas'
import { useSeguimientoStore } from '@/stores/seguimiento'
import type { AlertaColor } from '@/lib/supabase'
import { useI18n } from 'vue-i18n'
import { formatoFechaHora } from '@/i18n'
import { useAuthStore } from '@/stores/auth'
import { candidatos } from '@/lib/lideres'
import { camposContacto, contactosDe, enlaceLlamar, enlaceWhatsApp, fechaDeContactoValida, siguienteHueco } from '@/lib/seguimiento'

const { t, te } = useI18n()
const auth = useAuthStore()
const seg = useSeguimientoStore()

// ---- OP72 avanzado (de pago) ----
const verMetricas = computed(() => auth.tieneModulo('op72_avanzado') && auth.can('consolidacion.ver'))
const ofrecerMetricas = computed(() => !auth.tieneModulo('op72_avanzado') && auth.can('consolidacion.ver'))
const metricas = ref<any>(null)
const errorMetricas = ref(false)
const diasMetricas = ref(30)

async function cargarMetricas() {
  if (!verMetricas.value) return
  metricas.value = null
  errorMetricas.value = false
  const { data, error } = await supabase.rpc('metricas_op72', { p_desde: new Date(Date.now() - diasMetricas.value * 86_400_000).toISOString() })
  if (error) { errorMetricas.value = true; return }
  metricas.value = data
}

const pct = (n: number, d: number) => (d > 0 ? `${Math.round((n / d) * 100)}%` : '0%')
const tarjetasMetricas = computed(() => {
  const m = metricas.value
  if (!m) return []
  return [
    { etiqueta: 'consolidacion.metricas.total', valor: m.total },
    { etiqueta: 'consolidacion.metricas.contacto24h', valor: pct(m.primer_contacto_24h, m.total) },
    { etiqueta: 'consolidacion.metricas.horasPrimerContacto', valor: m.horas_primer_contacto == null ? '-' : `${m.horas_primer_contacto} h` },
    { etiqueta: 'consolidacion.metricas.completados72h', valor: pct(m.completados_72h, m.total) },
    { etiqueta: 'consolidacion.metricas.completados', valor: m.completados },
    { etiqueta: 'consolidacion.metricas.abiertos', valor: m.abiertos },
    { etiqueta: 'consolidacion.metricas.vencidos', valor: m.vencidos },
    { etiqueta: 'consolidacion.metricas.conContacto', valor: pct(m.con_primer_contacto, m.total) },
  ]
})
const gruposMetricas = computed(() => {
  const m = metricas.value
  if (!m) return []
  return [
    { titulo: 'consolidacion.metricas.porConsolidador', filas: (m.por_consolidador ?? []).map((f: any) => ({ id: f.consolidador_id, nombre: f.nombre, total: f.total, vencidos: f.vencidos })) },
    { titulo: 'consolidacion.metricas.porCasa', filas: (m.por_casa ?? []).map((f: any) => ({ id: f.casa_oracion_id, nombre: f.nombre, total: f.total, vencidos: f.vencidos })) },
  ]
})

const cargando = ref(true)
const consolidaciones = ref<any[]>([])
const miembrosDisponibles = ref<any[]>([])
const filtroActivo = ref<AlertaColor | null>(null)
const ordenar = ref('urgente')
const abrirNuevo = ref(false)
const guardando = ref(false)
const detalleActivo = ref<any>(null)
const dialogoDetalle = ref<HTMLElement | null>(null)
// El foco entra en el diálogo al abrirlo (así Escape lo cierra) y vuelve a donde estaba al cerrarlo
let focoPrevio: HTMLElement | null = null
watch(detalleActivo, async (nuevo, viejo) => {
  if (nuevo && !viejo) { focoPrevio = document.activeElement as HTMLElement | null; await nextTick(); dialogoDetalle.value?.focus() }
  else if (!nuevo && viejo) { focoPrevio?.focus?.(); focoPrevio = null }
})

// Permisos de esta pantalla: la base de datos los exige igualmente; aquí solo se ofrece lo que la persona puede hacer
const puedeCrear = computed(() => auth.can('consolidacion.crear'))
const puedeContactar = computed(() => auth.can('consolidacion.editar', 'consolidacion.registrar_contacto'))
const puedeReasignar = computed(() => auth.can('consolidacion.reasignar'))

const aviso = ref<{ texto: string; error: boolean } | null>(null)
const avisar = (texto: string, error = false) => { aviso.value = { texto, error } }
const nombreDe = (c: any) => `${c.miembros?.nombre ?? ''} ${c.miembros?.apellido ?? ''}`.trim()

// Quién puede ser consolidador: las personas activas cuyo rol puede registrar contactos (o es propietario)
const consolidadores = ref<{ id: string; nombre: string; apellido: string }[]>([])
async function cargarConsolidadores() {
  if (!puedeReasignar.value) return
  const [{ data: roles }, { data: perfiles }] = await Promise.all([
    supabase.from('roles').select('clave, es_propietario, rol_permisos(permiso)'),
    supabase.from('perfiles').select('id, nombre, apellido, rol, activo').eq('activo', true).order('nombre'),
  ])
  consolidadores.value = candidatos((roles ?? []) as any[], (perfiles ?? []) as any[], 'consolidacion.registrar_contacto').map(p => ({ id: p.id, nombre: p.nombre, apellido: p.apellido }))
}

const ahoraLocal = () => { const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16) }
const contacto = ref({ fecha: ahoraLocal(), nota: '' })
const errorContacto = ref('')

async function guardarContacto() {
  const c = detalleActivo.value
  const n = c ? siguienteHueco(c) : null
  if (!c || !n) return
  const fechaIso = new Date(contacto.value.fecha).toISOString()
  if (!fechaDeContactoValida(fechaIso)) { errorContacto.value = t('consolidacion.contactos.futura'); return }
  errorContacto.value = ''
  guardando.value = true
  const campos = camposContacto(n, fechaIso, contacto.value.nota)
  const { error } = await supabase.from('consolidaciones').update(campos).eq('id', c.id)
  guardando.value = false
  if (error) { errorContacto.value = t('consolidacion.contactos.error'); return }
  Object.assign(c, campos)
  contacto.value = { fecha: ahoraLocal(), nota: '' }
  avisar(t('consolidacion.contactos.guardado'))
}

async function asignar(id: string | null) {
  const c = detalleActivo.value
  if (!c) return
  const { error } = await supabase.from('consolidaciones').update({ consolidador_id: id }).eq('id', c.id)
  if (error) { avisar(t('consolidacion.asignar.error'), true); await cargarDatos(); return }
  c.consolidador_id = id
  const p = consolidadores.value.find(x => x.id === id)
  c.consolidador_perfil = p ? { nombre: p.nombre, apellido: p.apellido } : null
  avisar(t('consolidacion.asignar.guardado'))
}

const nuevo = ref({
  miembro_id: '',
  fecha_conversion: new Date().toISOString().slice(0, 16),
  notas: '',
})

// Helpers
function horasTranscurridas(fecha: string) {
  return Math.floor((Date.now() - new Date(fecha).getTime()) / 3600000)
}

// Progreso hacia el plazo del método del proceso (72 horas en OP72)
function progresoHoras(c: { fecha_conversion: string; metodo?: any }) {
  return (horasTranscurridas(c.fecha_conversion) / plazoDe(c)) * 100
}

function formatFecha(fecha: string) {
  if (!fecha) return '—'
  return formatoFechaHora(fecha, {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit'
  })
}

function claseBorde(alerta: AlertaColor) {
  const m: Record<AlertaColor, string> = {
    verde: 'border-green-200 bg-green-50/30',
    amarillo: 'border-yellow-200 bg-yellow-50/30',
    naranja: 'border-orange-200 bg-orange-50/30',
    rojo: 'border-red-200 bg-red-50/30',
  }
  return m[alerta] ?? 'border-gray-200'
}

function claseBarra(alerta: AlertaColor) {
  const m: Record<AlertaColor, string> = {
    verde: 'bg-green-400', amarillo: 'bg-yellow-400',
    naranja: 'bg-orange-400', rojo: 'bg-red-500',
  }
  return m[alerta] ?? 'bg-gray-400'
}

// Estados para los indicadores (label: clave de traducción)
const estados = computed(() => {
  const conteo = { verde: 0, amarillo: 0, naranja: 0, rojo: 0 }
  consolidaciones.value.forEach(c => { conteo[c.estado_alerta as AlertaColor]++ })
  return [
    { alerta: 'verde' as AlertaColor, icono: CircleCheck, color: 'text-emerald-600', label: 'alertas.rango.verde', count: conteo.verde, clase: 'border-green-400' },
    { alerta: 'amarillo' as AlertaColor, icono: Clock, color: 'text-amber-600', label: 'alertas.rango.amarillo', count: conteo.amarillo, clase: 'border-yellow-400' },
    { alerta: 'naranja' as AlertaColor, icono: TriangleAlert, color: 'text-orange-600', label: 'alertas.rango.naranja', count: conteo.naranja, clase: 'border-orange-400' },
    { alerta: 'rojo' as AlertaColor, icono: Siren, color: 'text-red-600', label: 'alertas.rango.rojo', count: conteo.rojo, clase: 'border-red-400' },
  ]
})

// Filtrado y ordenación
const consolidacionesFiltradas = computed(() => {
  let lista = [...consolidaciones.value]
  if (filtroActivo.value) lista = lista.filter(c => c.estado_alerta === filtroActivo.value)

  if (ordenar.value === 'urgente') {
    const orden: Record<AlertaColor, number> = { rojo: 0, naranja: 1, amarillo: 2, verde: 3 }
    lista.sort((a, b) => (orden[a.estado_alerta as AlertaColor] ?? 9) - (orden[b.estado_alerta as AlertaColor] ?? 9))
  } else if (ordenar.value === 'reciente') {
    lista.sort((a, b) => new Date(b.fecha_conversion).getTime() - new Date(a.fecha_conversion).getTime())
  } else {
    lista.sort((a, b) => (a.miembros?.nombre ?? '').localeCompare(b.miembros?.nombre ?? ''))
  }
  return lista
})

function toggleFiltro(alerta: AlertaColor) {
  filtroActivo.value = filtroActivo.value === alerta ? null : alerta
}

function verDetalle(c: any) {
  detalleActivo.value = c
}

async function cargarDatos() {
  cargando.value = true
  await seg.asegurar()
  const [consolRes, miembrosRes] = await Promise.all([
    supabase
      .from('consolidaciones')
      .select('*, miembros!consolidaciones_miembro_fk(id, nombre, apellido, crm_id, telefono), consolidador_perfil:perfiles!consolidaciones_consolidador_fk(nombre, apellido)' + seg.embeber())
      .eq('completado', false)
      .order('fecha_conversion', { ascending: true }),
    puedeCrear.value
      ? supabase.from('miembros').select('id, nombre, apellido, crm_id').eq('activo', true).order('nombre')
      : Promise.resolve({ data: [] as any[] }),
  ])
  consolidaciones.value = (consolRes.data ?? []).map(conAlerta)
  miembrosDisponibles.value = miembrosRes.data ?? []
  cargando.value = false
}

async function crearConsolidacion() {
  guardando.value = true
  const { error } = await supabase.from('consolidaciones').insert({
    miembro_id: nuevo.value.miembro_id,
    fecha_conversion: nuevo.value.fecha_conversion,
    notas: nuevo.value.notas || null,
  })
  guardando.value = false
  if (error) { avisar(t('consolidacion.errorCrear'), true); return }
  if (!error) {
    abrirNuevo.value = false
    nuevo.value = { miembro_id: '', fecha_conversion: new Date().toISOString().slice(0, 16), notas: '' }
    await cargarDatos()
  }
}

async function marcarCompletado(id: string) {
  const { error } = await supabase.from('consolidaciones').update({ completado: true }).eq('id', id)
  if (error) { avisar(t('consolidacion.errorCompletar'), true); return }
  consolidaciones.value = consolidaciones.value.filter(c => c.id !== id)
}

onMounted(() => { cargarDatos(); cargarMetricas(); cargarConsolidadores() })
</script>
