<template>
  <div class="space-y-6" data-test="pm-soporte">
    <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.menu.soporte') }}</h1>

    <template v-if="pm.soporte.estado === 'falta'">
      <TarjetaSinConectar id="tickets" :titulo="t('plataformaPanel.soporte.tickets')" :falta="t('plataformaPanel.soporte.faltaTickets')" />
      <TarjetaSinConectar id="cambios" :titulo="t('plataformaPanel.soporte.cambios')" :falta="t('plataformaPanel.soporte.faltaCambios')" />
    </template>
    <p v-else-if="pm.soporte.estado === 'error'" class="card text-sm text-red-700" role="alert" data-test="pm-soporte-error">{{ t('plataformaPanel.soporte.errorCarga') }}</p>
    <template v-else>
      <p v-if="pm.soporte.estado === 'pendiente'" class="text-sm text-gray-500" role="status">{{ t('comun.cargando') }}</p>
      <div v-else class="grid grid-cols-2 lg:grid-cols-4 gap-3" data-test="pm-soporte-cifras">
        <div class="card"><p class="text-xs text-gray-500">{{ t('plataformaPanel.soporte.abiertos') }}</p><p class="text-2xl font-bold" data-test="cifra-abiertos">{{ r?.tickets?.abiertos ?? 0 }}</p></div>
        <div class="card"><p class="text-xs text-gray-500">{{ t('plataformaPanel.soporte.respondidos') }}</p><p class="text-2xl font-bold">{{ r?.tickets?.respondidos ?? 0 }}</p></div>
        <div class="card"><p class="text-xs text-gray-500">{{ t('plataformaPanel.soporte.urgentes') }}</p><p class="text-2xl font-bold">{{ r?.tickets?.urgentes ?? 0 }}</p></div>
        <div class="card"><p class="text-xs text-gray-500">{{ t('plataformaPanel.soporte.avisosVigentes') }}</p><p class="text-2xl font-bold">{{ r?.avisos?.vigentes ?? 0 }}</p></div>
      </div>

      <div role="tablist" :aria-label="t('plataformaPanel.menu.soporte')" class="flex gap-2 border-b border-gray-200" @keydown="teclasPestanas">
        <button v-for="p in PESTANAS" :key="p" :id="`soporte-tab-${p}`" type="button" role="tab" :aria-selected="pestana === p" :aria-controls="`soporte-panel-${p}`" :tabindex="pestana === p ? 0 : -1" :data-pestana="p"
          :class="['px-3 py-2 text-sm font-medium border-b-2 -mb-px', pestana === p ? 'border-adn-verde text-adn-verde' : 'border-transparent text-gray-500 hover:text-gray-800']"
          @click="cambiar(p)">{{ t('plataformaPanel.soporte.pest.' + p) }}</button>
      </div>
      <p v-if="aviso" class="text-sm text-green-800 rounded-lg bg-green-50 p-3" role="status" data-test="pm-soporte-aviso">{{ aviso }}</p>
      <p v-if="error" class="text-sm text-red-700 rounded-lg bg-red-50 p-3" role="alert" data-test="pm-soporte-fallo">{{ error }}</p>

      <!-- Tickets -->
      <section v-if="pestana === 'tickets'" id="soporte-panel-tickets" role="tabpanel" aria-labelledby="soporte-tab-tickets" tabindex="0" class="space-y-4" data-test="pm-tickets">
        <p class="text-xs text-gray-500">{{ t('plataformaPanel.soporte.ticketsNota') }}</p>
        <p v-if="!tickets.length" class="card text-sm text-gray-500" data-test="pm-tickets-vacio">{{ t('plataformaPanel.soporte.sinTickets') }}</p>
        <ul v-else class="card divide-y divide-gray-100 p-0">
          <li v-for="tk in tickets" :key="tk.id" :data-ticket="tk.id">
            <button type="button" class="w-full text-left px-4 py-3 flex items-center justify-between gap-3 hover:bg-gray-50" @click="abrir(tk.id)">
              <span class="min-w-0">
                <span class="block text-sm font-medium text-gray-900 truncate">{{ tk.asunto }}</span>
                <span class="block text-xs text-gray-500">{{ tk.iglesia ?? '' }} · {{ t('plataformaPanel.soporte.prio.' + tk.prioridad) }} · {{ new Date(tk.actualizado).toLocaleDateString(locale) }} · {{ t('plataformaPanel.soporte.mensajes', { n: tk.mensajes }) }}</span>
              </span>
              <span class="text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-700 flex-shrink-0" :data-estado="tk.estado">{{ t('plataformaPanel.soporte.estado.' + tk.estado) }}</span>
            </button>
          </li>
        </ul>
        <div v-if="abierto" class="card space-y-3" data-test="pm-ticket-abierto">
          <div class="flex items-start justify-between gap-3">
            <div><h2 class="text-base font-semibold text-gray-900">{{ abierto.asunto }}</h2><p class="text-xs text-gray-500">{{ abierto.iglesia }} · {{ t('plataformaPanel.soporte.estado.' + abierto.estado) }}</p></div>
            <button v-if="abierto.estado !== 'cerrado'" type="button" class="btn-secondary text-sm" :disabled="ocupado" data-test="pm-cerrar-ticket" @click="cerrar">{{ t('plataformaPanel.soporte.cerrar') }}</button>
          </div>
          <ol class="space-y-2">
            <li v-for="m in abierto.conversacion" :key="m.id" :data-de="m.de" :class="['rounded-xl p-3 text-sm border', m.de === 'plataforma' ? 'bg-green-50 border-green-100' : 'bg-gray-50 border-gray-100']">
              <p class="text-xs text-gray-500 mb-1">{{ m.de === 'plataforma' ? t('plataformaPanel.soporte.dePlataforma') : t('plataformaPanel.soporte.deIglesia') }} · {{ new Date(m.fecha).toLocaleString(locale) }}</p>
              <p class="whitespace-pre-line text-gray-800">{{ m.texto }}</p>
            </li>
          </ol>
          <form v-if="abierto.estado !== 'cerrado'" class="space-y-2" novalidate @submit.prevent="responder">
            <label for="pm-resp" class="block text-sm font-medium text-gray-700">{{ t('plataformaPanel.soporte.responder') }}</label>
            <textarea id="pm-resp" v-model="respuesta" rows="3" maxlength="4000" data-test="pm-resp" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde"></textarea>
            <button type="submit" class="btn-primary text-sm" :disabled="ocupado" data-test="pm-enviar-resp">{{ t('plataformaPanel.soporte.enviar') }}</button>
          </form>
        </div>
      </section>

      <!-- Novedades -->
      <section v-if="pestana === 'novedades'" id="soporte-panel-novedades" role="tabpanel" aria-labelledby="soporte-tab-novedades" tabindex="0" class="space-y-4" data-test="pm-novedades">
        <form class="card space-y-3" novalidate @submit.prevent="publicarNovedad">
          <h2 class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.soporte.nuevaNovedad') }}</h2>
          <div class="grid sm:grid-cols-4 gap-3">
            <div><label for="nv-version" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataformaPanel.soporte.version') }}</label>
              <input id="nv-version" v-model="nov.version" maxlength="30" data-test="nv-version" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm" /></div>
            <div class="sm:col-span-3"><label for="nv-titulo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataformaPanel.soporte.titulo') }}</label>
              <input id="nv-titulo" v-model="nov.titulo" maxlength="120" data-test="nv-titulo" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm" /></div>
          </div>
          <div><label for="nv-texto" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataformaPanel.soporte.texto') }}</label>
            <textarea id="nv-texto" v-model="nov.texto" rows="4" maxlength="4000" data-test="nv-texto" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm"></textarea></div>
          <button type="submit" class="btn-primary text-sm" :disabled="ocupado" data-test="nv-publicar">{{ t('plataformaPanel.soporte.publicar') }}</button>
        </form>
        <p v-if="!novedades.length" class="card text-sm text-gray-500" data-test="pm-novedades-vacio">{{ t('plataformaPanel.soporte.sinNovedades') }}</p>
        <ul v-else class="space-y-3">
          <li v-for="n in novedades" :key="n.id" class="card flex items-start justify-between gap-3" :data-novedad="n.id">
            <div><p class="text-sm font-semibold text-gray-900">{{ n.titulo }} <span class="text-xs font-normal text-gray-500">{{ n.version }} · {{ new Date(n.publicada_en).toLocaleDateString(locale) }}</span></p>
              <p class="text-sm text-gray-700 whitespace-pre-line mt-1">{{ n.texto }}</p></div>
            <span v-if="n.retirada_en" class="text-xs text-gray-500 flex-shrink-0">{{ t('plataformaPanel.soporte.retirada') }}</span>
            <button v-else type="button" class="btn-secondary text-xs flex-shrink-0" :disabled="ocupado" @click="retirarNovedad(n.id)">{{ t('plataformaPanel.soporte.retirar') }}</button>
          </li>
        </ul>
      </section>

      <!-- Avisos -->
      <section v-if="pestana === 'avisos'" id="soporte-panel-avisos" role="tabpanel" aria-labelledby="soporte-tab-avisos" tabindex="0" class="space-y-4" data-test="pm-avisos">
        <form class="card space-y-3" novalidate @submit.prevent="crearAviso">
          <h2 class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.soporte.nuevoAviso') }}</h2>
          <div class="grid sm:grid-cols-3 gap-3">
            <div><label for="av-tipo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataformaPanel.soporte.tipo') }}</label>
              <select id="av-tipo" v-model="av.tipo" data-test="av-tipo" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm bg-white">
                <option v-for="x in TIPOS" :key="x" :value="x">{{ t('plataformaPanel.soporte.tipos.' + x) }}</option></select></div>
            <div class="sm:col-span-2"><label for="av-titulo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataformaPanel.soporte.titulo') }}</label>
              <input id="av-titulo" v-model="av.titulo" maxlength="120" data-test="av-titulo" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm" /></div>
          </div>
          <div><label for="av-texto" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataformaPanel.soporte.texto') }}</label>
            <textarea id="av-texto" v-model="av.texto" rows="3" maxlength="2000" data-test="av-texto" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm"></textarea></div>
          <fieldset class="space-y-2">
            <legend class="text-sm font-medium text-gray-700">{{ t('plataformaPanel.soporte.destinatarios') }}</legend>
            <label class="flex items-center gap-2 text-sm"><input type="radio" value="todas" v-model="av.dest" data-test="av-dest-todas" /> {{ t('plataformaPanel.soporte.destTodas') }}</label>
            <label class="flex items-center gap-2 text-sm"><input type="radio" value="filtro" v-model="av.dest" data-test="av-dest-filtro" /> {{ t('plataformaPanel.soporte.destFiltro') }}</label>
            <div v-if="av.dest === 'filtro'" class="pl-6 space-y-2">
              <p class="text-xs text-gray-500">{{ t('plataformaPanel.soporte.porPlan') }}</p>
              <div class="flex flex-wrap gap-3"><label v-for="p in pm.planes" :key="p.clave" class="flex items-center gap-1 text-sm"><input type="checkbox" :value="p.clave" v-model="av.planes" /> {{ p.nombre ?? p.clave }}</label></div>
              <p class="text-xs text-gray-500">{{ t('plataformaPanel.soporte.porEstado') }}</p>
              <div class="flex flex-wrap gap-3"><label v-for="e in ETAPAS" :key="e" class="flex items-center gap-1 text-sm"><input type="checkbox" :value="e" v-model="av.estados" /> {{ t('plataformaPanel.soporte.etapas.' + e) }}</label></div>
            </div>
          </fieldset>
          <label class="flex items-center gap-2 text-sm"><input type="checkbox" v-model="av.demo" data-test="av-demo" /> {{ t('plataformaPanel.soporte.incluirDemo') }}</label>
          <label class="flex items-start gap-2 text-sm"><input type="checkbox" v-model="av.correo" data-test="av-correo" class="mt-0.5" /> <span>{{ t('plataformaPanel.soporte.porCorreo') }}<span class="block text-xs text-gray-500">{{ t('plataformaPanel.soporte.correoNota') }}</span></span></label>
          <button type="submit" class="btn-primary text-sm" :disabled="ocupado" data-test="av-crear">{{ t('plataformaPanel.soporte.enviarAviso') }}</button>
        </form>
        <p v-if="!avisos.length" class="card text-sm text-gray-500" data-test="pm-avisos-vacio">{{ t('plataformaPanel.soporte.sinAvisos') }}</p>
        <ul v-else class="space-y-3">
          <li v-for="a in avisos" :key="a.id" class="card flex items-start justify-between gap-3" :data-aviso="a.id">
            <div>
              <p class="text-sm font-semibold text-gray-900">{{ a.titulo }} <span class="text-xs font-normal text-gray-500">{{ t('plataformaPanel.soporte.tipos.' + a.tipo) }} · {{ new Date(a.created_at).toLocaleDateString(locale) }}</span></p>
              <p class="text-sm text-gray-700 mt-1">{{ a.texto }}</p>
              <p class="text-xs text-gray-500 mt-1" data-test="aviso-cifras">{{ t('plataformaPanel.soporte.entregas', { e: a.entregas, l: a.leidos, d: a.descartados }) }}
                <template v-if="a.correo_estado === 'apagado'"> · {{ t('plataformaPanel.soporte.correoApagado') }}</template></p>
            </div>
            <span v-if="a.retirado_en" class="text-xs text-gray-500 flex-shrink-0">{{ t('plataformaPanel.soporte.retirado') }}</span>
            <button v-else type="button" class="btn-secondary text-xs flex-shrink-0" :disabled="ocupado" @click="retirarAviso(a.id)">{{ t('plataformaPanel.soporte.retirar') }}</button>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import TarjetaSinConectar from '@/panel-maestro/TarjetaSinConectar.vue'
