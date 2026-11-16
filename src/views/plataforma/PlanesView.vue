<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.planes.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('plataformaPanel.planes.subtitulo') }}</p>
    </div>
    <div v-if="pm.cargando && !pm.cargada" class="py-12 text-center text-gray-500 text-sm">{{ t('plataforma.cargando') }}</div>
    <section v-else class="card" aria-labelledby="pl-tabla">
      <h2 id="pl-tabla" class="sr-only">{{ t('plataformaPanel.planes.titulo') }}</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm" data-test="matriz-planes">
          <thead class="text-left text-xs text-gray-500 border-b border-gray-100"><tr>
            <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataformaPanel.planes.modulo') }}</th>
            <th v-for="p in pm.planes" :key="p.clave" scope="col" class="py-2 px-3 font-medium text-center">{{ p.nombre }}</th></tr></thead>
          <tbody class="divide-y divide-gray-50">
            <tr><th scope="row" class="py-2 pr-3 text-left font-normal text-gray-600">{{ t('plataformaPanel.planes.limite') }}</th>
              <td v-for="p in pm.planes" :key="p.clave" class="py-2 px-3 text-center tabular-nums">{{ p.max_miembros ? p.max_miembros.toLocaleString(locale) : t('plataformaPanel.planes.sinLimite') }}</td></tr>
            <tr><th scope="row" class="py-2 pr-3 text-left font-normal text-gray-600">{{ t('plataformaPanel.planes.iglesias') }}</th>
              <td v-for="p in pm.planes" :key="p.clave" class="py-2 px-3 text-center tabular-nums">{{ contar(p.clave) }}</td></tr>
            <tr v-for="m in pm.modulos" :key="m.clave">
              <th scope="row" class="py-2 pr-3 text-left font-normal text-gray-900">{{ m.nombre }}</th>
              <td v-for="p in pm.planes" :key="p.clave" class="py-2 px-3 text-center">
                <Check v-if="incluye(p.clave, m.clave)" class="w-4 h-4 text-green-700 inline" aria-hidden="true" /><span class="sr-only">{{ t(incluye(p.clave, m.clave) ? 'plataformaPanel.planes.incluido' : 'plataformaPanel.planes.noIncluido') }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { Check } from '@lucide/vue'
import { useI18n } from 'vue-i18n'
import { usePlataformaStore } from '@/stores/plataforma'

const { t, locale } = useI18n()
const pm = usePlataformaStore()
onMounted(() => { void pm.asegurarCargada() })
const incluye = (plan: string, modulo: string) => pm.planModulos.some(x => x.plan === plan && x.modulo === modulo)
const contar = (plan: string) => pm.iglesias.filter(i => i.plan === plan && !i.es_demo).length
</script>
