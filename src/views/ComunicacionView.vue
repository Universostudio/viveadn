<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('comunicacion.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('comunicacion.subtitulo') }}</p>
    </div>

    <!-- Aviso honesto: el envío va a un buzón de pruebas, no a las personas -->
    <div class="flex items-start gap-3 bg-amber-50 border border-amber-200 text-amber-900 rounded-xl px-4 py-3 text-sm" role="note">
      <Info class="w-5 h-5 flex-shrink-0 mt-0.5" aria-hidden="true" />
      <p>{{ t('comunicacion.avisoSumidero') }}</p>
    </div>

    <p v-if="!puedeEnviar" class="text-sm text-gray-500">{{ t('comunicacion.soloLectura') }}</p>

    <!-- Canales -->
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <button
        v-for="canal in canales"
        :key="canal.id"
        type="button"
        @click="mensaje.canal = canal.id"
        :aria-pressed="mensaje.canal === canal.id"
        :class="['card text-left cursor-pointer transition-all hover:shadow-md', mensaje.canal === canal.id ? 'ring-2 ring-adn-verde' : '']"
      >
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-lg bg-adn-verde/10 flex items-center justify-center flex-shrink-0">
            <component :is="canal.icono" class="w-5 h-5 text-adn-verde" aria-hidden="true" />
          </div>
          <div>
            <p class="font-semibold text-gray-900">{{ t(`comunicacion.canales.${canal.id}.nombre`) }}</p>
            <p class="text-xs text-gray-500">{{ t(`comunicacion.canales.${canal.id}.descripcion`) }}</p>
          </div>
        </div>
      </button>
    </div>
    <p class="text-xs text-gray-400 -mt-3">{{ t('comunicacion.notificacionNoDisponible') }}</p>

    <!-- Composición de mensaje -->
    <div class="card">
      <h2 class="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
        <PenLine class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('comunicacion.nuevoMensaje') }}
      </h2>

      <div class="space-y-4">
        <!-- Destinatarios -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">{{ t('comunicacion.destinatarios') }}</label>
          <div class="flex gap-2 flex-wrap mb-2">
            <button
              v-for="seg in segmentos"
              :key="seg.valor"
              type="button"
              @click="mensaje.segmento = seg.valor"
              :aria-pressed="mensaje.segmento === seg.valor"
              :class="['text-xs px-3 py-1.5 rounded-full border transition-colors inline-flex items-center gap-1.5',
                mensaje.segmento === seg.valor ? 'border-adn-verde bg-adn-verde/10 text-adn-verde font-medium' : 'border-gray-200 text-gray-600 hover:border-gray-300']"
            >
              <component :is="seg.icono" class="w-3.5 h-3.5" aria-hidden="true" />
              {{ t(`comunicacion.segmentos.${seg.valor}`) }}
            </button>
          </div>
          <p v-if="!puedeEnviar" class="text-xs text-gray-400">{{ t('comunicacion.numeroExacto') }}</p>
          <p v-else-if="cargandoConteo" class="text-xs text-gray-400">{{ t('comun.cargando') }}</p>
          <p v-else-if="errorConteo" class="text-xs text-red-600" role="alert">{{ errorConteo }}</p>
          <p v-else-if="conteo" class="text-xs text-gray-500">
            <span class="font-semibold text-gray-800">{{ t('comunicacion.recibiran', { n: conteo.recibiran }) }}</span>
            <span v-if="omitidosTotal > 0">
              · {{ t('comunicacion.seOmitiran', { n: omitidosTotal }) }}
              ({{ detalleOmitidos(conteo) }})
            </span>
          </p>
        </div>

        <!-- Asunto (correo) -->
        <div v-if="mensaje.canal === 'email'">
          <label for="asunto" class="block text-sm font-medium text-gray-700 mb-1">{{ t('comunicacion.asuntoCampo') }}</label>
          <input
            id="asunto"
            v-model="mensaje.asunto"
            type="text"
            maxlength="200"
            class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm"
          />
        </div>

        <!-- Mensaje -->
        <div>
          <div class="flex items-center justify-between mb-1 gap-2 flex-wrap">
            <label for="texto" class="block text-sm font-medium text-gray-700">{{ t('comunicacion.mensaje') }}</label>
            <div class="flex gap-3">
              <button
                v-for="p in plantillas"
                :key="p"
                type="button"
                @click="mensaje.texto = textoPlantilla(p)"
                class="text-xs text-adn-verde hover:underline"
              >
                {{ t(`comunicacion.plantillas.${p}.nombre`) }}
              </button>
            </div>
          </div>
          <textarea
            id="texto"
            v-model="mensaje.texto"
            rows="5"
            :placeholder="placeholderMensaje"
            class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm resize-none"
          ></textarea>
          <p class="text-xs text-gray-400 mt-1">
            {{ t('comunicacion.caracteres', mensaje.texto.length) }}
            <span v-if="mensaje.canal === 'whatsapp'"> · {{ t('comunicacion.limiteWhatsapp') }}</span>
          </p>
        </div>

        <p v-if="errorEnvio" class="text-sm text-red-600" role="alert">{{ errorEnvio }}</p>

        <!-- Resultado del último envío -->
        <div v-if="resultado" class="rounded-lg border border-emerald-200 bg-emerald-50 text-emerald-900 text-sm p-3" role="status">
          <p class="font-medium">{{ t('comunicacion.resultadoTitulo', { n: resultado.enviados }) }}</p>
          <p v-if="resultado.omitidosTotal > 0" class="mt-0.5">
            {{ t('comunicacion.resultadoOmitidos', { n: resultado.omitidosTotal }) }}
            ({{ detalleOmitidos(resultado.omitidos) }})
          </p>
          <p class="mt-0.5 text-xs opacity-80">{{ t('comunicacion.resultadoBuzon') }}</p>
        </div>

        <!-- Acciones -->
        <div class="flex items-center justify-end gap-3 pt-2 flex-wrap">
          <button type="button" @click="previsualizar = true" :disabled="!mensaje.texto.trim()" class="btn-secondary text-sm inline-flex items-center gap-2 disabled:opacity-50">
            <Eye class="w-4 h-4" aria-hidden="true" /> {{ t('comunicacion.vistaPrevia') }}
          </button>
          <button
            type="button"
            :disabled="!puedeEnviar || !listoParaEnviar || enviando"
            :title="puedeEnviar ? '' : t('comunicacion.soloLectura')"
            @click="confirmar = true"
            class="btn-primary text-sm inline-flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Send class="w-4 h-4" aria-hidden="true" /> {{ enviando ? t('comunicacion.enviando') : t('comunicacion.enviar') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Historial -->
    <div class="card">
      <h2 class="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
        <History class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('comunicacion.historial') }}
      </h2>

      <p v-if="errorHistorial" class="text-sm text-red-600" role="alert">{{ errorHistorial }}</p>
      <div v-else-if="historial.length === 0" class="py-8 text-center text-gray-400">
        <Inbox class="w-10 h-10 mx-auto mb-2 text-gray-300" aria-hidden="true" />
        <p class="text-sm">{{ t('comunicacion.sinEnvios') }}</p>
      </div>

      <ul v-else class="divide-y divide-gray-100">
        <li v-for="h in historial" :key="h.id" class="py-3">
          <button type="button" class="w-full text-left" @click="abrir(h.id)" :aria-expanded="abierto === h.id">
            <div class="flex items-center justify-between gap-3 flex-wrap">
              <div class="min-w-0">
                <p class="text-sm font-medium text-gray-900 truncate">
                  {{ h.asunto || t('comunicacion.sinAsunto') }}
                </p>
                <p class="text-xs text-gray-500">
                  {{ t(`comunicacion.canales.${h.canal}.nombre`) }} ·
                  {{ t(`comunicacion.segmentos.${h.segmento}`) }} ·
                  {{ formatoFecha(new Date(h.created_at), { day: 'numeric', month: 'short', year: 'numeric' }) }}
                </p>
              </div>
              <p class="text-xs text-gray-600">
                {{ t('comunicacion.enviadosDeTotal', { enviados: h.enviados, total: h.total }) }}
              </p>
            </div>
          </button>

          <div v-if="abierto === h.id" class="mt-3 bg-gray-50 rounded-lg p-3 text-xs space-y-2">
            <p class="text-gray-500">{{ t('comunicacion.buzonPruebas') }}</p>
            <p v-if="cargandoDetalle" class="text-gray-400">{{ t('comun.cargando') }}</p>
            <p v-else-if="detalle.length === 0" class="text-gray-400">{{ t('comunicacion.sinDetalle') }}</p>
            <ul v-else class="space-y-2 max-h-72 overflow-y-auto">
              <li v-for="d in detalle" :key="d.id" class="border border-gray-200 bg-white rounded-md p-2">
                <p class="font-medium text-gray-800">
                  {{ d.destino || t('comunicacion.sinDestinoEtiqueta') }}
                  <span :class="['ml-2 px-1.5 py-0.5 rounded-full', d.estado === 'enviado' ? 'bg-emerald-100 text-emerald-800' : 'bg-gray-200 text-gray-700']">
                    {{ d.estado === 'enviado' ? t('comunicacion.estado.enviado') : t(`comunicacion.motivo.${d.motivo}`) }}
                  </span>
                </p>
                <p v-if="d.texto_final" class="text-gray-600 whitespace-pre-wrap mt-1">{{ d.texto_final }}</p>
              </li>
            </ul>
          </div>
        </li>
      </ul>
    </div>

    <!-- Modal: Vista previa -->
    <div
      v-if="previsualizar"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="previsualizar = false"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-sm p-6" role="dialog" aria-modal="true" :aria-label="t('comunicacion.vistaPrevia')">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-bold text-gray-900">{{ t('comunicacion.vistaPrevia') }}</h2>
          <button type="button" @click="previsualizar = false" class="text-gray-400 hover:text-gray-600" :aria-label="t('comun.cerrar')">
            <X class="w-5 h-5" aria-hidden="true" />
          </button>
        </div>

        <div v-if="mensaje.canal === 'whatsapp'" class="bg-[#ECE5DD] rounded-xl p-4">
          <div class="bg-white rounded-xl rounded-tl-none px-4 py-3 shadow-sm max-w-xs ml-auto">
            <p class="text-sm text-gray-800 whitespace-pre-wrap">{{ mensajePersonalizado }}</p>
            <p class="text-xs text-gray-400 text-right mt-1 inline-flex items-center gap-1 w-full justify-end">
              {{ horaActual }} <CheckCheck class="w-3.5 h-3.5" aria-hidden="true" />
            </p>
          </div>
        </div>

        <div v-else class="border border-gray-200 rounded-xl p-4">
          <p class="text-xs text-gray-400 mb-2">{{ t('comunicacion.para', { correo: t('comunicacion.correoEjemplo') }) }}</p>
          <p class="text-xs text-gray-400 mb-3">{{ t('comunicacion.asunto', { asunto: mensaje.asunto || t('comunicacion.sinAsunto') }) }}</p>
          <p class="text-sm text-gray-800 whitespace-pre-wrap">{{ mensajePersonalizado }}</p>
        </div>

        <p class="text-xs text-gray-400 text-center mt-3">{{ t('comunicacion.datosEjemplo') }}</p>
      </div>
    </div>

    <!-- Modal: Confirmar envío -->
    <div
      v-if="confirmar"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="confirmar = false"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6" role="dialog" aria-modal="true" :aria-label="t('comunicacion.confirmarTitulo')">
        <h2 class="text-lg font-bold text-gray-900 mb-2">{{ t('comunicacion.confirmarTitulo') }}</h2>
        <p class="text-sm text-gray-700">
          {{ t('comunicacion.confirmarTexto', {
            n: conteo?.recibiran ?? 0,
            canal: t(`comunicacion.canales.${mensaje.canal}.nombre`),
            segmento: t(`comunicacion.segmentos.${mensaje.segmento}`),
          }) }}
        </p>
        <p class="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-lg p-2 mt-3">{{ t('comunicacion.confirmarSumidero') }}</p>
        <div class="flex justify-end gap-3 mt-5">
          <button type="button" class="btn-secondary text-sm" @click="confirmar = false">{{ t('comun.cancelar') }}</button>
          <button type="button" class="btn-primary text-sm" @click="enviar">{{ t('comunicacion.confirmarAccion') }}</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue'