import { usePlataformaStore } from '@/stores/plataforma'

const { t, locale } = useI18n()
const pm = usePlataformaStore()
const PESTANAS = ['tickets', 'novedades', 'avisos'] as const
const TIPOS = ['actualizacion', 'mantenimiento', 'alerta'] as const
const ETAPAS = ['onboarding', 'prueba', 'activa', 'receso', 'suspendida'] as const
const pestana = ref<typeof PESTANAS[number]>('tickets')
const r = computed(() => pm.soporte.resumen)
const ocupado = ref(false)
const aviso = ref('')
const error = ref('')
const tickets = ref<any[]>([])
const abierto = ref<any | null>(null)
const respuesta = ref('')
const novedades = ref<any[]>([])
const avisos = ref<any[]>([])
const nov = ref({ version: '', titulo: '', texto: '' })
const av = ref({ tipo: 'actualizacion', titulo: '', texto: '', dest: 'todas', planes: [] as string[], estados: [] as string[], demo: false, correo: false })

async function accion(cuerpo: Record<string, unknown>, ok?: string) {
  aviso.value = ''; error.value = ''; ocupado.value = true
  try { const d = await pm.llamar(cuerpo); if (ok) aviso.value = ok; return d } catch (e) { error.value = (e as Error).message; return null } finally { ocupado.value = false }
}

