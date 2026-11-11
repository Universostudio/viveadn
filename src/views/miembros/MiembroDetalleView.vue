<template>
  <div class="p-4 sm:p-6 space-y-6">
    <!-- Back + header -->
    <div class="flex items-center gap-3">
      <RouterLink to="/miembros" class="text-gray-400 hover:text-adn-verde transition-colors" :aria-label="t('ficha.volver')"><ArrowLeft class="w-6 h-6" aria-hidden="true" /></RouterLink>
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('ficha.titulo') }}</h1>
        <p class="text-gray-500 text-sm">{{ miembro?.crm_id }}</p>
      </div>
    </div>

    <div v-if="cargando" class="py-20 text-center text-gray-400">
      <LoaderCircle class="w-8 h-8 mx-auto mb-2 animate-spin text-gray-300" aria-hidden="true" />
      <p>{{ t('ficha.cargando') }}</p>
    </div>

    <div v-else-if="!miembro" class="py-20 text-center text-gray-400">
      <UserX class="w-10 h-10 mx-auto mb-2 text-gray-300" aria-hidden="true" />
      <p>{{ t('ficha.noEncontrado') }}</p>
      <RouterLink to="/miembros" class="text-adn-verde hover:underline text-sm mt-2 inline-block">
        {{ t('ficha.volver') }}
      </RouterLink>
    </div>

    <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Columna principal -->
      <div class="lg:col-span-2 space-y-6">
        <!-- Tarjeta perfil -->
        <div class="card">
          <div class="flex items-start gap-4">
            <div class="w-16 h-16 bg-adn-verde rounded-2xl flex items-center justify-center flex-shrink-0">
              <span class="text-white text-2xl font-bold">{{ miembro.nombre[0] }}</span>
            </div>
            <div class="flex-1">
              <div class="flex items-start justify-between">
                <div>
                  <h2 class="text-xl font-bold text-gray-900">{{ miembro.nombre }} {{ miembro.apellido }}</h2>
                  <p class="text-sm text-gray-500 font-mono mt-0.5">{{ miembro.crm_id }}</p>
                </div>
                <span :class="['text-xs px-3 py-1 rounded-full font-medium', claseNivel(miembro.nivel_compromiso)]">
                  {{ etiquetaNivel(miembro.nivel_compromiso) }}
                </span>
              </div>
              <div class="flex flex-wrap gap-4 mt-4 text-sm text-gray-600">
                <span v-if="miembro.email" class="inline-flex items-center gap-1.5"><Mail class="w-4 h-4 text-gray-400" aria-hidden="true" /> {{ miembro.email }}</span>
                <span v-if="miembro.telefono" class="inline-flex items-center gap-1.5"><Phone class="w-4 h-4 text-gray-400" aria-hidden="true" /> {{ miembro.telefono }}</span>
                <span v-if="miembro.casas_oracion" class="inline-flex items-center gap-1.5"><House class="w-4 h-4 text-gray-400" aria-hidden="true" /> {{ miembro.casas_oracion.nombre }}</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Datos de contacto adicionales (segundo correo, otros teléfonos, direcciones y etiquetas), p. ej. de una importación -->
        <div v-if="contactos.length" class="card">
          <h3 class="font-semibold text-gray-900 mb-3 flex items-center gap-2"><ContactRound class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('ficha.contactos') }}</h3>
          <dl class="space-y-2 text-sm">
            <div v-for="g in gruposContacto" :key="g.tipo" class="flex gap-3">
              <dt class="text-gray-500 w-24 flex-shrink-0">{{ t('ficha.contactoTipo.' + g.tipo) }}</dt>
              <dd class="text-gray-800 min-w-0">
                <template v-if="g.tipo === 'etiqueta'">
                  <span v-for="c in g.items" :key="c.id" class="inline-block text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full mr-1 mb-1">{{ c.valor }}</span>
                </template>
                <template v-else>
                  <span v-for="c in g.items" :key="c.id" class="block break-words">{{ c.valor }}<span v-if="c.etiqueta" class="text-xs text-gray-400"> · {{ c.etiqueta }}</span></span>
                </template>
              </dd>
            </div>
          </dl>
        </div>

        <!-- Historial de consolidación -->
        <div class="card">
          <h3 class="font-semibold text-gray-900 mb-4 flex items-center gap-2"><HeartHandshake class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('ficha.historial') }}</h3>
          <div v-if="!consolidaciones.length" class="py-6 text-center text-gray-400 text-sm">
            {{ t('ficha.sinHistorial') }}
          </div>
          <div v-else class="space-y-3">
            <div
              v-for="c in consolidaciones"
              :key="c.id"
              class="flex items-center justify-between p-3 bg-gray-50 rounded-lg text-sm"
            >
              <div>
                <p class="font-medium text-gray-800">{{ formatFecha(c.fecha_conversion) }}</p>
                <p class="text-xs text-gray-500 mt-0.5" v-if="c.notas">{{ c.notas }}</p>
              </div>
              <span v-if="c.completado" class="text-xs px-2.5 py-1 rounded-full font-semibold bg-emerald-100 text-emerald-800 inline-flex items-center gap-1.5">
                <Check class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('comun.completado') }}
              </span>
              <EstadoAlerta v-else :estado="c.estado_alerta" />
            </div>
          </div>
        </div>

        <!-- Progreso formación -->
        <div class="card">
          <h3 class="font-semibold text-gray-900 mb-4 flex items-center gap-2"><GraduationCap class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('ficha.progreso') }}</h3>
          <div v-if="!progreso.length" class="py-6 text-center text-gray-400 text-sm">
            {{ t('ficha.sinProgreso') }}
          </div>
          <div v-else class="space-y-4">
            <div v-for="p in progresoOrdenado" :key="p.id">
              <div class="flex items-center justify-between text-sm mb-1">
                <span class="font-medium text-gray-800">{{ p.nivel }}. {{ p.nombre_nivel }}</span>
                <span class="text-gray-500">{{ p.porcentaje ?? 0 }}%</span>
              </div>
              <div class="h-2.5 bg-gray-100 rounded-full overflow-hidden">
                <div
                  class="h-full bg-adn-verde rounded-full transition-all"
                  :style="{ width: `${p.porcentaje ?? 0}%` }"
                ></div>
              </div>
              <p v-if="p.fecha_completado" class="text-xs text-emerald-700 mt-1 inline-flex items-center gap-1">
                <Check class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('ficha.completadoEl', { fecha: formatFecha(p.fecha_completado) }) }}
              </p>
            </div>
          </div>
        </div>
      </div>

      <!-- Columna lateral -->
      <div class="space-y-6">
        <!-- Gamificación -->
        <div class="card">
          <h3 class="font-semibold text-gray-900 mb-4 flex items-center gap-2"><Activity class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('ficha.participacion') }}</h3>
          <div class="space-y-3">
            <div class="flex items-center justify-between">
              <span class="text-sm text-gray-600">{{ t('ficha.puntos') }}</span>
              <span class="font-bold text-adn-oro text-lg">{{ miembro.puntos ?? 0 }}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-sm text-gray-600 inline-flex items-center gap-1.5"><Flame class="w-4 h-4 text-orange-500" aria-hidden="true" /> {{ t('ficha.racha') }}</span>
              <span class="font-bold text-orange-500">{{ t('ficha.dias', miembro.racha_dias ?? 0) }}</span>
            </div>
          </div>
        </div>

        <!-- Logros -->
        <div class="card">
          <h3 class="font-semibold text-gray-900 mb-3 flex items-center gap-2"><Trophy class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('ficha.logros') }}</h3>
          <div v-if="!logros.length" class="py-4 text-center text-gray-400 text-sm">
            {{ t('ficha.sinLogros') }}
          </div>
          <div v-else class="grid grid-cols-3 gap-2">
            <div
              v-for="l in logros"
              :key="l.id"
              class="bg-yellow-50 border border-yellow-100 rounded-xl p-2 text-center"
              :title="l.nombre"
            >
              <Award class="w-7 h-7 mx-auto text-adn-oro" aria-hidden="true" />
              <p class="text-xs text-gray-600 mt-1 truncate">{{ l.nombre }}</p>
            </div>
          </div>
        </div>

        <!-- Info adicional -->
        <div class="card">
          <h3 class="font-semibold text-gray-900 mb-3 flex items-center gap-2"><Info class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('ficha.informacion') }}</h3>
          <dl class="space-y-2 text-sm">
            <div class="flex justify-between">
              <dt class="text-gray-500">{{ t('ficha.registrado') }}</dt>
              <dd class="text-gray-800 font-medium">{{ formatFecha(miembro.created_at) }}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-500">{{ t('ficha.estado') }}</dt>
              <dd>
                <span :class="['text-xs px-2 py-0.5 rounded-full font-medium', miembro.activo ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500']">
                  {{ miembro.activo ? t('comun.activo') : t('comun.inactivo') }}
                </span>
              </dd>
            </div>
            <div v-if="miembro.casas_oracion" class="flex justify-between">
              <dt class="text-gray-500">{{ t('ficha.zona') }}</dt>
              <dd class="text-gray-800 font-mono text-xs font-medium">{{ miembro.casas_oracion.codigo_zona }}</dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Activity, ArrowLeft, Award, Check, ContactRound, Flame, GraduationCap, HeartHandshake, House, Info, LoaderCircle, Mail, Phone, Trophy, UserX } from '@lucide/vue'
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { conAlerta } from '@/lib/alertas'
import type { NivelCompromiso } from '@/lib/supabase'
import EstadoAlerta from '@/components/EstadoAlerta.vue'
import { useI18n } from 'vue-i18n'
import { formatoFecha } from '@/i18n'