import {
  Info, MessageCircle, Mail, PenLine, Users, Sprout, Star, HeartHandshake,
  Eye, Send, History, Inbox, X, CheckCheck,
} from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useI18n } from 'vue-i18n'
import { formatoHora, formatoFecha } from '@/i18n'

interface Conteo { total: number; recibiran: number; sin_destino: number; baja: number; repetido: number; sin_consentimiento: number }
interface Omitidos { sin_destino: number; baja: number; repetido: number; sin_consentimiento: number }
interface Mensaje { id: string; canal: 'email' | 'whatsapp'; segmento: string; asunto: string | null; total: number; enviados: number; omitidos: number; created_at: string }
interface Detalle { id: string; destino: string | null; texto_final: string | null; estado: 'enviado' | 'omitido'; motivo: string | null }

const auth = useAuthStore()
const { t } = useI18n()

const previsualizar = ref(false)
const confirmar = ref(false)
const enviando = ref(false)
const errorEnvio = ref('')
const resultado = ref<{ enviados: number; omitidos: Omitidos; omitidosTotal: number } | null>(null)

const mensaje = ref({ canal: 'email' as 'email' | 'whatsapp', segmento: 'todos', asunto: '', texto: '' })

const puedeEnviar = computed(() => auth.can('comunicacion.enviar') && auth.can('miembros.ver'))

