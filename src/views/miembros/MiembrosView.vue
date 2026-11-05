<template>
  <div class="p-4 sm:p-6 space-y-6">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('miembros.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('miembros.subtitulo') }}</p>
      </div>
      <div class="flex items-center gap-2">
        <button v-if="puedeImportar" @click="abrirImportar = true" class="btn-secondary flex items-center gap-2">
          <Upload class="w-4 h-4" aria-hidden="true" /> {{ t('miembros.importar.boton') }}
        </button>
        <button @click="abrirNuevo = true" class="btn-primary flex items-center gap-2">
          <UserPlus class="w-4 h-4" aria-hidden="true" /> {{ t('miembros.nuevo') }}
        </button>
      </div>
    </div>

    <ImportarMiembros v-if="abrirImportar" @cerrar="abrirImportar = false" @importado="cargarDatos" />

    <!-- Buscador y filtros -->
    <div class="card">
      <div class="flex flex-col sm:flex-row gap-3">
        <div class="flex-1 relative">
          <Search class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" aria-hidden="true" />
          <input
            v-model="busqueda"
            type="text"
            :placeholder="t('miembros.buscar')"
            class="w-full pl-9 pr-4 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde"
          />
        </div>
        <select
          v-model="filtroNivel"
          class="text-sm border border-gray-200 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-adn-verde"
        >
          <option value="">{{ t('miembros.todosNiveles') }}</option>
          <option v-for="n in NIVELES_COMPROMISO" :key="n" :value="n">{{ t(ETIQUETAS_COMPROMISO[n]) }}</option>
        </select>
        <select
          v-model="filtroEstado"
          class="text-sm border border-gray-200 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-adn-verde"
        >
          <option value="activo">{{ t('miembros.activos') }}</option>
          <option value="todos">{{ t('miembros.todos') }}</option>
          <option value="inactivo">{{ t('miembros.inactivos') }}</option>
        </select>
      </div>
    </div>

    <!-- Tabla de miembros -->
    <div class="card overflow-hidden p-0">
      <div v-if="cargando" class="py-16 text-center text-gray-400">
        <LoaderCircle class="w-8 h-8 mx-auto mb-2 animate-spin text-gray-300" aria-hidden="true" />
        <p>{{ t('miembros.cargando') }}</p>
      </div>

      <div v-else-if="miembrosFiltrados.length === 0" class="py-16 text-center text-gray-400">
        <SearchX class="w-10 h-10 mx-auto mb-2 text-gray-300" aria-hidden="true" />
        <p>{{ t('miembros.sinResultados') }}</p>
      </div>

      <div v-else>
        <!-- Cabecera tabla -->
        <div class="grid grid-cols-12 gap-2 px-4 py-3 bg-gray-50 border-b border-gray-100 text-xs font-semibold text-gray-500 uppercase tracking-wide">
          <div class="col-span-5">{{ t('miembros.colMiembro') }}</div>
          <div class="col-span-3 hidden md:block">{{ t('miembros.colCrmCasa') }}</div>
          <div class="col-span-2 hidden lg:block">{{ t('miembros.colNivel') }}</div>
          <div class="col-span-2 text-right">{{ t('miembros.colAcciones') }}</div>
        </div>

        <!-- Filas -->
        <div class="divide-y divide-gray-50">
          <div
            v-for="m in miembrosFiltrados"
            :key="m.id"
            class="grid grid-cols-12 gap-2 px-4 py-3.5 items-center hover:bg-gray-50 transition-colors"
          >
            <!-- Avatar + nombre -->
            <div class="col-span-7 md:col-span-5 flex items-center gap-3">
              <div class="w-9 h-9 bg-adn-verde rounded-full flex items-center justify-center flex-shrink-0">
                <span class="text-white text-sm font-bold">{{ m.nombre[0] }}</span>
              </div>
              <div class="min-w-0">
                <p class="font-medium text-gray-900 text-sm truncate">{{ m.nombre }} {{ m.apellido }}</p>
                <p class="text-xs text-gray-400 truncate">{{ m.email }}</p>
              </div>
            </div>

            <!-- CRM-ID y casa -->
            <div class="col-span-3 hidden md:block">
              <p class="text-xs font-mono text-gray-600 font-medium">{{ m.crm_id }}</p>
              <p class="text-xs text-gray-400 truncate">
                {{ m.casas_oracion?.nombre ?? '—' }}
              </p>
            </div>

            <!-- Nivel compromiso -->
            <div class="col-span-2 hidden lg:block">
              <span :class="['text-xs px-2 py-1 rounded-full font-medium capitalize', claseNivel(m.nivel_compromiso)]">
                {{ etiquetaNivel(m.nivel_compromiso) }}
              </span>
            </div>

            <!-- Acciones -->
            <div class="col-span-5 md:col-span-2 flex items-center justify-end gap-2">
              <RouterLink
                :to="`/miembros/${m.id}`"
                class="text-xs text-adn-verde hover:underline font-medium"
              >
                {{ t('miembros.verPerfil') }}
              </RouterLink>
            </div>
          </div>
        </div>

        <!-- Paginación / total -->
        <div class="px-4 py-3 bg-gray-50 border-t border-gray-100 flex items-center justify-between">
          <p class="text-xs text-gray-500">
            {{ t('miembros.mostrando', { visibles: miembrosFiltrados.length, total: miembros.length }, miembros.length) }}
          </p>
          <div class="flex gap-2">
            <button
              v-if="pagina > 0"
              @click="pagina--"
              class="text-xs text-adn-verde hover:underline font-medium"
            >{{ t('miembros.anterior') }}</button>
            <button
              v-if="hayMasPaginas"
              @click="pagina++"
              class="text-xs text-adn-verde hover:underline font-medium"
            >{{ t('miembros.siguiente') }}</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal: Nuevo miembro -->
    <div
      v-if="abrirNuevo"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="abrirNuevo = false"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ t('miembros.registrarTitulo') }}</h2>
        <form @submit.prevent="crearMiembro" class="space-y-4">
          <div :class="auth.modoAlias ? '' : 'grid grid-cols-2 gap-4'">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">{{ auth.modoAlias ? t('miembros.alias') : t('miembros.nombre') }}</label>
              <input v-model="nuevo.nombre" type="text" required :placeholder="auth.modoAlias ? t('miembros.ejemploAlias') : t('miembros.ejemploNombre')"
                class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm" />
              <p v-if="auth.modoAlias" class="text-xs text-gray-500 mt-1">{{ t('miembros.aliasAyuda') }}</p>
            </div>
            <div v-if="!auth.modoAlias">
              <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('miembros.apellido') }}</label>
              <input v-model="nuevo.apellido" type="text" required :placeholder="t('miembros.ejemploApellido')"
                class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm" />
            </div>
          </div>
          <div v-if="!auth.modoAlias">
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('miembros.email') }}</label>
            <input v-model="nuevo.email" type="email" :placeholder="t('miembros.ejemploEmail')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('miembros.telefono') }}</label>
            <input v-model="nuevo.telefono" type="tel" placeholder="+34 600 000 000"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('miembros.casa') }}</label>
            <select v-model="nuevo.casa_id"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm">
              <option value="">{{ t('miembros.sinAsignar') }}</option>
              <option v-for="c in casas" :key="c.id" :value="c.id">{{ c.nombre }} ({{ c.codigo_zona }})</option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('miembros.nivelCompromiso') }}</label>
            <select v-model="nuevo.nivel_compromiso"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm">
              <option v-for="n in NIVELES_COMPROMISO" :key="n" :value="n">{{ t(ETIQUETAS_COMPROMISO[n]) }}</option>
            </select>
          </div>
          <div v-if="error" class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{{ t(error) }}</div>
          <div class="flex gap-3 pt-2">
            <button type="button" @click="abrirNuevo = false" class="btn-secondary flex-1">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="guardando" class="btn-primary flex-1 disabled:opacity-60">
              {{ guardando ? t('comun.guardando') : t('miembros.registrar') }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { LoaderCircle, Search, SearchX, Upload, UserPlus } from '@lucide/vue'
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { esLimitePlan } from '@/lib/plan'
import { useAuthStore } from '@/stores/auth'
import ImportarMiembros from '@/components/ImportarMiembros.vue'
import { ETIQUETAS_COMPROMISO, NIVELES_COMPROMISO } from '@/lib/supabase'
import type { NivelCompromiso } from '@/lib/supabase'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
const auth = useAuthStore()

const cargando = ref(true)
const miembros = ref<any[]>([])
const casas = ref<any[]>([])
const busqueda = ref('')
const filtroNivel = ref('')
const filtroEstado = ref('activo')
const pagina = ref(0)
const POR_PAGINA = 20
const abrirNuevo = ref(false)
const abrirImportar = ref(false)
// Importar necesita su permiso y también el de registrar, que es el que exige la base al insertar
const puedeImportar = computed(() => auth.can('miembros.importar') && auth.can('miembros.crear'))
const guardando = ref(false)
// Clave de traducción del error visible ('' = sin error)
const error = ref('')

const nuevo = ref({
  nombre: '',
  apellido: '',
  email: '',
  telefono: '',
  casa_id: '',
  nivel_compromiso: 'nuevo' as NivelCompromiso,
})

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

// En la tabla "en_crecimiento" se muestra en su forma corta
function etiquetaNivel(nivel: NivelCompromiso) {
  if (nivel === 'en_crecimiento') return t('compromiso.en_crecimiento_corto')
  const clave = ETIQUETAS_COMPROMISO[nivel]
  return clave ? t(clave) : nivel
}

const miembrosFiltrados = computed(() => {
  let lista = [...miembros.value]

  // Filtro estado
  if (filtroEstado.value === 'activo') lista = lista.filter(m => m.activo)
  else if (filtroEstado.value === 'inactivo') lista = lista.filter(m => !m.activo)

  // Filtro nivel
  if (filtroNivel.value) lista = lista.filter(m => m.nivel_compromiso === filtroNivel.value)

  // Búsqueda
  if (busqueda.value.trim()) {
    const q = busqueda.value.toLowerCase()
    lista = lista.filter(m =>
      `${m.nombre} ${m.apellido}`.toLowerCase().includes(q) ||
      (m.email ?? '').toLowerCase().includes(q) ||
      (m.crm_id ?? '').toLowerCase().includes(q)
    )
  }

  // Paginación
  const inicio = pagina.value * POR_PAGINA
  return lista.slice(inicio, inicio + POR_PAGINA)
})

const hayMasPaginas = computed(() => {
  return (pagina.value + 1) * POR_PAGINA < miembros.value.length
})

async function cargarDatos() {
  cargando.value = true
  const [miembrosRes, casasRes] = await Promise.all([
    supabase
      .from('miembros')
      .select('id, nombre, apellido, email, crm_id, nivel_compromiso, activo, casas_oracion(nombre, codigo_zona)')
      .order('nombre'),
    supabase
      .from('casas_oracion')
      .select('id, nombre, codigo_zona')
      .eq('activa', true)
      .order('nombre'),
  ])
  miembros.value = miembrosRes.data ?? []
  casas.value = casasRes.data ?? []
  cargando.value = false
}

async function crearMiembro() {
  error.value = ''
  guardando.value = true
  const { error: err } = await supabase.from('miembros').insert({
    nombre: nuevo.value.nombre,
    apellido: auth.modoAlias ? '' : nuevo.value.apellido,
    email: auth.modoAlias ? null : (nuevo.value.email || null),
    telefono: nuevo.value.telefono || null,
    casa_oracion_id: nuevo.value.casa_id || null,
    nivel_compromiso: nuevo.value.nivel_compromiso,
    activo: true,
  })
  guardando.value = false
  if (err) {
    error.value = esLimitePlan(err) ? 'plan.limiteMiembros' : 'miembros.errorRegistrar'
  } else {
    abrirNuevo.value = false
    nuevo.value = { nombre: '', apellido: '', email: '', telefono: '', casa_id: '', nivel_compromiso: 'nuevo' }
    await cargarDatos()
  }
}

const route = useRoute()
const router = useRouter()

onMounted(() => {
  cargarDatos()
  // Llegada desde el botón "Nuevo miembro" del panel: abre el formulario y limpia la URL
  if (route.query.nuevo === '1') {
    abrirNuevo.value = true
    router.replace({ path: route.path })
  }
})
</script>
