<template>
  <div class="relative">
    <input
      v-bind="$attrs"
      v-model="valor"
      :type="visible ? 'text' : 'password'"
      class="w-full pl-4 pr-12 py-3 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde focus:border-transparent transition"
    />
    <button
      type="button"
      @click="visible = !visible"
      :aria-label="visible ? t('comun.ocultarContrasena') : t('comun.verContrasena')"
      :aria-pressed="visible"
      class="absolute inset-y-0 right-0 px-3 flex items-center text-gray-400 hover:text-gray-600 focus:outline-none focus-visible:text-adn-verde"
    >
      <EyeOff v-if="visible" class="w-5 h-5" aria-hidden="true" />
      <Eye v-else class="w-5 h-5" aria-hidden="true" />
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { Eye, EyeOff } from '@lucide/vue'

// El input recibe el resto de atributos (required, minlength, autocomplete, placeholder, id...)
defineOptions({ inheritAttrs: false })
const valor = defineModel<string>({ default: '' })
const { t } = useI18n()
const visible = ref(false)
</script>
