<template>
  <div class="min-h-screen bg-gradient-to-br from-adn-verde to-adn-oscuro flex items-center justify-center p-4">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-8 text-center">
      <template v-if="estado === 'confirmar' || estado === 'enviando'">
        <MailX class="w-14 h-14 mx-auto mb-3 text-adn-verde" aria-hidden="true" />
        <h1 class="text-xl font-bold text-gray-900">{{ t('baja.titulo') }}</h1>
        <p class="text-sm text-gray-500 mt-1">{{ t('baja.texto') }}</p>
        <!-- Confirmación explícita: abrir el enlace no gasta nada, solo este botón da de baja -->
        <button type="button" class="btn-primary mt-6 w-full disabled:opacity-50" :disabled="estado === 'enviando'" @click="confirmar">
          {{ estado === 'enviando' ? t('comun.enviando') : t('baja.boton') }}
        </button>
      </template>

      <template v-else-if="estado === 'hecho'">
        <CircleCheck class="w-14 h-14 mx-auto mb-3 text-green-600" aria-hidden="true" />
        <h1 class="text-xl font-bold text-gray-900">{{ t('baja.hecho') }}</h1>
        <p class="text-sm text-gray-500 mt-1">{{ t(`baja.hechoTexto.${canal}`) }}</p>
      </template>

      <template v-else>
        <TriangleAlert class="w-14 h-14 mx-auto mb-3 text-amber-500" aria-hidden="true" />
        <h1 class="text-xl font-bold text-gray-900">{{ t(`baja.${estado}`) }}</h1>
        <p class="text-sm text-gray-500 mt-1">{{ t(`baja.${estado}Texto`) }}</p>
      </template>
      <PieLegal class="mt-6" />
    </div>
  </div>
</template>

<script setup lang="ts">
import PieLegal from '@/components/PieLegal.vue'
import { ref } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { CircleCheck, MailX, TriangleAlert } from '@lucide/vue'
import { supabase } from '@/lib/supabase'

const { t } = useI18n()
const route = useRoute()
const estado = ref<'confirmar' | 'enviando' | 'hecho' | 'invalido' | 'usado' | 'caducado' | 'error'>('confirmar')
const canal = ref<'email' | 'sms' | 'whatsapp'>('email')

async function confirmar() {
  estado.value = 'enviando'
  const { data, error } = await supabase.functions.invoke('baja', { body: { token: String(route.params.token ?? '') } })
  if (error || !data) { estado.value = 'error'; return }
  const r = data as { ok: boolean; canal?: 'email' | 'sms' | 'whatsapp'; motivo?: 'invalido' | 'usado' | 'caducado' }
  if (r.ok) { canal.value = r.canal ?? 'email'; estado.value = 'hecho'; return }
  estado.value = r.motivo === 'usado' || r.motivo === 'caducado' ? r.motivo : 'invalido'
}
</script>
