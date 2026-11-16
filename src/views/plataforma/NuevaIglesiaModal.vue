<template>
  <div class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50" @click.self="cerrar" @keydown.esc="cerrar" @keydown="atraparTab($event, caja)">
    <div ref="caja" role="dialog" aria-modal="true" tabindex="-1" :aria-labelledby="idTitulo" class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 max-h-[90vh] overflow-y-auto" data-test="modal-nueva">
      <h2 :id="idTitulo" class="text-lg font-bold text-gray-900 mb-4">{{ t('plataforma.nueva') }}</h2>
      <form @submit.prevent="crear" class="space-y-4">
        <div>
          <label for="ni-nombre" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.nombre') }}</label>
          <input id="ni-nombre" ref="primero" v-model="nueva.nombre" required minlength="2" maxlength="80" class="campo" />
        </div>
        <div>
          <label for="ni-slug" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.direccionInterna') }}</label>
          <input id="ni-slug" v-model="nueva.slug" required maxlength="80" placeholder="casa-reino" autocomplete="off" class="campo" aria-describedby="ni-slug-ayuda ni-slug-previa" />
          <p id="ni-slug-ayuda" class="text-xs text-gray-500 mt-1">{{ t('plataforma.slugAyuda') }}</p>
          <!-- Lo que se guardará, en vivo: quien escribe una dirección postal por error lo ve antes de enviar -->
          <p id="ni-slug-previa" class="text-xs mt-1" :class="slugOk || !nueva.slug ? 'text-gray-700' : 'text-red-600'" data-test="slug-previa" aria-live="polite">
            <template v-if="!nueva.slug">{{ t('plataforma.slugEjemplo') }}</template>
            <template v-else-if="slugOk">{{ t('plataforma.slugPrevia', { slug: slugNorm }) }}</template>
            <template v-else>{{ t('plataforma.slugCorto') }}</template>
          </p>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label for="ni-pais" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.pais') }}</label>
            <input id="ni-pais" v-model="nueva.pais" required maxlength="80" class="campo" />
          </div>
          <div>
            <label for="ni-ciudad" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.ciudad') }}</label>
            <input id="ni-ciudad" v-model="nueva.ciudad" required maxlength="80" class="campo" />
          </div>
        </div>
        <div>
          <label for="ni-plan" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.plan') }}</label>
          <select id="ni-plan" v-model="nueva.plan" class="campo">
            <option v-for="p in pm.planes" :key="p.clave" :value="p.clave">{{ p.nombre }}</option>
          </select>
        </div>
        <fieldset class="border-t border-gray-100 pt-4 space-y-3">
          <legend class="text-sm font-medium text-gray-700">{{ t('plataforma.propietario') }}</legend>
          <div class="grid grid-cols-2 gap-3">
            <input v-model="nueva.nombre_propietario" required :aria-label="t('plataforma.nombrePlaceholder')" :placeholder="t('plataforma.nombrePlaceholder')" class="campo" />
            <input v-model="nueva.apellido_propietario" required :aria-label="t('plataforma.apellidoPlaceholder')" :placeholder="t('plataforma.apellidoPlaceholder')" class="campo" />
          </div>
          <input v-model="nueva.email" type="email" required :aria-label="t('plataforma.ejemploEmail')" :placeholder="t('plataforma.ejemploEmail')" class="campo" />
        </fieldset>
        <label class="flex items-center gap-2 text-sm text-gray-600">
          <input v-model="nueva.es_demo" type="checkbox" class="rounded" /> {{ t('plataforma.esDemo') }}
        </label>
        <p v-if="error" role="alert" class="text-sm text-red-700">{{ error }}</p>
        <div class="flex gap-3 pt-2">
          <button type="button" @click="cerrar" class="btn-secondary flex-1">{{ t('comun.cancelar') }}</button>
          <button type="submit" :disabled="creando" class="btn-primary flex-1 disabled:opacity-60">{{ creando ? t('comun.creando') : t('plataforma.crear') }}</button>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { atraparTab } from '@/lib/foco'
import { normalizarSlug, slugValido } from '@/lib/slug'
import { useI18n } from 'vue-i18n'
import { usePlataformaStore } from '@/stores/plataforma'

const emit = defineEmits<{ (e: 'cerrar'): void }>()
const { t } = useI18n()
const pm = usePlataformaStore()
const idTitulo = 'ni-titulo'
const primero = ref<HTMLInputElement | null>(null)
const caja = ref<HTMLElement | null>(null)
// Quién tenía el foco al abrir el diálogo: al cerrarlo, el foco vuelve ahí
const opener = typeof document !== 'undefined' ? document.activeElement as HTMLElement | null : null
const creando = ref(false)
const error = ref('')
const vacia = () => ({
  nombre: '', slug: '', pais: '', ciudad: '', plan: pm.planes[0]?.clave ?? 'semilla',
  nombre_propietario: '', apellido_propietario: '', email: '', es_demo: false,
})
const nueva = ref(vacia())
const slugNorm = computed(() => normalizarSlug(nueva.value.slug))
const slugOk = computed(() => slugValido(slugNorm.value))

onMounted(() => { void pm.asegurarCargada(); nextTick(() => primero.value?.focus()) })
onBeforeUnmount(() => {
  // Si el elemento que abrió el diálogo ya no existe, el foco va al contenido para no quedarse perdido en el documento
  const destino = opener && opener !== document.body && document.contains(opener) ? opener : document.getElementById('panel-contenido')
  nextTick(() => destino?.focus({ preventScroll: true }))
})

function cerrar() { emit('cerrar') }

async function crear() {
  if (!slugOk.value) { error.value = t('plataforma.slugCorto'); return }
  creando.value = true
  error.value = ''
  try {
    await pm.llamar({ accion: 'crear_iglesia', ...nueva.value, slug: slugNorm.value })
    const correo = nueva.value.email
    pm.avisar(() => t('plataforma.creada', { correo }))
    await pm.cargar()
    emit('cerrar')
  } catch (e: any) {
    error.value = e.message
  }
  creando.value = false
}
</script>

<style scoped>
.campo { @apply w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde; }
</style>
