<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('logros.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('logros.subtitulo') }}</p>
    </div>

    <p v-if="aviso" role="status" data-test="aviso" :class="['text-sm px-4 py-3 rounded-lg border', aviso.error ? 'bg-red-50 text-red-700 border-red-200' : 'bg-green-50 text-green-700 border-green-200']">{{ aviso.texto }}</p>

    <form v-if="puedeGestionar" class="card space-y-3" aria-labelledby="lg-nuevo" data-test="form-logro" @submit.prevent="otorgar">
      <h2 id="lg-nuevo" class="text-base font-semibold text-gray-900">{{ t('logros.otorgar') }}</h2>
      <div class="grid grid-cols-1 sm:grid-cols-4 gap-3">
        <div class="sm:col-span-2">
          <label for="lg-miembro" class="block text-xs font-medium text-gray-600 mb-1">{{ t('logros.persona') }}</label>
          <select id="lg-miembro" v-model="nuevo.miembro_id" required data-test="logro-miembro" class="w-full text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde">
            <option value="">{{ t('comun.seleccionar') }}</option>
            <option v-for="m in miembros" :key="m.id" :value="m.id">{{ m.nombre }} {{ m.apellido }}</option>
          </select>
        </div>
        <div>
          <label for="lg-nombre" class="block text-xs font-medium text-gray-600 mb-1">{{ t('logros.nombre') }}</label>
          <input id="lg-nombre" v-model="nuevo.nombre" required maxlength="80" data-test="logro-nombre" class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" />
        </div>
        <div>
          <label for="lg-puntos" class="block text-xs font-medium text-gray-600 mb-1">{{ t('logros.puntos') }}</label>
          <input id="lg-puntos" v-model.number="nuevo.puntos" type="number" min="0" max="1000" required data-test="logro-puntos" class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" />
        </div>
      </div>
      <button type="submit" :disabled="guardando" class="btn-primary text-sm disabled:opacity-60" data-test="logro-guardar">{{ t('logros.guardar') }}</button>
    </form>

    <div v-if="cargando" class="py-12 text-center text-gray-500 text-sm">{{ t('comun.cargando') }}</div>
    <template v-else>
      <section class="card" aria-labelledby="lg-ranking" data-test="ranking">
        <h2 id="lg-ranking" class="text-base font-semibold text-gray-900 mb-3">{{ t('logros.ranking') }}</h2>
        <p v-if="!ranking.length" class="text-sm text-gray-500">{{ t('logros.vacio') }}</p>
        <ol v-else class="divide-y divide-gray-50">
          <li v-for="(r, i) in ranking" :key="r.miembro_id" class="py-2 flex items-center gap-3 text-sm">
            <span class="w-6 text-gray-500 tabular-nums">{{ i + 1 }}</span>
            <span class="flex-1 truncate text-gray-900">{{ r.nombre }}</span>
            <span class="text-gray-600">{{ t('logros.logrosN', { n: r.logros }, r.logros) }}</span>
            <span class="font-semibold text-adn-verde tabular-nums">{{ t('logros.puntosN', { n: r.puntos }) }}</span>
          </li>
        </ol>
      </section>

      <section class="card" aria-labelledby="lg-recientes" data-test="recientes">
        <h2 id="lg-recientes" class="text-base font-semibold text-gray-900 mb-3">{{ t('logros.recientes') }}</h2>
        <p v-if="!logros.length" class="text-sm text-gray-500">{{ t('logros.vacio') }}</p>
        <ul v-else class="divide-y divide-gray-50">
          <li v-for="l in logros" :key="l.id" class="py-2 flex items-center gap-3 text-sm" data-test="logro">
            <Trophy class="w-4 h-4 text-adn-oro flex-shrink-0" aria-hidden="true" />
            <span class="flex-1 min-w-0"><span class="text-gray-900">{{ l.nombre }}</span> <span class="text-gray-500">· {{ nombreDe(l.miembro_id) }}</span></span>
            <span class="text-gray-600 tabular-nums">{{ t('logros.puntosN', { n: l.puntos_otorgados ?? 0 }) }}</span>
            <time :datetime="l.fecha" class="text-xs text-gray-500 whitespace-nowrap">{{ formatoFecha(l.fecha) }}</time>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Trophy } from '@lucide/vue'
import { useI18n } from 'vue-i18n'
import { supabase } from '@/lib/supabase'
import { formatoFecha } from '@/i18n'
import { useAuthStore } from '@/stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
const puedeGestionar = computed(() => auth.can('gamificacion.gestionar'))

const cargando = ref(true)
const logros = ref<any[]>([])
const miembros = ref<any[]>([])
const guardando = ref(false)
const aviso = ref<{ texto: string; error: boolean } | null>(null)
const avisar = (texto: string, error = false) => { aviso.value = { texto, error } }
const nuevo = ref({ miembro_id: '', nombre: '', puntos: 10 })

const nombreDe = (id: string) => { const m = miembros.value.find(x => x.id === id); return m ? `${m.nombre} ${m.apellido}` : t('logros.personaDesconocida') }
// Los puntos y los logros de cada persona, con los que se ven (la base ya limita lo que cada rol puede leer)
const ranking = computed(() => {
  const porMiembro = new Map<string, { miembro_id: string; nombre: string; puntos: number; logros: number }>()
  for (const l of logros.value) {
    const r = porMiembro.get(l.miembro_id) ?? { miembro_id: l.miembro_id, nombre: nombreDe(l.miembro_id), puntos: 0, logros: 0 }
    r.puntos += Number(l.puntos_otorgados) || 0; r.logros++
    porMiembro.set(l.miembro_id, r)
  }
  return [...porMiembro.values()].sort((a, b) => b.puntos - a.puntos || a.nombre.localeCompare(b.nombre)).slice(0, 10)
})

async function cargar() {
  cargando.value = true
  const [l, m] = await Promise.all([
    supabase.from('logros').select('id, miembro_id, tipo, nombre, puntos_otorgados, fecha').order('fecha', { ascending: false }).limit(200),
    supabase.from('miembros').select('id, nombre, apellido').eq('activo', true).order('nombre'),
  ])
  if (l.error) avisar(t('logros.error'), true)
  logros.value = l.data ?? []; miembros.value = m.data ?? []
  cargando.value = false
}

async function otorgar() {
  guardando.value = true
  const { error } = await supabase.from('logros').insert({ miembro_id: nuevo.value.miembro_id, tipo: 'manual', nombre: nuevo.value.nombre.trim(), puntos_otorgados: Math.max(0, Math.round(nuevo.value.puntos)) })
  guardando.value = false
  if (error) { avisar(t('logros.error'), true); return }
  nuevo.value = { miembro_id: '', nombre: '', puntos: 10 }
  avisar(t('logros.guardado'))
  await cargar()
}

onMounted(cargar)
</script>