// Nombre y descripción de cada canal: comunicacion.canales.<id> en src/i18n.
// La notificación dentro de la app no existe todavía: no se ofrece.
const canales = [
  { id: 'email' as const, icono: Mail },
  { id: 'whatsapp' as const, icono: MessageCircle },
]

// Etiqueta de cada segmento: comunicacion.segmentos.<valor> en src/i18n
const segmentos = [
  { valor: 'todos', icono: Users },
  { valor: 'nuevos', icono: Sprout },
  { valor: 'lideres', icono: Star },
  { valor: 'consolidacion', icono: HeartHandshake },
]

// Plantillas rápidas del redactor (comunicacion.plantillas.<id> en src/i18n).
// Las variables {{nombre}}, {{dia}} e {{iglesia}} son códigos fijos: no se traducen.
const plantillas = ['bienvenida', 'recordatorio', 'evento']
const VARIABLES = { nombre: '{{nombre}}', dia: '{{dia}}', iglesia: '{{iglesia}}' }

function textoPlantilla(id: string) {
  return t(`comunicacion.plantillas.${id}.texto`, { ...VARIABLES })
}

const placeholderMensaje = computed(() =>
  mensaje.value.canal === 'whatsapp'
    ? t('comunicacion.placeholder.whatsapp', { variable: VARIABLES.nombre })
    : t('comunicacion.placeholder.email'),
)

