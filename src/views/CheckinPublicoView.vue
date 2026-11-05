<template>
  <div class="min-h-screen bg-gradient-to-br from-adn-verde to-adn-oscuro flex items-center justify-center p-4">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-8">
      <div class="text-center mb-6">
        <div class="w-16 h-16 bg-adn-verde rounded-2xl flex items-center justify-center mx-auto mb-4">
          <ClipboardCheck class="w-8 h-8 text-white" aria-hidden="true" />
        </div>
        <h1 class="text-2xl font-bold text-adn-verde">{{ t('checkin.titulo') }}</h1>
        <p v-if="info?.iglesia" class="text-gray-900 font-semibold mt-1">{{ info.iglesia }}</p>
        <p v-if="estado === 'abierto' && info?.evento" class="text-sm text-gray-500 mt-0.5">{{ info.evento }}</p>
      </div>

      <p v-if="estado === 'cargando'" class="text-center text-gray-500 text-sm" role="status">{{ t('comun.cargando') }}</p>

      <div v-else-if="estado === 'noDisponible'" class="text-center space-y-3">
        <TriangleAlert class="w-10 h-10 mx-auto text-amber-500" aria-hidden="true" />
        <p class="text-gray-700 font-medium">{{ t('checkin.noDisponible') }}</p>
      </div>

      <div v-else-if="estado === 'cerrado'" class="text-center space-y-3">
        <Clock class="w-10 h-10 mx-auto text-amber-500" aria-hidden="true" />
        <p class="text-gray-700 font-medium">{{ t('checkin.cerrado') }}</p>
        <p class="text-sm text-gray-500">{{ t('checkin.cerradoAyuda') }}</p>
      </div>

      <div v-else-if="estado === 'lleno'" class="text-center space-y-3">
        <Users class="w-10 h-10 mx-auto text-amber-500" aria-hidden="true" />
        <p class="text-gray-700 font-medium">{{ t('checkin.lleno') }}</p>
      </div>

      <div v-else-if="estado === 'enviado'" class="text-center space-y-3" role="status">
        <CircleCheck class="w-12 h-12 mx-auto text-green-600" aria-hidden="true" />
        <p class="text-gray-900 font-semibold text-lg">{{ t('checkin.gracias') }}</p>
        <p class="text-sm text-gray-500">{{ t('checkin.graciasTexto') }}</p>
      </div>

      <form v-else @submit.prevent="enviar" class="space-y-4" novalidate>
        <div :class="info?.alias ? '' : 'grid grid-cols-2 gap-3'">
          <div>
            <label for="ck-nombre" class="block text-sm font-medium text-gray-700 mb-1">{{ info?.alias ? t('miembros.alias') : t('miembros.nombre') }}</label>
            <input id="ck-nombre" v-model="form.nombre" required maxlength="100" :autocomplete="info?.alias ? 'off' : 'given-name'" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
            <p v-if="info?.alias" class="text-xs text-gray-500 mt-1">{{ t('miembros.aliasAyuda') }}</p>
          </div>
          <div v-if="!info?.alias">
            <label for="ck-apellido" class="block text-sm font-medium text-gray-700 mb-1">{{ t('miembros.apellido') }}</label>
            <input id="ck-apellido" v-model="form.apellido" required maxlength="100" autocomplete="family-name" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
        </div>
        <div>
          <label for="ck-tel" class="block text-sm font-medium text-gray-700 mb-1">{{ t('miembros.telefono') }}</label>
          <input id="ck-tel" v-model="form.telefono" required type="tel" inputmode="tel" maxlength="30" autocomplete="tel" placeholder="+34 600 000 000" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
        </div>
        <div v-if="!info?.alias">
          <label for="ck-email" class="block text-sm font-medium text-gray-700 mb-1">{{ t('checkin.email') }}</label>
          <input id="ck-email" v-model="form.email" type="email" inputmode="email" maxlength="254" autocomplete="email" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
        </div>

        <!-- Campo trampa: fuera de la vista y del teclado; solo un robot lo rellena -->
        <div class="absolute -left-[9999px] w-px h-px overflow-hidden" aria-hidden="true">
          <label for="ck-web">Web</label>
          <input id="ck-web" v-model="form.web" name="web" tabindex="-1" autocomplete="off" />
        </div>

        <label class="flex items-start gap-2 text-sm text-gray-700">
          <input v-model="form.mayor14" type="checkbox" required class="mt-0.5 rounded border-gray-300 text-adn-verde" />
          <span>{{ t('checkin.mayor14') }}</span>
        </label>
        <label class="flex items-start gap-2 text-sm text-gray-700">
          <input v-model="form.consentimiento" type="checkbox" required class="mt-0.5 rounded border-gray-300 text-adn-verde" />
          <span>{{ t('checkin.consentimiento', { iglesia: info?.iglesia ?? '' }) }}</span>
        </label>
        <p class="text-xs text-gray-400">
          {{ t('checkin.privacidad', { iglesia: info?.iglesia ?? '' }) }}
          <template v-if="info?.contacto"> {{ t('checkin.privacidadContacto', { correo: info.contacto }) }}</template>
        </p>

        <p v-if="error" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(error) }}</p>
        <button type="submit" :disabled="enviando" class="w-full btn-primary py-3 text-base disabled:opacity-60">{{ enviando ? t('checkin.enviando') : t('checkin.enviar') }}</button>
      </form>

      <SelectorIdioma id="selector-idioma-checkin" class="mt-6 max-w-xs mx-auto" />
      <p class="text-center text-xs text-gray-400 mt-6">© 2026 ViveADN</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted, onBeforeUnmount } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ClipboardCheck, CircleCheck, Clock, TriangleAlert, Users } from '@lucide/vue'
