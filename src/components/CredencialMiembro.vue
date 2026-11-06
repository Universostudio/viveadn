<template>
  <button @click="abrir" class="btn-secondary text-sm inline-flex items-center gap-1"><IdCard class="w-4 h-4" aria-hidden="true" /> {{ t('ficha.credencial.boton') }}</button>

  <div v-if="abierta" class="fixed inset-0 bg-black bg-opacity-40 z-50 overflow-y-auto" @click.self="cerrar" role="dialog" aria-modal="true" :aria-label="t('ficha.credencial.titulo')">
    <div class="min-h-full flex items-center justify-center p-4" @click.self="cerrar">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-sm p-6 my-2">
        <p v-if="cargando" class="text-center text-gray-400 py-10" role="status">{{ t('comun.cargando') }}</p>
        <template v-else>
          <div v-if="imagen" class="credencial-imprimible border-2 border-adn-verde rounded-xl p-6 text-center bg-white">
            <p class="text-xs uppercase tracking-widest text-gray-500">{{ auth.nombreIglesia }}</p>
            <h2 class="text-lg font-bold text-adn-verde mt-1">{{ t('ficha.credencial.titulo') }}</h2>
            <p class="text-xl font-bold text-gray-900 mt-4">{{ nombreCompleto }}</p>
            <img :src="imagen" :alt="t('ficha.credencial.qrAlt')" class="mx-auto mt-4" width="220" height="220" />
            <p class="text-xs text-gray-500 mt-3">{{ t('ficha.credencial.uso') }}</p>
          </div>
          <p v-if="error" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200 mt-3">{{ t(error) }}</p>
          <p v-if="imagen" class="text-xs text-gray-400 mt-3">{{ t('ficha.credencial.aviso') }}</p>
          <div class="flex flex-wrap gap-2 mt-4">
            <button v-if="imagen" @click="imprimir" class="btn-primary flex-1 text-sm">{{ t('ficha.credencial.imprimir') }}</button>
            <button v-if="imagen" @click="renovar" :disabled="trabajando" class="btn-secondary text-sm">{{ t('ficha.credencial.renovar') }}</button>
            <button v-if="imagen" @click="retirar" :disabled="trabajando" class="btn-secondary text-sm text-red-600">{{ t('ficha.credencial.retirar') }}</button>
            <button @click="cerrar" class="btn-secondary text-sm">{{ t('ficha.credencial.cerrar') }}</button>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import QRCode from 'qrcode'
import { IdCard } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { textoQr } from '@/lib/credencial'

const props = defineProps<{ miembro: { id: string; nombre: string; apellido: string } }>()
const { t } = useI18n()
const auth = useAuthStore()

const abierta = ref(false)
const cargando = ref(false)
const trabajando = ref(false)
const error = ref('')
const imagen = ref('')

const nombreCompleto = computed(() => `${props.miembro.nombre} ${props.miembro.apellido ?? ''}`.trim())

// El QR se dibuja en el navegador; el token no sale a ningun servicio externo
async function cargar(renovar: boolean) {
  error.value = ''
  const { error: e1 } = await supabase.rpc('emitir_credencial', { p_miembro: props.miembro.id, p_renovar: renovar })
  if (e1) { error.value = 'ficha.credencial.error'; return }
  const { data, error: e2 } = await supabase.from('credenciales_miembro').select('token').eq('miembro_id', props.miembro.id).maybeSingle()
  if (e2 || !data) { error.value = 'ficha.credencial.error'; return }
  imagen.value = await QRCode.toDataURL(textoQr(data.token), { width: 600, margin: 2, errorCorrectionLevel: 'M' })
}

async function abrir() {
  abierta.value = true
  cargando.value = true
  imagen.value = ''
  await cargar(false)
  cargando.value = false
}

async function renovar() {
  if (!window.confirm(t('ficha.credencial.confirmarRenovar'))) return
  trabajando.value = true
  await cargar(true)
  trabajando.value = false
}

async function retirar() {
  if (!window.confirm(t('ficha.credencial.confirmarRetirar'))) return
  trabajando.value = true
  const { error: e } = await supabase.rpc('retirar_credencial', { p_miembro: props.miembro.id })
  trabajando.value = false
  if (e) { error.value = 'ficha.credencial.error'; return }
  cerrar()
}

const cerrar = () => { abierta.value = false; imagen.value = '' }
const imprimir = () => window.print()
</script>

<style>
/* Al imprimir con la credencial abierta solo sale la credencial; sin ella, la pagina se imprime con normalidad */
@media print {
  body:has(.credencial-imprimible) * { visibility: hidden; }
  body:has(.credencial-imprimible) .credencial-imprimible, body:has(.credencial-imprimible) .credencial-imprimible * { visibility: visible; }
  .credencial-imprimible { position: fixed; left: 0; top: 0; width: 90mm; border-width: 3px; }
}
</style>