const route = useRoute()
const { t, te } = useI18n()
const cargando = ref(true)
const miembro = ref<any>(null)
const consolidaciones = ref<any[]>([])
const progreso = ref<any[]>([])
const logros = ref<any[]>([])
const contactos = ref<any[]>([])

// Agrupados por tipo y sin la marca de la importación, que no es un dato del miembro
const gruposContacto = computed(() =>
  (['correo', 'telefono', 'direccion', 'etiqueta'] as const)
    .map(tipo => ({ tipo, items: contactos.value.filter(c => c.tipo === tipo && c.etiqueta !== 'importacion') }))
    .filter(g => g.items.length)
)

const progresoOrdenado = computed(() =>
  [...progreso.value].sort((a, b) => (a.nivel ?? 9) - (b.nivel ?? 9))
)

function formatFecha(fecha?: string) {
  if (!fecha) return '—'
  return formatoFecha(fecha, { day: '2-digit', month: 'short', year: 'numeric' })
}

function claseNivel(nivel: NivelCompromiso) {
  const m: Record<NivelCompromiso, string> = {
    nuevo: 'bg-gray-100 text-gray-600',
    en_crecimiento: 'bg-blue-100 text-blue-700',
    maduro: 'bg-green-100 text-green-700',
    lider: 'bg-purple-100 text-purple-700',
    multiplicador: 'bg-yellow-100 text-yellow-700',
  }
  return m[nivel] ?? 'bg-gray-100 text-gray-600'
}

