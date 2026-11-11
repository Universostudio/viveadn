<template>
  <!-- Consentimiento de un miembro por canal, con el interruptor de baja. Una baja es el estado más restrictivo:
       la importación nunca la deshace; quitarla es una decisión de una persona con permiso y queda anotada. -->
  <div>
    <h3 class="font-semibold text-gray-900 mb-1 flex items-center gap-2">
      <MailCheck class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('consentimiento.titulo') }}
    </h3>
    <p class="text-xs text-gray-500 mb-3">{{ t('consentimiento.ayuda') }}</p>
    <p v-if="error" class="text-sm text-red-600 mb-2" role="alert">{{ error }}</p>
    <ul class="divide-y divide-gray-100">
      <li v-for="canal in CANALES" :key="canal" class="py-2 flex items-center justify-between gap-3 flex-wrap">
        <div class="min-w-0">
          <p class="text-sm font-medium text-gray-800">{{ t(`consentimiento.canal.${canal}`) }}</p>
          <p class="text-xs text-gray-500">
            <span :class="['px-1.5 py-0.5 rounded-full', clase(estadoDe(canal))]">{{ t(`consentimiento.estado.${estadoDe(canal)}`) }}</span>
            <span v-if="filas[canal]"> · {{ t(`consentimiento.origen.${origenClave(filas[canal]!.origen)}`) }} · {{ formatoFecha(new Date(filas[canal]!.actualizado_en), { day: 'numeric', month: 'short', year: 'numeric' }) }}</span>
          </p>
        </div>
        <template v-if="puedeEditar">
          <div v-if="pendiente === canal" class="flex items-center gap-2 text-xs">
            <span class="text-gray-600">{{ t(estadoDe(canal) === 'cancelado' ? 'consentimiento.seguroQuitar' : 'consentimiento.seguroBaja') }}</span>
            <button type="button" class="btn-primary text-xs" :disabled="guardando" @click="cambiar(canal)">{{ t('consentimiento.confirmar') }}</button>
            <button type="button" class="btn-secondary text-xs" @click="pendiente = null">{{ t('comun.cancelar') }}</button>
          </div>
          <button v-else type="button" class="btn-secondary text-xs" @click="pendiente = canal">
            {{ t(estadoDe(canal) === 'cancelado' ? 'consentimiento.quitarBaja' : 'consentimiento.darBaja') }}
          </button>
        </template>
      </li>
    </ul>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { MailCheck } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { formatoFecha } from '@/i18n'

type Canal = 'email' | 'sms' | 'whatsapp'
type Estado = 'suscrito' | 'nunca' | 'cancelado' | 'sin_dato'
interface Fila { canal: Canal; estado: Estado; origen: string; actualizado_en: string }

const props = defineProps<{ miembroId: string }>()
const { t } = useI18n()
const auth = useAuthStore()
const CANALES: Canal[] = ['email', 'sms', 'whatsapp']
const ORIGENES_CONOCIDOS = ['manual', 'formulario', 'papel', 'verbal', 'wix', 'baja', 'enlace']

const filas = ref<Partial<Record<Canal, Fila>>>({})
const error = ref('')
const pendiente = ref<Canal | null>(null)
const guardando = ref(false)
const puedeEditar = computed(() => auth.can('comunicacion.enviar'))

const estadoDe = (canal: Canal): Estado => filas.value[canal]?.estado ?? 'sin_dato'
const origenClave = (o: string) => (ORIGENES_CONOCIDOS.includes(o) ? o : 'otro')
const clase = (e: Estado) => e === 'suscrito' ? 'bg-emerald-100 text-emerald-800' : e === 'cancelado' ? 'bg-red-100 text-red-800' : 'bg-gray-100 text-gray-700'

async function cargar() {
  const { data, error: err } = await supabase.from('adn_consentimientos').select('canal, estado, origen, actualizado_en').eq('miembro_id', props.miembroId)
  if (err) { error.value = t('consentimiento.errorCarga'); return }
  filas.value = Object.fromEntries(((data ?? []) as Fila[]).map(f => [f.canal, f]))
}

// Dar de baja deja el canal en 'cancelado'. Quitar la baja lo deja en 'sin dato': no recibe nada hasta que se
// registre un consentimiento nuevo en la pantalla de consentimientos.
async function cambiar(canal: Canal) {
  guardando.value = true
  error.value = ''
  const baja = estadoDe(canal) !== 'cancelado'
  const { error: err } = await supabase.rpc('adn_registrar_consentimiento', {
    p_miembro: props.miembroId, p_canal: canal, p_estado: baja ? 'cancelado' : 'sin_dato', p_origen: baja ? 'baja' : 'manual',
  })
  guardando.value = false
  if (err) { error.value = /ADN_SIN_PERMISO/.test(err.message) ? t('comunicacion.errores.sinPermiso') : t('consentimiento.errorGuardar'); return }
  pendiente.value = null
  await cargar()
}

onMounted(cargar)
</script>
