<template>
  <div class="min-h-screen bg-gradient-to-br from-adn-verde to-adn-oscuro flex items-center justify-center p-4">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-8">
      <div class="text-center mb-6">
        <div class="w-16 h-16 bg-adn-verde rounded-2xl flex items-center justify-center mx-auto mb-4">
          <span class="text-white text-3xl font-bold">V</span>
        </div>
        <h1 class="text-2xl font-bold text-adn-verde">Vive ADN</h1>
      </div>

      <p v-if="estado === 'cargando'" class="text-center text-gray-500 text-sm">{{ t('invitacion.comprobando') }}</p>

      <div v-else-if="estado === 'invalida'" class="text-center space-y-3">
        <TriangleAlert class="w-10 h-10 mx-auto text-amber-500" aria-hidden="true" />
        <p class="text-gray-700 font-medium">{{ t('invitacion.invalida') }}</p>
        <p class="text-sm text-gray-500">{{ t('invitacion.pideNueva') }}</p>
      </div>

      <form v-else-if="estado === 'lista'" @submit.prevent="aceptar" class="space-y-5">
        <div class="text-center">
          <p class="text-gray-900 font-semibold">{{ t('invitacion.hola', { nombre: datos.nombre }) }}</p>
          <p class="text-sm text-gray-500 mt-1">{{ t('invitacion.te', { iglesia: datos.iglesia, rol: datos.rol }) }}</p>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('invitacion.elige') }}</label>
          <CampoContrasena v-model="password" required minlength="10" autocomplete="new-password" :placeholder="t('invitacion.minimo')" />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('reset.confirmar') }}</label>
          <CampoContrasena v-model="confirmar" required autocomplete="new-password" />
        </div>
        <div v-if="error" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ error }}</div>
        <button type="submit" :disabled="enviando" class="w-full btn-primary py-3 text-base disabled:opacity-60">
          {{ enviando ? t('comun.guardando') : t('invitacion.aceptar') }}
        </button>
        <p class="text-xs text-gray-400 text-center">{{ t('invitacion.unSoloUso') }}</p>
      </form>

      <PieLegal class="mt-4" />
    </div>
  </div>
</template>

<script setup lang="ts">
import PieLegal from '@/components/PieLegal.vue'
import { TriangleAlert } from '@lucide/vue'
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { supabase } from '@/lib/supabase'
import CampoContrasena from '@/components/CampoContrasena.vue'

const router = useRouter()
const { t } = useI18n()
const estado = ref<'cargando' | 'lista' | 'invalida'>('cargando')
const datos = ref({ nombre: '', iglesia: '', rol: '' })
const password = ref('')
const confirmar = ref('')
const error = ref('')
const enviando = ref(false)
let token = ''

async function motivoDe(error: unknown, defecto: string) {
  try {
    const resp = (error as { context?: Response }).context
    if (resp?.json) return (await resp.json()).error ?? defecto
  } catch { /* se usa el mensaje por defecto */ }
  return defecto
}

// El token va en el fragmento (#t=...): no se envía al servidor web ni queda en registros ni en Referer.
// Solo abrir la página NO gasta la invitación: se gasta al pulsar el botón.
onMounted(async () => {
  token = new URLSearchParams(window.location.hash.slice(1)).get('t') ?? ''
  history.replaceState(null, '', window.location.pathname)
  if (!token) { estado.value = 'invalida'; return }
  const { data, error: e } = await supabase.functions.invoke('invitaciones', { body: { accion: 'consultar', token } })
  if (e || !data?.nombre) { estado.value = 'invalida'; return }
  datos.value = data
  estado.value = 'lista'
})

async function aceptar() {
  error.value = ''
  if (password.value !== confirmar.value) { error.value = t('reset.noCoinciden'); return }
  enviando.value = true
  const { data, error: e } = await supabase.functions.invoke('invitaciones', { body: { accion: 'aceptar', token, password: password.value } })
  if (e || !data?.ok) {
    error.value = await motivoDe(e, t('invitacion.errorGenerico'))
    enviando.value = false
    return
  }
  const { error: eLogin } = await supabase.auth.signInWithPassword({ email: data.email, password: password.value })
  enviando.value = false
  if (eLogin) { router.push('/login'); return }
  router.push('/')
}
</script>