async function cambiar(p: typeof PESTANAS[number]) {
  pestana.value = p; aviso.value = ''; error.value = ''
  if (p === 'tickets') { const d = await accion({ accion: 'ticket_listar' }); if (d) tickets.value = d.tickets }
  else if (p === 'novedades') { const d = await accion({ accion: 'novedad_listar' }); if (d) novedades.value = d.novedades }
  else { const d = await accion({ accion: 'aviso_listar' }); if (d) avisos.value = d.avisos }
}
// Pestañas con teclado: flechas, Inicio y Fin mueven el foco y activan la pestaña (patrón de pestañas de WAI-ARIA)
async function teclasPestanas(ev: KeyboardEvent) {
  const i = PESTANAS.indexOf(pestana.value)
  const siguiente = ev.key === 'ArrowRight' ? (i + 1) % PESTANAS.length : ev.key === 'ArrowLeft' ? (i - 1 + PESTANAS.length) % PESTANAS.length : ev.key === 'Home' ? 0 : ev.key === 'End' ? PESTANAS.length - 1 : -1
  if (siguiente < 0) return
  ev.preventDefault()
  const destino = PESTANAS[siguiente]!
  await cambiar(destino)
  document.getElementById(`soporte-tab-${destino}`)?.focus()
}
async function abrir(id: string) { const d = await accion({ accion: 'ticket_abrir', id }); if (d) { abierto.value = d.ticket; respuesta.value = '' } }
async function responder() {
  if (!abierto.value || !respuesta.value.trim()) return
  const id = abierto.value.id
  const d = await accion({ accion: 'ticket_responder', id, texto: respuesta.value })
  if (d) { await abrir(id); await refrescar(); aviso.value = t('plataformaPanel.soporte.respondido') }
}
async function cerrar() {
  const id = abierto.value.id
  const d = await accion({ accion: 'ticket_cerrar', id })
  if (d) { await abrir(id); await refrescar(); aviso.value = t('plataformaPanel.soporte.cerrado') }
}
async function publicarNovedad() {
  const d = await accion({ accion: 'novedad_publicar', ...nov.value }, t('plataformaPanel.soporte.novedadPublicada'))
  if (d) { nov.value = { version: '', titulo: '', texto: '' }; await cambiar('novedades'); aviso.value = t('plataformaPanel.soporte.novedadPublicada') }
}
async function retirarNovedad(id: string) { const d = await accion({ accion: 'novedad_retirar', id }, t('plataformaPanel.soporte.novedadRetirada')); if (d) { const l = await accion({ accion: 'novedad_listar' }); if (l) novedades.value = l.novedades } }
async function crearAviso() {
  const destino = av.value.dest === 'todas' ? { todas: true } : { ...(av.value.planes.length ? { planes: av.value.planes } : {}), ...(av.value.estados.length ? { estados: av.value.estados } : {}) }
  const d = await accion({ accion: 'aviso_crear', tipo: av.value.tipo, titulo: av.value.titulo, texto: av.value.texto, destino, incluir_demo: av.value.demo, por_correo: av.value.correo })
  if (d) {
    const l = await accion({ accion: 'aviso_listar' }); if (l) avisos.value = l.avisos
    aviso.value = t('plataformaPanel.soporte.avisoEnviado', { n: d.entregas })
    av.value = { tipo: 'actualizacion', titulo: '', texto: '', dest: 'todas', planes: [], estados: [], demo: false, correo: false }
    await refrescar()
  }
}
async function retirarAviso(id: string) { const d = await accion({ accion: 'aviso_retirar', id }, t('plataformaPanel.soporte.avisoRetirado')); if (d) { const l = await accion({ accion: 'aviso_listar' }); if (l) avisos.value = l.avisos; await refrescar() } }
async function refrescar() { await pm.cargarSoporte(); if (pestana.value === 'tickets') { const d = await accion({ accion: 'ticket_listar' }); if (d) tickets.value = d.tickets } }

onMounted(async () => { await pm.cargarSoporte(); if (pm.soporte.estado === 'ok') await cambiar('tickets') })
</script>
