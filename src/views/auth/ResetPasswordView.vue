<template>
  <div class="min-h-screen bg-gradient-to-br from-adn-verde to-adn-oscuro flex items-center justify-center p-4">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-8">
      <!-- Logo -->
      <div class="text-center mb-8">
        <div class="w-16 h-16 bg-adn-verde rounded-2xl flex items-center justify-center mx-auto mb-4">
          <span class="text-white text-3xl font-bold">V</span>
        </div>
        <h1 class="text-2xl font-bold text-adn-verde">ViveADN</h1>
        <p class="text-gray-500 text-sm mt-1">{{ t('reset.titulo') }}</p>
      </div>

      <form v-if="!exito" @submit.prevent="handleReset" class="space-y-5">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('reset.nueva') }}</label>
          <CampoContrasena v-model="password" required minlength="8" autocomplete="new-password" :placeholder="t('reset.minimo')" />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('reset.confirmar') }}</label>
          <CampoContrasena v-model="confirmar" required autocomplete="new-password" :placeholder="t('reset.repite')" />
        </div>

        <div v-if="error" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">
          {{ t(error) }}
        </div>

        <button
          type="submit"
          :disabled="loading"
          class="w-full btn-primary py-3 text-base disabled:opacity-60 disabled:cursor-not-allowed"
        >
          <span v-if="loading">{{ t('comun.guardando') }}</span>
          <span v-else>{{ t('reset.guardar') }}</span>
        </button>
      </form>

      <div v-else class="text-center space-y-4">
        <CircleCheck class="w-12 h-12 mx-auto text-emerald-500" aria-hidden="true" />
        <p class="text-gray-700 font-medium">{{ t('reset.actualizada') }}</p>
        <button @click="router.push('/login')" class="btn-primary px-6 py-2">
          {{ t('reset.irLogin') }}
        </button>
      </div>

      <p class="text-center text-xs text-gray-400 mt-6">
        © 2026 ViveADN
      </p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { CircleCheck } from '@lucide/vue'
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { supabase } from '@/lib/supabase'
import CampoContrasena from '@/components/CampoContrasena.vue'

const router = useRouter()
const { t } = useI18n()
const password = ref('')
const confirmar = ref('')
// Clave de traducción del error visible ('' = sin error)
const error = ref('')
const loading = ref(false)
const exito = ref(false)

async function handleReset() {
  error.value = ''
  if (password.value !== confirmar.value) {
    error.value = 'reset.noCoinciden'
    return
  }
  loading.value = true
  try {
    const { error: err } = await supabase.auth.updateUser({ password: password.value })
    if (err) throw err
    exito.value = true
  } catch (e: any) {
    error.value = 'reset.errorActualizar'
  } finally {
    loading.value = false
  }
}
</script>