const mensajePersonalizado = computed(() =>
  mensaje.value.texto
    .replace(/\{\{nombre\}\}/g, t('comunicacion.ejemploNombre'))
    .replace(/\{\{dia\}\}/g, t('comunicacion.ejemploDia'))
    .replace(/\{\{iglesia\}\}/g, auth.nombreIglesia || t('comunicacion.tuIglesia')),
)

const horaActual = computed(() => formatoHora(new Date(), { hour: '2-digit', minute: '2-digit' }))

// Vista previa de destinatarios: la calcula la base de datos con las mismas reglas del envío
const conteo = ref<Conteo | null>(null)
const cargandoConteo = ref(false)
const errorConteo = ref('')
let pedido = 0

async function actualizarConteo() {
  if (!puedeEnviar.value) return
  const este = ++pedido
  cargandoConteo.value = true
  errorConteo.value = ''
  const { data, error } = await supabase.rpc('adn_vista_previa_envio', { p_canal: mensaje.value.canal, p_segmento: mensaje.value.segmento })
  if (este !== pedido) return
  cargandoConteo.value = false
  if (error) { conteo.value = null; errorConteo.value = t('comunicacion.errorConteo'); return }
  conteo.value = data as Conteo
}

const omitidosTotal = computed(() => conteo.value ? conteo.value.sin_destino + conteo.value.baja + conteo.value.repetido + conteo.value.sin_consentimiento : 0)