import SelectorIdioma from '@/components/SelectorIdioma.vue'
import { supabase } from '@/lib/supabase'

const route = useRoute()
const { t } = useI18n()

const estado = ref<'cargando' | 'abierto' | 'cerrado' | 'lleno' | 'noDisponible' | 'enviado'>('cargando')
const info = ref<{ iglesia?: string; evento?: string; contacto?: string; alias?: boolean } | null>(null)
const enviando = ref(false)
const error = ref('')
const form = reactive({ nombre: '', apellido: '', telefono: '', email: '', mayor14: false, consentimiento: false, web: '' })
const token = String(route.params.token ?? '')

// La pagina lleva el enlace secreto en la direccion: que no se indexe ni se pase a otros sitios
const metas: HTMLMetaElement[] = []
function meta(nombre: string, contenido: string) {
  const m = document.createElement('meta')
  m.name = nombre
  m.content = contenido
  document.head.appendChild(m)
  metas.push(m)
}

// Codigo de error de una respuesta no exitosa de la funcion
async function codigoDe(err: unknown): Promise<string> {
  try {
    const resp = (err as { context?: Response })?.context
    if (resp?.json) return (await resp.json()).error ?? ''
  } catch { /* sin detalle */ }
  return ''
}

onMounted(async () => {
  meta('robots', 'noindex, nofollow')
  meta('referrer', 'no-referrer')
  const { data, error: err } = await supabase.functions.invoke('checkin-evento', { body: { accion: 'consultar', token } })
  if (err || !data?.estado) { estado.value = 'noDisponible'; return }
  info.value = data
  estado.value = data.estado === 'abierto' ? 'abierto' : data.estado === 'lleno' ? 'lleno' : 'cerrado'
})

onBeforeUnmount(() => metas.forEach(m => m.remove()))

async function enviar() {
  error.value = ''
  if (!form.nombre.trim() || (!info.value?.alias && !form.apellido.trim()) || !form.telefono.trim()) { error.value = 'checkin.errorDatos'; return }
  if (!form.mayor14 || !form.consentimiento) { error.value = 'checkin.errorConsentimiento'; return }
  enviando.value = true
  const { error: err } = await supabase.functions.invoke('checkin-evento', { body: { accion: 'registrar', token, ...form, ...(info.value?.alias ? { apellido: '', email: '' } : {}) } })
  enviando.value = false
  if (!err) { estado.value = 'enviado'; return }
  const codigo = await codigoDe(err)
  if (codigo === 'cerrado') estado.value = 'cerrado'
  else if (codigo === 'lleno') estado.value = 'lleno'
  else if (codigo === 'no_valido') estado.value = 'noDisponible'
  else if (codigo === 'limite') error.value = 'checkin.limite'
  else if (codigo === 'datos') error.value = 'checkin.errorDatos'
  else if (codigo === 'consentimiento') error.value = 'checkin.errorConsentimiento'
  else error.value = 'checkin.errorGenerico'
}
</script>
