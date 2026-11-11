<template>
  <div class="min-h-screen bg-gradient-to-br from-adn-verde to-adn-oscuro flex items-center justify-center p-4">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-lg p-6 sm:p-8">
      <div class="text-center mb-6">
        <LogoAdn class="w-12 h-auto mx-auto mb-3 text-adn-verde" />
        <h1 class="text-2xl font-bold text-adn-verde">{{ t('registro.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-1">{{ t('registro.subtitulo') }}</p>
      </div>

      <p v-if="estado === 'cargando'" class="py-8 text-center text-sm text-gray-400" role="status">{{ t('comun.cargando') }}</p>

      <div v-else-if="estado === 'cerrado'" class="text-center py-6">
        <p class="font-medium text-gray-800">{{ t('registro.cerradoTitulo') }}</p>
        <p class="text-sm text-gray-500 mt-1">{{ t('registro.cerradoTexto') }}</p>
        <RouterLink :to="{ name: 'login' }" class="btn-secondary inline-block mt-5">{{ t('registro.irAlAcceso') }}</RouterLink>
      </div>

      <div v-else-if="estado === 'enviado'" class="text-center py-4" role="status">
        <div class="w-12 h-12 rounded-full bg-green-100 text-green-700 flex items-center justify-center mx-auto mb-3"><MailCheck class="w-6 h-6" aria-hidden="true" /></div>
        <p class="font-semibold text-gray-900">{{ t('registro.exitoTitulo') }}</p>
        <p class="text-sm text-gray-600 mt-2">{{ t('registro.exitoTexto') }}</p>
        <p class="text-xs text-gray-400 mt-3">{{ t('registro.exitoAyuda') }}</p>
        <RouterLink :to="{ name: 'login' }" class="btn-secondary inline-block mt-5">{{ t('registro.irAlAcceso') }}</RouterLink>
      </div>

      <form v-else @submit.prevent="enviar" class="space-y-5" novalidate>
        <fieldset class="space-y-3">
          <legend class="text-sm font-semibold text-gray-900 mb-1">{{ t('registro.tuIglesia') }}</legend>
          <div>
            <label for="rg-nombre" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.nombreIglesia') }}</label>
            <input id="rg-nombre" v-model="form.nombre" maxlength="80" required autocomplete="organization" class="campo" @input="sugerirDireccion" />
          </div>
          <div>
            <label for="rg-slug" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.direccion') }}</label>
            <input id="rg-slug" v-model="form.slug" maxlength="40" required autocapitalize="none" spellcheck="false" class="campo font-mono" @input="direccionEditada = true" />
            <p class="text-xs text-gray-400 mt-1">{{ t('registro.direccionAyuda', { ejemplo: form.slug || 'tu-iglesia' }) }}</p>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label for="rg-pais" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.pais') }}</label>
              <input id="rg-pais" v-model="form.pais" maxlength="80" required autocomplete="country-name" class="campo" />
            </div>
            <div>
              <label for="rg-ciudad" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.ciudad') }}</label>
              <input id="rg-ciudad" v-model="form.ciudad" maxlength="80" required autocomplete="address-level2" class="campo" />
            </div>
          </div>
        </fieldset>

        <fieldset class="space-y-3">
          <legend class="text-sm font-semibold text-gray-900 mb-1">{{ t('registro.tuCuenta') }}</legend>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label for="rg-pnombre" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.nombre') }}</label>
              <input id="rg-pnombre" v-model="form.pnombre" maxlength="60" required autocomplete="given-name" class="campo" />
            </div>
            <div>
              <label for="rg-papellido" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.apellido') }}</label>
              <input id="rg-papellido" v-model="form.papellido" maxlength="60" required autocomplete="family-name" class="campo" />
            </div>
          </div>
          <div>
            <label for="rg-email" class="block text-sm font-medium text-gray-700 mb-1">{{ t('login.correo') }}</label>
            <input id="rg-email" v-model="form.email" type="email" maxlength="254" required autocomplete="email" class="campo" />
            <p class="text-xs text-gray-400 mt-1">{{ t('registro.correoAyuda') }}</p>
          </div>
          <div v-if="requiereCodigo">
            <label for="rg-codigo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.codigo') }}</label>
            <input id="rg-codigo" v-model="form.codigo" maxlength="20" required autocapitalize="characters" spellcheck="false" placeholder="ADN-XXXX-XXXX" class="campo font-mono uppercase" />
            <p class="text-xs text-gray-400 mt-1">{{ t('registro.codigoAyuda') }}</p>
          </div>
        </fieldset>

        <!-- Campo trampa: las personas no lo ven -->
        <div class="absolute -left-[9999px]" aria-hidden="true">
          <label for="rg-web">Web</label>
          <input id="rg-web" v-model="form.web" tabindex="-1" autocomplete="off" />
        </div>

        <label class="flex items-start gap-2 text-sm text-gray-700">
          <input v-model="form.consentimiento" type="checkbox" class="mt-1" />
          <span>{{ t('registro.consentimiento') }} <RouterLink to="/privacidad" target="_blank" class="underline text-adn-verde">{{ t('legal.privacidad') }}</RouterLink> · <RouterLink to="/terminos" target="_blank" class="underline text-adn-verde">{{ t('legal.terminos') }}</RouterLink></span>
        </label>

        <p v-if="error" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(error) }}</p>

        <button type="submit" :disabled="enviando" class="w-full btn-primary py-3 text-base disabled:opacity-60">
          {{ enviando ? t('registro.enviando') : t('registro.enviar') }}
        </button>
        <p class="text-center text-sm text-gray-500">
          {{ t('registro.yaTienes') }} <RouterLink :to="{ name: 'login' }" class="text-adn-verde font-medium hover:underline">{{ t('registro.irAlAcceso') }}</RouterLink>
        </p>
      </form>

      <div class="mt-6 flex justify-center"><SelectorIdioma /></div>
      <PieLegal class="mt-4" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { reactive, ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { MailCheck } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import LogoAdn from '@/components/LogoAdn.vue'
import SelectorIdioma from '@/components/SelectorIdioma.vue'
import PieLegal from '@/components/PieLegal.vue'

const { t } = useI18n()
const estado = ref<'cargando' | 'abierto' | 'cerrado' | 'enviado'>('cargando')
const requiereCodigo = ref(true)
const enviando = ref(false)
const error = ref('')
const direccionEditada = ref(false)
const form = reactive({ nombre: '', slug: '', pais: '', ciudad: '', pnombre: '', papellido: '', email: '', codigo: '', web: '', consentimiento: false })

// La direccion corta se propone a partir del nombre, sin tildes, hasta que la persona la cambie
const aDireccion = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40).replace(/-+$/, '')
function sugerirDireccion() { if (!direccionEditada.value) form.slug = aDireccion(form.nombre) }

async function codigoDe(err: unknown): Promise<string> {
  try {
    const resp = (err as { context?: Response })?.context
    if (resp?.json) return (await resp.json()).error ?? ''
  } catch { /* sin detalle */ }
  return ''
}

onMounted(async () => {
  const { data, error: err } = await supabase.functions.invoke('registro-iglesia', { body: { accion: 'consultar' } })
  if (err || typeof data?.abierto !== 'boolean') { estado.value = 'cerrado'; return }
  requiereCodigo.value = data.requiere_codigo !== false
  estado.value = data.abierto ? 'abierto' : 'cerrado'
})

async function enviar() {
  error.value = ''
  if (!form.consentimiento) { error.value = 'registro.errores.consentimiento'; return }
  enviando.value = true
  const { error: err } = await supabase.functions.invoke('registro-iglesia', {
    body: {
      accion: 'registrar', web: form.web, consentimiento: form.consentimiento, codigo: form.codigo,
      iglesia: { nombre: form.nombre, slug: form.slug, pais: form.pais, ciudad: form.ciudad },
      propietario: { nombre: form.pnombre, apellido: form.papellido, email: form.email },
    },
  })
  enviando.value = false
  if (!err) { estado.value = 'enviado'; return }
  const c = await codigoDe(err)
  if (c === 'cerrado') estado.value = 'cerrado'
  else if (['datos', 'consentimiento', 'codigo', 'slug', 'limite'].includes(c)) error.value = `registro.errores.${c}`
  else error.value = 'registro.errores.generico'
}
</script>

<style scoped>
.campo { @apply w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde; }
</style>
