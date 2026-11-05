<template>
  <div class="min-h-screen bg-gradient-to-br from-adn-verde to-adn-oscuro flex items-center justify-center p-4">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-8">
      <!-- Logo -->
      <div class="text-center mb-8">
        <div class="w-16 h-16 bg-adn-verde rounded-2xl flex items-center justify-center mx-auto mb-4">
          <span class="text-white text-3xl font-bold">V</span>
        </div>
        <h1 class="text-2xl font-bold text-adn-verde">ViveADN</h1>
        <p class="text-gray-500 text-sm mt-1">{{ t('login.subtitulo') }}</p>
      </div>

      <!-- Formulario login -->
      <form v-if="!modoRecuperar" @submit.prevent="handleLogin" class="space-y-5">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('login.correo') }}</label>
          <input
            v-model="email"
            type="email"
            required
            :placeholder="t('login.correoEjemplo')"
            class="w-full px-4 py-3 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde focus:border-transparent transition"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('login.contrasena') }}</label>
          <CampoContrasena v-model="password" required placeholder="••••••••" autocomplete="current-password" />
        </div>

        <div v-if="error" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">
          {{ t(error) }}
        </div>

        <button
          type="submit"
          :disabled="loading"
          class="w-full btn-primary py-3 text-base disabled:opacity-60 disabled:cursor-not-allowed"
        >
          <span v-if="loading">{{ t('login.entrando') }}</span>
          <span v-else>{{ t('login.entrar') }}</span>
        </button>

        <div class="text-center">
          <button
            type="button"
            @click="modoRecuperar = true"
            class="text-sm text-adn-verde hover:underline"
          >
            {{ t('login.olvidaste') }}
          </button>
        </div>
      </form>

      <!-- Formulario recuperar contraseña -->
      <form v-else @submit.prevent="handleRecuperar" class="space-y-5">
        <div class="text-center mb-2">
          <h2 class="text-lg font-semibold text-gray-800">{{ t('login.recuperarTitulo') }}</h2>
          <p class="text-sm text-gray-500 mt-1">{{ t('login.recuperarTexto') }}</p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('login.correo') }}</label>
          <input
            v-model="email"
            type="email"
            required
            :placeholder="t('login.correoEjemplo')"
            class="w-full px-4 py-3 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde focus:border-transparent transition"
          />
        </div>

        <div v-if="error" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">
          {{ t(error) }}
        </div>

        <div v-if="exito" class="bg-green-50 text-green-700 text-sm px-4 py-3 rounded-lg border border-green-200">
          <CircleCheck class="w-4 h-4 inline -mt-0.5 mr-1" aria-hidden="true" /><I18nT keypath="login.enlaceEnviado" tag="span" scope="global"><template #correo><strong>{{ email }}</strong></template></I18nT>
        </div>

        <button
          v-if="!exito"
          type="submit"
          :disabled="loading"
          class="w-full btn-primary py-3 text-base disabled:opacity-60 disabled:cursor-not-allowed"
        >
          <span v-if="loading">{{ t('comun.enviando') }}</span>
          <span v-else>{{ t('login.enviarEnlace') }}</span>
        </button>

        <div class="text-center">
          <button
            type="button"
            @click="modoRecuperar = false; error = ''; exito = false"
            class="text-sm text-adn-verde hover:underline"
          >
            {{ t('login.volver') }}
          </button>
        </div>
      </form>

      <p v-if="!modoRecuperar" class="text-center text-sm text-gray-500 mt-5">
        {{ t('registro.enlaceLogin') }}
        <RouterLink :to="{ name: 'registro' }" class="text-adn-verde font-medium hover:underline">{{ t('registro.enlaceLoginAccion') }}</RouterLink>
      </p>

      <SelectorIdioma id="selector-idioma-login" class="mt-6 max-w-xs mx-auto" />

      <p class="text-center text-xs text-gray-400 mt-4">
        © 2026 ViveADN
      </p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { CircleCheck } from '@lucide/vue'
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { I18nT, useI18n } from 'vue-i18n'
import SelectorIdioma from '@/components/SelectorIdioma.vue'
import CampoContrasena from '@/components/CampoContrasena.vue'
import { useAuthStore } from '@/stores/auth'
import { supabase } from '@/lib/supabase'

const auth = useAuthStore()
const router = useRouter()
const { t } = useI18n()

const email = ref('')
const password = ref('')
// Clave de traducción del error visible ('' = sin error)
const error = ref('')
const loading = ref(false)
const modoRecuperar = ref(false)
const exito = ref(false)

async function handleLogin() {
  error.value = ''
  loading.value = true
  try {
    await auth.login(email.value, password.value)
    router.push('/')
  } catch (e: any) {
    error.value = 'login.errorCredenciales'
  } finally {
    loading.value = false
  }
}

async function handleRecuperar() {
  error.value = ''
  exito.value = false
  loading.value = true
  try {
    const { error: err } = await supabase.auth.resetPasswordForEmail(email.value, {
      redirectTo: `${window.location.origin}/reset-password`,
    })
    if (err) throw err
    exito.value = true
  } catch (e: any) {
    error.value = 'login.errorEnvio'
  } finally {
    loading.value = false
  }
}
</script>