// Acepta niveles de compromiso y nombres de nivel de formación; "en_crecimiento" va en forma corta
function etiquetaNivel(nivel: string) {
  if (nivel === 'en_crecimiento') return t('compromiso.en_crecimiento_corto')
  for (const clave of [`compromiso.${nivel}`, `formacion.niveles.${nivel}`]) {
    if (nivel && te(clave)) return t(clave)
  }
  return nivel
}

onMounted(async () => {
  const id = route.params.id as string
  const [miembroRes, consolRes, progresoRes, logrosRes, contactosRes] = await Promise.all([
    supabase
      .from('miembros')
      .select('*, casas_oracion(nombre, codigo_zona)')
      .eq('id', id)
      .single(),
    supabase
      .from('consolidaciones')
      .select('id, fecha_conversion, completado, notas')
      .eq('miembro_id', id)
      .order('fecha_conversion', { ascending: false }),
    supabase
      .from('progreso_formacion')
      .select('*')
      .eq('miembro_id', id),
    supabase
      .from('logros')
      .select('id, nombre, tipo')
      .eq('miembro_id', id),
    supabase
      .from('adn_miembro_contactos')
      .select('id, tipo, etiqueta, valor, orden')
      .eq('miembro_id', id)
      .order('orden'),
  ])
  miembro.value = miembroRes.data
  consolidaciones.value = (consolRes.data ?? []).map(conAlerta)
  progreso.value = progresoRes.data ?? []
  logros.value = logrosRes.data ?? []
  contactos.value = contactosRes.data ?? []
  cargando.value = false
})
</script>
