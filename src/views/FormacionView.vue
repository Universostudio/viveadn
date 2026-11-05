<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('formacion.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('formacion.subtitulo') }}</p>
      </div>
      <RouterLink to="/formacion/programas" class="btn-secondary text-sm">{{ t('formacion.programas.enlace') }}</RouterLink>
    </div>

    <!-- Descripción niveles -->
    <div class="grid grid-cols-1 sm:grid-cols-5 gap-3">
      <div
        v-for="(nivel, i) in niveles"
        :key="nivel.numero"
        class="card text-center hover:shadow-md transition-shadow cursor-pointer"
        :class="nivelActivo === nivel.numero ? 'ring-2 ring-adn-verde' : ''"
        @click="nivelActivo = nivelActivo === nivel.numero ? null : nivel.numero"
      >
        <component :is="nivel.icono" class="w-8 h-8 mx-auto mb-2 text-adn-verde" aria-hidden="true" />
        <p class="text-xs font-bold text-gray-700 uppercase tracking-wide">{{ t('formacion.nivelNumero', { n: i + 1 }) }}</p>
        <p class="text-sm font-semibold text-gray-900 mt-0.5">{{ nombreNivel(nivel.numero) }}</p>
        <p class="text-2xl font-bold text-adn-verde mt-2">{{ conteoPorNivel[nivel.numero] ?? 0 }}</p>
        <p class="text-xs text-gray-400">{{ t('formacion.alumnos', conteoPorNivel[nivel.numero] ?? 0) }}</p>
      </div>
    </div>

    <!-- Lista de progreso -->
    <div class="card">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-gray-900">
          {{ nivelActivo ? t('formacion.nivelFiltro', { nombre: nombreNivel(nivelActivo) }) : t('formacion.todosProgresos') }}
        </h2>
        <div class="flex items-center gap-2">
          <button v-if="nivelActivo" @click="nivelActivo = null" class="text-xs text-adn-verde hover:underline">
            {{ t('formacion.verTodos') }}
          </button>
          <button @click="abrirActualizar = true" class="btn-secondary text-xs">
            {{ t('formacion.actualizarBoton') }}
          </button>
        </div>
      </div>

      <div v-if="cargando" class="py-12 text-center text-gray-400">
        <LoaderCircle class="w-8 h-8 mx-auto mb-2 animate-spin text-gray-300" aria-hidden="true" /><p>{{ t('comun.cargando') }}</p>
      </div>

      <div v-else-if="progresoFiltrado.length === 0" class="py-12 text-center text-gray-400">
        <GraduationCap class="w-10 h-10 mx-auto mb-2 text-gray-300" aria-hidden="true" />
        <p>{{ t('formacion.sinRegistros') }}</p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="p in progresoFiltrado"
          :key="p.id"
          class="flex items-center gap-4 p-3 bg-gray-50 rounded-xl"
        >
          <!-- Avatar -->
          <div class="w-9 h-9 bg-adn-verde rounded-full flex items-center justify-center flex-shrink-0">
            <span class="text-white text-sm font-bold">{{ p.miembros?.nombre?.[0] ?? '?' }}</span>
          </div>

          <!-- Info miembro y nivel -->
          <div class="flex-1 min-w-0">
            <div class="flex items-center justify-between">
              <p class="font-medium text-gray-900 text-sm">{{ p.miembros?.nombre }} {{ p.miembros?.apellido }}</p>
              <span class="text-xs font-medium text-gray-500">{{ nombreNivel(p.nivel) }}</span>
            </div>
            <div class="mt-1.5 flex items-center gap-3">
              <div class="flex-1 h-2 bg-gray-200 rounded-full overflow-hidden">
                <div
                  class="h-full bg-adn-verde rounded-full transition-all"
                  :style="{ width: `${p.porcentaje ?? 0}%` }"
                ></div>
              </div>
              <span class="text-xs text-gray-500 flex-shrink-0">{{ p.porcentaje ?? 0 }}%</span>
            </div>
          </div>

          <!-- Estado -->
          <span
            :class="['text-xs px-2 py-1 rounded-full font-medium flex-shrink-0',
              p.fecha_completado ? 'bg-green-100 text-green-700' : 'bg-blue-100 text-blue-700']"
          >
            {{ p.fecha_completado ? t('comun.completado') : t('formacion.enCurso') }}
          </span>
        </div>
      </div>
    </div>

    <!-- Modal: Actualizar progreso -->
    <div
      v-if="abrirActualizar"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="abrirActualizar = false"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ t('formacion.modalTitulo') }}</h2>
        <form @submit.prevent="actualizarProgreso" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('formacion.miembro') }}</label>
            <select v-model="upd.miembro_id" required
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm">
              <option value="">{{ t('comun.seleccionar') }}</option>
              <option v-for="m in miembros" :key="m.id" :value="m.id">
                {{ m.nombre }} {{ m.apellido }}
              </option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('formacion.nivel') }}</label>
            <select v-model="upd.nivel" required
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm">
              <option v-for="n in niveles" :key="n.numero" :value="n.numero">
                {{ n.numero }}. {{ nombreNivel(n.numero) }}
              </option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">
              {{ t('formacion.porcentaje', { p: upd.porcentaje }) }}
            </label>
            <input v-model.number="upd.porcentaje" type="range" min="0" max="100" step="5"
              class="w-full accent-adn-verde" />
            <div class="flex justify-between text-xs text-gray-400 mt-1">
              <span>0%</span><span>25%</span><span>50%</span><span>75%</span><span>100%</span>
            </div>
          </div>
          <p v-if="errorGuardar" class="text-sm text-red-600">{{ t(errorGuardar) }}</p>
          <label class="flex items-center gap-2 cursor-pointer">
            <input v-model="upd.completado" type="checkbox" class="w-4 h-4 accent-adn-verde" />
            <span class="text-sm text-gray-700">{{ t('formacion.marcarCompletado') }}</span>
          </label>
          <div class="flex gap-3 pt-2">
            <button type="button" @click="abrirActualizar = false" class="btn-secondary flex-1">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="guardando" class="btn-primary flex-1 disabled:opacity-60">
              {{ guardando ? t('comun.guardando') : t('formacion.actualizar') }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { GraduationCap, HandHelping, Leaf, LoaderCircle, Rocket, Sprout, Star } from '@lucide/vue'
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

const cargando = ref(true)
const progreso = ref<any[]>([])
const miembros = ref<any[]>([])
const nivelActivo = ref<number | null>(null)
const abrirActualizar = ref(false)
const guardando = ref(false)
// Clave de traducción del error visible ('' = sin error)
const errorGuardar = ref('')

const vacio = () => ({ miembro_id: '', nivel: 1, porcentaje: 0, completado: false })
const upd = ref(vacio())

// nombreBD: valor que se guarda en progreso_formacion.nombre_nivel (no se traduce)
// clave: etiqueta visible en src/i18n (formacion.niveles.<clave>)
const niveles = [
  { numero: 1, clave: 'fundamentos', nombreBD: 'Fundamentos', icono: Sprout },
  { numero: 2, clave: 'crecimiento', nombreBD: 'Crecimiento', icono: Leaf },
  { numero: 3, clave: 'servicio', nombreBD: 'Servicio', icono: HandHelping },
  { numero: 4, clave: 'liderazgo', nombreBD: 'Liderazgo', icono: Star },
  { numero: 5, clave: 'multiplicacion', nombreBD: 'Multiplicación', icono: Rocket },
]

function nombreNivel(numero: number) {
  const nivel = niveles.find(n => n.numero === numero)
  return nivel ? t(`formacion.niveles.${nivel.clave}`) : t('formacion.nivelNumero', { n: numero })
}

function nombreNivelBD(numero: number) {
  return niveles.find(n => n.numero === numero)?.nombreBD ?? `Nivel ${numero}`
}

const conteoPorNivel = computed(() => {
  const c: Record<number, number> = {}
  progreso.value.forEach(p => {
    c[p.nivel] = (c[p.nivel] ?? 0) + 1
  })
  return c
})

const progresoFiltrado = computed(() => {
  if (!nivelActivo.value) return progreso.value
  return progreso.value.filter(p => p.nivel === nivelActivo.value)
})

async function cargarDatos() {
  cargando.value = true
  const [progRes, miembrosRes] = await Promise.all([
    supabase
      .from('progreso_formacion')
      .select('*, miembros(nombre, apellido)')
      .order('nivel'),
    supabase.from('miembros').select('id, nombre, apellido').eq('activo', true).order('nombre'),
  ])
  progreso.value = progRes.data ?? []
  miembros.value = miembrosRes.data ?? []
  cargando.value = false
}

async function actualizarProgreso() {
  guardando.value = true
  errorGuardar.value = ''
  const completado = upd.value.completado || upd.value.porcentaje === 100
  // Un registro por miembro y nivel: guardar de nuevo actualiza el existente
  const { error } = await supabase.from('progreso_formacion').upsert({
    miembro_id: upd.value.miembro_id,
    nivel: upd.value.nivel,
    nombre_nivel: nombreNivelBD(upd.value.nivel),
    porcentaje: completado ? 100 : upd.value.porcentaje,
    fecha_completado: completado ? new Date().toISOString().slice(0, 10) : null,
  }, { onConflict: 'miembro_id,nivel' })
  guardando.value = false
  if (error) {
    errorGuardar.value = 'formacion.errorGuardar'
    return
  }
  abrirActualizar.value = false
  upd.value = vacio()
  await cargarDatos()
}

onMounted(cargarDatos)
</script>
