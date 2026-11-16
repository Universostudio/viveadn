<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('plataforma.registro.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('plataforma.registro.ayuda') }}</p>
    </div>
    <div v-if="pm.cargando && !pm.cargada" class="py-12 text-center text-gray-500 text-sm">{{ t('plataforma.cargando') }}</div>
    <section v-else class="card space-y-4" :aria-label="t('plataforma.registro.titulo')">
      <div class="flex flex-wrap gap-x-6 gap-y-2">
        <label class="inline-flex items-center gap-2 text-sm text-gray-700"><input type="checkbox" data-test="registro-abierto" :checked="pm.registro.abierto" @change="guardarAjustes(($event.target as HTMLInputElement).checked, pm.registro.requiere_codigo)" /> {{ t('plataforma.registro.abierto') }}</label>
        <label class="inline-flex items-center gap-2 text-sm text-gray-700"><input type="checkbox" :checked="pm.registro.requiere_codigo" @change="guardarAjustes(pm.registro.abierto, ($event.target as HTMLInputElement).checked)" /> {{ t('plataforma.registro.requiereCodigo') }}</label>
      </div>
      <p v-if="pm.registro.abierto" class="text-xs text-gray-500">{{ t('plataforma.registro.enlace') }} <span class="font-mono">{{ origen }}/registro</span></p>

      <div v-if="codigoCreado" role="status" class="rounded-lg border border-green-200 bg-green-50 p-3 text-sm">
        <p class="text-green-800 font-medium">{{ t('plataforma.registro.codigoCreado') }}</p>
        <p class="mt-1 flex flex-wrap items-center gap-3"><span class="font-mono text-base text-green-900 select-all">{{ codigoCreado }}</span>
          <button type="button" @click="copiarCodigo" class="btn-secondary text-xs">{{ codigoCopiado ? t('dar.copiado') : t('dar.copiar') }}</button></p>
        <p class="text-xs text-green-700 mt-1">{{ t('plataforma.registro.codigoUnaVez') }}</p>
      </div>

      <form @submit.prevent="crearCodigo" class="flex flex-wrap items-end gap-3">
        <div><label for="cd-eti" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.registro.etiqueta') }}</label>
          <input id="cd-eti" v-model="nuevoCodigo.etiqueta" required maxlength="80" class="text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" /></div>
        <div><label for="cd-usos" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.registro.usos') }}</label>
          <input id="cd-usos" v-model.number="nuevoCodigo.usos_max" type="number" min="1" max="1000" required class="w-24 text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" /></div>
        <div><label for="cd-dias" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.registro.dias') }}</label>
          <input id="cd-dias" v-model.number="nuevoCodigo.dias" type="number" min="0" max="365" required class="w-24 text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" /></div>
        <button type="submit" class="btn-primary text-sm">{{ t('plataforma.registro.crear') }}</button>
      </form>

      <div v-if="pm.registro.codigos.length" class="overflow-x-auto">
        <table class="w-full text-sm">
          <caption class="sr-only">{{ t('plataforma.registro.titulo') }}</caption>
          <thead class="text-left text-xs text-gray-500 border-b border-gray-100"><tr>
            <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataforma.registro.etiqueta') }}</th>
            <th scope="col" class="py-2 pr-3 font-medium text-right">{{ t('plataforma.registro.usados') }}</th>
            <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataforma.registro.vence') }}</th>
            <th scope="col" class="py-2 font-medium text-right">{{ t('plataforma.registro.estado') }}</th></tr></thead>
          <tbody class="divide-y divide-gray-50">
            <tr v-for="c in pm.registro.codigos" :key="c.id">
              <td class="py-2 pr-3 text-gray-900">{{ c.etiqueta }}</td>
              <td class="py-2 pr-3 text-right">{{ c.usos }} / {{ c.usos_max }}</td>
              <td class="py-2 pr-3 text-gray-500">{{ c.vence_en ? new Date(c.vence_en).toLocaleDateString(locale) : t('plataforma.registro.sinVencimiento') }}</td>
              <td class="py-2 text-right"><button type="button" :aria-pressed="c.activo" @click="estadoCodigo(c)" :class="['text-xs px-3 py-1.5 rounded-full border', c.activo ? 'border-green-200 text-green-800 bg-green-50' : 'border-gray-200 text-gray-600']">{{ c.activo ? t('comun.activo') : t('comun.inactivo') }}</button></td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else class="text-sm text-gray-400">{{ t('plataforma.registro.sinCodigos') }}</p>
    </section>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { usePlataformaStore } from '@/stores/plataforma'

const { t, locale } = useI18n()
const pm = usePlataformaStore()
onMounted(() => { void pm.asegurarCargada() })

const origen = window.location.origin
const nuevoCodigo = ref({ etiqueta: '', usos_max: 1, dias: 30 })
const codigoCreado = ref('')
const codigoCopiado = ref(false)

const guardarAjustes = (abierto: boolean, requiereCodigo: boolean) =>
  pm.ejecutar({ accion: 'registro_ajustes', abierto, requiere_codigo: requiereCodigo }, () => t('plataforma.registro.guardado'))

async function crearCodigo() {
  try {
    const d = await pm.llamar({ accion: 'codigo_crear', ...nuevoCodigo.value })
    codigoCreado.value = d.codigo
    nuevoCodigo.value = { etiqueta: '', usos_max: 1, dias: 30 }
    await pm.cargar()
  } catch (e: any) { const texto = e.message; pm.avisar(() => texto, true) }
}
const estadoCodigo = (c: any) => pm.ejecutar({ accion: 'codigo_estado', id: c.id, activo: !c.activo }, () => t('plataforma.registro.guardado'))
async function copiarCodigo() {
  try { await navigator.clipboard.writeText(codigoCreado.value); codigoCopiado.value = true; setTimeout(() => { codigoCopiado.value = false }, 2000) } catch { /* se puede copiar a mano */ }
}
</script>