function detalleOmitidos(o: Omitidos) {
  const partes: string[] = []
  if (o.sin_destino) partes.push(t('comunicacion.motivoN.sin_destino', { n: o.sin_destino }))
  if (o.baja) partes.push(t('comunicacion.motivoN.baja', { n: o.baja }))
  if (o.repetido) partes.push(t('comunicacion.motivoN.repetido', { n: o.repetido }))
  if (o.sin_consentimiento) partes.push(t('comunicacion.motivoN.sin_consentimiento', { n: o.sin_consentimiento }))
  return partes.join(', ')
}

const listoParaEnviar = computed(() => {
  const m = mensaje.value
  if (!m.texto.trim()) return false
  if (m.canal === 'email' && !m.asunto.trim()) return false
  return !!conteo.value && conteo.value.recibiran > 0
})

// Mensajes de error comprensibles para los códigos que lanza la base de datos
function textoError(msg: string) {
  if (msg.includes('ADN_LIMITE_DIARIO')) return t('comunicacion.errores.topeDiario')
  if (msg.includes('ADN_ASUNTO_INVALIDO')) return t('comunicacion.errores.asunto')
  if (msg.includes('ADN_TEXTO_INVALIDO')) return t('comunicacion.errores.texto')
  if (msg.includes('ADN_DEMASIADOS_DESTINATARIOS')) return t('comunicacion.errores.demasiados')
  if (msg.includes('ADN_SIN_PERMISO')) return t('comunicacion.errores.sinPermiso')
  if (msg.includes('ADN_DATOS_INVALIDOS')) return t('comunicacion.errores.datos')
  return t('comunicacion.errores.generico')
}

async function enviar() {
  confirmar.value = false
  if (!listoParaEnviar.value || enviando.value) return
  enviando.value = true
  errorEnvio.value = ''
  resultado.value = null
  // La clave hace el envío idempotente: repetir la petición no duplica el mensaje
  const { data, error } = await supabase.rpc('adn_enviar_mensaje', {
    p_clave: crypto.randomUUID(),
    p_canal: mensaje.value.canal,
    p_segmento: mensaje.value.segmento,
    p_asunto: mensaje.value.canal === 'email' ? mensaje.value.asunto.trim() : '',
    p_texto: mensaje.value.texto,
    p_dia: formatoFecha(new Date(), { weekday: 'long' }),
  })
  enviando.value = false
  if (error) { errorEnvio.value = textoError(error.message); return }
  const r = data as { enviados: number; omitidos: Omitidos }
  resultado.value = { enviados: r.enviados, omitidos: r.omitidos, omitidosTotal: r.omitidos.sin_destino + r.omitidos.baja + r.omitidos.repetido + r.omitidos.sin_consentimiento }
  mensaje.value.texto = ''
  await Promise.all([cargarHistorial(), actualizarConteo()])
}

// Historial y buzón de pruebas
const historial = ref<Mensaje[]>([])
const errorHistorial = ref('')
const abierto = ref<string | null>(null)
const detalle = ref<Detalle[]>([])
const cargandoDetalle = ref(false)

async function cargarHistorial() {
  if (!auth.can('comunicacion.ver')) return
  const { data, error } = await supabase
    .from('adn_mensajes')
    .select('id, canal, segmento, asunto, total, enviados, omitidos, created_at')
    .order('created_at', { ascending: false })
    .limit(20)
  if (error) { errorHistorial.value = t('comunicacion.errorHistorial'); return }
  errorHistorial.value = ''
  historial.value = (data ?? []) as Mensaje[]
}

async function abrir(id: string) {
  if (abierto.value === id) { abierto.value = null; return }
  abierto.value = id
  detalle.value = []
  cargandoDetalle.value = true
  const { data } = await supabase
    .from('adn_mensaje_destinatarios')
    .select('id, destino, texto_final, estado, motivo')
    .eq('mensaje_id', id)
    .order('estado', { ascending: true })
    .limit(200)
  if (abierto.value === id) { detalle.value = (data ?? []) as Detalle[]; cargandoDetalle.value = false }
}

watch(() => [mensaje.value.canal, mensaje.value.segmento], actualizarConteo)

onMounted(() => {
  actualizarConteo()
  cargarHistorial()
})
</script>
