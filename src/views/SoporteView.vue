<template>
  <div class="p-4 sm:p-6 max-w-3xl mx-auto space-y-6" data-test="soporte">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('soporte.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('soporte.subtitulo') }}</p>
    </div>

    <p v-if="!disponible && !cargando" class="card text-sm text-gray-600" data-test="soporte-no-disponible">{{ t('soporte.noDisponible') }}</p>
    <template v-else>
      <p v-if="aviso" class="text-sm text-green-800 rounded-lg bg-green-50 p-3" role="status" data-test="soporte-aviso">{{ aviso }}</p>
      <p v-if="error" class="text-sm text-red-700 rounded-lg bg-red-50 p-3" role="alert" data-test="soporte-error">{{ error }}</p>

      <!-- Nuevo ticket -->
      <form class="card space-y-3" novalidate aria-labelledby="s-nuevo" data-test="soporte-nuevo" @submit.prevent="crear">
        <h2 id="s-nuevo" class="text-base font-semibold text-gray-900">{{ t('soporte.nuevo') }}</h2>
        <div>
          <label for="s-asunto" class="block text-sm font-medium text-gray-700 mb-1">{{ t('soporte.asunto') }}</label>
          <input id="s-asunto" v-model="borrador.asunto" type="text" :maxlength="MAX_ASUNTO" :aria-invalid="!!errores.asunto" data-test="s-asunto"
            class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          <p v-if="errores.asunto" class="text-xs text-red-600 mt-1" data-test="s-e-asunto">{{ t(errores.asunto) }}</p>
        </div>
        <div>
          <label for="s-prioridad" class="block text-sm font-medium text-gray-700 mb-1">{{ t('soporte.prioridad') }}</label>
          <select id="s-prioridad" v-model="borrador.prioridad" data-test="s-prioridad" class="px-3 py-2 border border-gray-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-adn-verde">
            <option v-for="p in PRIORIDADES" :key="p" :value="p">{{ t('soporte.prio.' + p) }}</option>
          </select>
        </div>
        <div>
          <label for="s-texto" class="block text-sm font-medium text-gray-700 mb-1">{{ t('soporte.texto') }}</label>
          <textarea id="s-texto" v-model="borrador.texto" rows="5" :maxlength="MAX_TEXTO" :aria-invalid="!!errores.texto" data-test="s-texto"
            class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde"></textarea>
          <p v-if="errores.texto" class="text-xs text-red-600 mt-1" data-test="s-e-texto">{{ t(errores.texto) }}</p>
          <p class="text-xs text-gray-500 mt-1">{{ t('soporte.sinDatos') }}</p>
        </div>
        <button type="submit" class="btn-primary text-sm" :disabled="ocupado" data-test="s-enviar">{{ ocupado ? t('soporte.enviando') : t('soporte.enviar') }}</button>
      </form>

      <!-- Mis tickets -->
      <section class="card space-y-3" aria-labelledby="s-lista">
        <h2 id="s-lista" class="text-base font-semibold text-gray-900">{{ t('soporte.misTickets') }}</h2>
        <p v-if="cargando" class="text-sm text-gray-400" role="status">{{ t('comun.cargando') }}</p>
        <p v-else-if="errorCarga" class="text-sm text-red-600" role="alert" data-test="soporte-error-carga">{{ t('soporte.errorCarga') }}
          <button type="button" class="underline ml-1" @click="cargar">{{ t('soporte.reintentar') }}</button></p>
        <p v-else-if="!tickets.length" class="text-sm text-gray-500" data-test="soporte-vacio">{{ t('soporte.vacio') }}</p>
        <ul v-else class="divide-y divide-gray-100">
          <li v-for="tk in tickets" :key="tk.id" :data-ticket="tk.id">
            <button type="button" class="w-full text-left py-3 flex items-center justify-between gap-3 hover:bg-gray-50 rounded-lg px-2" :aria-expanded="abierto?.id === tk.id" @click="abrir(tk)">
              <span class="min-w-0">
                <span class="block text-sm font-medium text-gray-900 truncate">{{ tk.asunto }}</span>
                <span class="block text-xs text-gray-500">{{ new Date(tk.updated_at).toLocaleDateString(locale) }} · {{ t('soporte.prio.' + tk.prioridad) }}</span>
              </span>
              <span :class="['text-xs px-2 py-0.5 rounded-full flex-shrink-0', tk.estado === 'respondido' ? 'bg-green-100 text-green-800' : tk.estado === 'cerrado' ? 'bg-gray-100 text-gray-600' : 'bg-amber-100 text-amber-800']" :data-estado="tk.estado">{{ t('soporte.estado.' + tk.estado) }}</span>
            </button>
          </li>
        </ul>
      </section>

      <!-- Conversación -->
      <section v-if="abierto" class="card space-y-3" aria-labelledby="s-conv" data-test="soporte-conversacion">
        <h2 id="s-conv" class="text-base font-semibold text-gray-900">{{ abierto.asunto }}</h2>
        <p v-if="cargandoConv" class="text-sm text-gray-400" role="status">{{ t('comun.cargando') }}</p>
        <ol v-else class="space-y-3">
          <li v-for="m in mensajes" :key="m.id" :data-de="m.autor_tipo" :class="['rounded-xl p-3 text-sm', m.autor_tipo === 'plataforma' ? 'bg-green-50 border border-green-100' : 'bg-gray-50 border border-gray-100']">
            <p class="text-xs text-gray-500 mb-1">{{ m.autor_tipo === 'plataforma' ? t('soporte.dePlataforma') : t('soporte.deTuIglesia') }} · {{ new Date(m.created_at).toLocaleString(locale) }}</p>
            <p class="whitespace-pre-line text-gray-800">{{ m.texto }}</p>
          </li>
        </ol>
        <form v-if="abierto.estado !== 'cerrado'" class="space-y-2" novalidate data-test="soporte-responder" @submit.prevent="responder">
          <label for="s-resp" class="block text-sm font-medium text-gray-700">{{ t('soporte.responder') }}</label>
          <textarea id="s-resp" v-model="respuesta" rows="3" :maxlength="MAX_TEXTO" data-test="s-resp" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde"></textarea>
          <p v-if="errorRespuesta" class="text-xs text-red-600" data-test="s-e-resp">{{ t(errorRespuesta) }}</p>
          <button type="submit" class="btn-primary text-sm" :disabled="ocupado" data-test="s-responder">{{ t('soporte.enviar') }}</button>
        </form>
        <p v-else class="text-sm text-gray-500" data-test="soporte-cerrado">{{ t('soporte.cerradoAviso') }}</p>
      </section>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { supabase } from '@/lib/supabase'
import { useSoporteStore } from '@/stores/soporte'
import { MAX_ASUNTO, MAX_TEXTO, PRIORIDADES, errorDeSoporte, validarMensaje, validarTicket } from '@/lib/soporte'

const { t, locale } = useI18n()
const soporte = useSoporteStore()
const cargando = ref(true)
const errorCarga = ref(false)
const disponible = ref(true)
const ocupado = ref(false)
const aviso = ref('')
const error = ref('')
type Ticket = { id: string; asunto: string; prioridad: string; estado: string; updated_at: string }
type Mensaje = { id: number; autor_tipo: string; texto: string; created_at: string }
const tickets = ref<Ticket[]>([])
const abierto = ref<Ticket | null>(null)
const mensajes = ref<Mensaje[]>([])
const cargandoConv = ref(false)
const borrador = ref({ asunto: '', prioridad: 'normal', texto: '' })
const respuesta = ref('')
const errorRespuesta = ref('')
const intentoEnvio = ref(false)
// Los errores de cada campo se ven al intentar enviar, no mientras se escribe por primera vez
const errores = computed(() => intentoEnvio.value ? validarTicket(borrador.value) : {})

async function cargar() {
  cargando.value = true; errorCarga.value = false
  disponible.value = await soporte.asegurar()
  if (!disponible.value) { cargando.value = false; return }
  const { data, error: e } = await supabase.from('adn_tickets').select('id, asunto, prioridad, estado, updated_at').order('updated_at', { ascending: false })
  if (e) errorCarga.value = true
  else tickets.value = (data ?? []) as Ticket[]
  cargando.value = false
}

async function crear() {
  aviso.value = ''; error.value = ''; intentoEnvio.value = true
  if (Object.keys(validarTicket(borrador.value)).length) return
  ocupado.value = true
  const { data, error: e } = await supabase.rpc('adn_ticket_crear', { p_asunto: borrador.value.asunto.trim(), p_prioridad: borrador.value.prioridad, p_texto: borrador.value.texto.trim() })
  ocupado.value = false
  if (e) { error.value = t(errorDeSoporte(e)); return }
  borrador.value = { asunto: '', prioridad: 'normal', texto: '' }; intentoEnvio.value = false
  aviso.value = t('soporte.creado')
  await cargar()
  const nuevo = tickets.value.find(x => x.id === data)
  if (nuevo) await abrir(nuevo)
}

async function abrir(tk: Ticket) {
  if (abierto.value?.id === tk.id) { abierto.value = null; return }
  abierto.value = tk; mensajes.value = []; respuesta.value = ''; errorRespuesta.value = ''; cargandoConv.value = true
  const { data, error: e } = await supabase.from('adn_ticket_mensajes').select('id, autor_tipo, texto, created_at').eq('ticket_id', tk.id).order('id')
  cargandoConv.value = false
  if (e) { error.value = t('soporte.errorCarga'); return }
  mensajes.value = (data ?? []) as Mensaje[]
}

async function responder() {
  const tk = abierto.value
  if (!tk || ocupado.value) return
  aviso.value = ''; error.value = ''
  const e0 = validarMensaje(respuesta.value)
  errorRespuesta.value = e0 ?? ''
  if (e0) return
  ocupado.value = true
  const { error: e } = await supabase.from('adn_ticket_mensajes').insert({ ticket_id: tk.id, texto: respuesta.value.trim() })
  ocupado.value = false
  if (e) { error.value = t(errorDeSoporte(e)); return }
  respuesta.value = ''
  aviso.value = t('soporte.respuestaEnviada')
  await cargar()
  const actual = tickets.value.find(x => x.id === tk.id)
  abierto.value = null
  if (actual) await abrir(actual)
}

onMounted(cargar)
</script>
