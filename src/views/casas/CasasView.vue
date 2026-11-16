<template>
  <div class="p-4 sm:p-6 space-y-6">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('casas.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('casas.subtitulo') }}</p>
      </div>
      <button v-if="puedeCrearCasa" @click="abrirNueva = true" class="btn-primary flex items-center gap-2" data-test="nueva-casa">
        <Plus class="w-4 h-4" aria-hidden="true" /> {{ t('casas.nueva') }}
      </button>
    </div>

    <p v-if="aviso" role="status" data-test="aviso" :class="['text-sm px-4 py-3 rounded-lg border', aviso.error ? 'bg-red-50 text-red-700 border-red-200' : 'bg-green-50 text-green-700 border-green-200']">{{ aviso.texto }}</p>

    <!-- Stats -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <div class="card-stat">
        <House class="w-6 h-6 text-adn-verde flex-shrink-0" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ casas.length }}</p>
          <p class="text-xs text-gray-500">{{ t('casas.total') }}</p>
        </div>
      </div>
      <div class="card-stat">
        <CircleCheck class="w-6 h-6 text-emerald-600 flex-shrink-0" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ casas.filter(c => c.activa).length }}</p>
          <p class="text-xs text-gray-500">{{ t('casas.activas') }}</p>
        </div>
      </div>
      <div class="card-stat">
        <Users class="w-6 h-6 text-adn-verde flex-shrink-0" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ totalMiembros }}</p>
          <p class="text-xs text-gray-500">{{ t('casas.miembrosAsignados') }}</p>
        </div>
      </div>
      <div class="card-stat">
        <ChartColumn class="w-6 h-6 text-adn-verde flex-shrink-0" aria-hidden="true" />
        <div>
          <p class="text-2xl font-bold text-gray-900">{{ promedioMiembros }}</p>
          <p class="text-xs text-gray-500">{{ t('casas.promedio') }}</p>
        </div>
      </div>
    </div>

    <!-- Buscador -->
    <div class="card">
      <div class="flex gap-3">
        <div class="flex-1 relative">
          <Search class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" aria-hidden="true" />
          <input
            v-model="busqueda"
            type="text"
            :placeholder="t('casas.buscar')"
            class="w-full pl-9 pr-4 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde"
          />
        </div>
        <select
          v-model="filtroZona"
          class="text-sm border border-gray-200 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-adn-verde"
        >
          <option value="">{{ t('casas.todasZonas') }}</option>
          <option v-for="z in zonasDisponibles" :key="z" :value="z">{{ z }}</option>
        </select>
      </div>
    </div>

    <!-- Grid de casas -->
    <div v-if="cargando" class="py-16 text-center text-gray-400">
      <LoaderCircle class="w-8 h-8 mx-auto mb-2 animate-spin text-gray-300" aria-hidden="true" />
      <p>{{ t('casas.cargando') }}</p>
    </div>

    <div v-else-if="casasFiltradas.length === 0" class="py-16 text-center text-gray-400 card">
      <SearchX class="w-10 h-10 mx-auto mb-2 text-gray-300" aria-hidden="true" />
      <p>{{ t('casas.sinResultados') }}</p>
    </div>

    <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
      <div
        v-for="casa in casasFiltradas"
        :key="casa.id"
        class="card hover:shadow-md transition-shadow cursor-pointer"
        :data-casa="casa.id"
        tabindex="0" role="button" :aria-label="casa.nombre"
        @click="casaActiva = casa" @keydown.enter.self="casaActiva = casa" @keydown.space.self.prevent="casaActiva = casa"
      >
        <!-- Cabecera -->
        <div class="flex items-start justify-between mb-3">
          <div>
            <p class="font-semibold text-gray-900">{{ casa.nombre }}</p>
            <p class="text-xs font-mono text-adn-verde font-bold mt-0.5">{{ casa.codigo_zona }}</p>
          </div>
          <span :class="['text-xs px-2 py-1 rounded-full font-medium', casa.activa ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500']">
            {{ casa.activa ? t('comun.activa') : t('comun.inactiva') }}
          </span>
        </div>

        <!-- Info -->
        <div class="space-y-1.5 text-sm text-gray-600">
          <div class="flex items-center gap-2">
            <MapPin class="w-4 h-4 text-gray-400 flex-shrink-0" aria-hidden="true" />
            <span class="truncate">{{ casa.ciudad ?? '—' }}, {{ casa.pais ?? '—' }}</span>
          </div>
          <div v-if="casa.lider_perfil" class="flex items-center gap-2">
            <UserRound class="w-4 h-4 text-gray-400 flex-shrink-0" aria-hidden="true" />
            <span>{{ casa.lider_perfil.nombre }} {{ casa.lider_perfil.apellido }}</span>
          </div>
          <p v-else class="text-xs text-amber-700" data-test="sin-lider">{{ t('lideres.sinLider') }}</p>
          <p v-if="!casa.zona_id" class="text-xs text-amber-700" data-test="sin-zona">{{ t('lideres.casa.sinZona') }}</p>
        </div>

        <!-- Contador miembros -->
        <div class="mt-4 pt-3 border-t border-gray-100 flex items-center justify-between">
          <span class="text-sm text-gray-500">
            <span class="font-bold text-gray-900">{{ casa.count_miembros ?? 0 }}</span> {{ t('casas.miembros', casa.count_miembros ?? 0) }}
          </span>
          <span class="text-xs text-adn-verde hover:underline font-medium">{{ t('casas.verDetalle') }}</span>
        </div>
      </div>
    </div>

    <!-- Modal: Detalle casa -->
    <div
      v-if="casaActiva"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="casaActiva = null" @keydown.esc="casaActiva = null"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-lg p-6 max-h-[85vh] overflow-y-auto" role="dialog" aria-modal="true" aria-labelledby="ca-titulo" data-test="detalle-casa" tabindex="-1" ref="dialogoCasa">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 id="ca-titulo" class="text-lg font-bold text-gray-900">{{ casaActiva.nombre }}</h2>
            <p class="text-sm font-mono text-adn-verde">{{ casaActiva.codigo_zona }}</p>
          </div>
          <button @click="casaActiva = null" class="text-gray-400 hover:text-gray-600 text-xl" :aria-label="t('comun.cerrar')">×</button>
        </div>

        <div class="space-y-4 text-sm">
          <!-- Ubicación -->
          <div class="bg-gray-50 rounded-xl p-4">
            <p class="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">{{ t('casas.ubicacion') }}</p>
            <dl class="space-y-1">
              <div class="flex justify-between">
                <dt class="text-gray-500">{{ t('casas.pais') }}</dt>
                <dd class="font-medium">{{ casaActiva.pais ?? '—' }}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-500">{{ t('casas.estadoProvincia') }}</dt>
                <dd class="font-medium">{{ casaActiva.estado_provincia ?? '—' }}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-500">{{ t('casas.ciudad') }}</dt>
                <dd class="font-medium">{{ casaActiva.ciudad ?? '—' }}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-500">{{ t('casas.direccion') }}</dt>
                <dd class="font-medium text-right max-w-xs">{{ casaActiva.direccion ?? '—' }}</dd>
              </div>
            </dl>
          </div>

          <!-- Zona de supervisión y líder: los cambia quien puede editar casas -->
          <div v-if="puedeEditarCasa" class="bg-adn-arena rounded-xl p-4 space-y-3" data-test="liderazgo">
            <div>
              <label for="ca-zona" class="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">{{ t('lideres.casa.zona') }}</label>
              <select id="ca-zona" data-test="casa-zona" :value="casaActiva.zona_id ?? ''" @change="cambiarZona(($event.target as HTMLSelectElement).value || null)"
                class="w-full text-sm border border-gray-200 rounded-lg px-2 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-adn-verde">
                <option value="">{{ t('lideres.casa.sinZona') }}</option>
                <option v-for="z in zonas.filter(z => z.activa !== false)" :key="z.id" :value="z.id">{{ z.nombre }} ({{ z.codigo }})</option>
              </select>
              <p v-if="!zonas.length" class="text-xs text-gray-500 mt-1">{{ t('lideres.casa.sinZonasCreadas') }} <RouterLink to="/zonas" class="underline text-adn-verde">{{ t('lideres.casa.crearZonas') }}</RouterLink></p>
            </div>
            <div>
              <label for="ca-lider" class="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">{{ t('casas.lider') }}</label>
              <select id="ca-lider" data-test="casa-lider" :value="casaActiva.lider_id ?? ''" @change="cambiarLiderCasa(($event.target as HTMLSelectElement).value || null)"
                class="w-full text-sm border border-gray-200 rounded-lg px-2 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-adn-verde">
                <option value="">{{ t('lideres.sinLider') }}</option>
                <option v-for="p in candidatosCasa" :key="p.id" :value="p.id">{{ p.nombre }} {{ p.apellido }}</option>
              </select>
              <p v-if="!candidatosCasa.length" class="text-xs text-amber-800 mt-1" data-test="sin-candidatos-casa">{{ t('lideres.casa.sinCandidatos') }}</p>
            </div>
          </div>
          <div v-else-if="casaActiva.lider_perfil" class="bg-adn-arena rounded-xl p-4">
            <p class="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">{{ t('casas.lider') }}</p>
            <p class="font-semibold text-gray-900">{{ casaActiva.lider_perfil.nombre }} {{ casaActiva.lider_perfil.apellido }}</p>
          </div>

          <!-- Miembros en esa casa -->
          <div>
            <p class="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">
              {{ t('casas.miembrosCasa', { n: miembrosCasa.length }) }}
            </p>
            <div v-if="!miembrosCasa.length" class="text-gray-400 text-center py-4">{{ t('casas.sinMiembros') }}</div>
            <div v-else class="space-y-1 max-h-40 overflow-y-auto">
              <div
                v-for="m in miembrosCasa"
                :key="m.id"
                class="flex items-center gap-2 p-2 rounded-lg hover:bg-gray-50"
              >
                <div class="w-7 h-7 bg-adn-verde rounded-full flex items-center justify-center flex-shrink-0">
                  <span class="text-white text-xs font-bold">{{ m.nombre[0] }}</span>
                </div>
                <span class="text-sm">{{ m.nombre }} {{ m.apellido }}</span>
                <span class="ml-auto text-xs text-gray-400 font-mono">{{ m.crm_id }}</span>
                <button v-if="puedeAsignarPersonas" type="button" data-test="quitar-persona" class="text-xs text-red-700 underline focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde rounded"
                  @click="quitarPersona(m)">{{ t('lideres.casa.quitar') }}<span class="sr-only"> {{ m.nombre }} {{ m.apellido }}</span></button>
              </div>
            </div>
            <div v-if="puedeAsignarPersonas" class="mt-3 space-y-2" data-test="anadir-persona">
              <label for="ca-buscar" class="text-xs font-medium text-gray-600 block">{{ t('lideres.casa.anadir') }}</label>
              <input id="ca-buscar" v-model="busquedaSinCasa" type="search" autocomplete="off" :placeholder="t('lideres.casa.buscarPersona')" data-test="buscar-persona"
                class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" />
              <p v-if="!sinCasaFiltradas.length" class="text-xs text-gray-500" data-test="nadie-sin-casa">{{ t('lideres.casa.nadieSinCasa') }}</p>
              <ul v-else class="max-h-36 overflow-y-auto divide-y divide-gray-50 border border-gray-100 rounded-lg">
                <li v-for="m in sinCasaFiltradas.slice(0, 20)" :key="m.id" class="flex items-center gap-2 px-2 py-1.5 text-sm" data-test="sin-casa-fila">
                  <span class="flex-1 truncate">{{ m.nombre }} {{ m.apellido }}</span>
                  <button type="button" class="text-xs px-2 py-1 rounded border border-adn-verde text-adn-verde focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde" data-test="anadir"
                    @click="anadirPersona(m)">{{ t('lideres.casa.anadirA') }}<span class="sr-only"> {{ m.nombre }} {{ m.apellido }}</span></button>
                </li>
              </ul>
              <p v-if="sinCasaFiltradas.length > 20" class="text-xs text-gray-500">{{ t('lideres.casa.afinaBusqueda', { n: sinCasaFiltradas.length - 20 }) }}</p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal: Nueva casa -->
    <div
      v-if="abrirNueva"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="abrirNueva = false"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 max-h-[90vh] overflow-y-auto">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ t('casas.nuevaTitulo') }}</h2>
        <form @submit.prevent="crearCasa" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('casas.nombre') }}</label>
            <input v-model="nueva.nombre" type="text" required :placeholder="t('casas.ejemploNombre')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm" />
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('casas.zona') }}</label>
              <select v-model="nueva.zona" required
                class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm">
                <option value="">{{ t('comun.seleccionar') }}</option>
                <option v-for="z in ZONAS" :key="z.prefijo" :value="z.prefijo">{{ t(z.nombre) }} ({{ z.prefijo }})</option>
              </select>
              <p class="text-xs text-gray-400 mt-1">{{ t('casas.codigoAyuda') }}</p>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('casas.paisObligatorio') }}</label>
              <input v-model="nueva.pais" type="text" required :placeholder="t('casas.ejemploPais')"
                class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm" />
            </div>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('casas.ciudadObligatoria') }}</label>
            <input v-model="nueva.ciudad" type="text" required maxlength="80" :placeholder="t('casas.ejemploCiudad')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('casas.direccionObligatoria') }}</label>
            <input v-model="nueva.direccion" type="text" required maxlength="200" :placeholder="t('casas.ejemploDireccion')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-adn-verde text-sm" />
          </div>
          <p v-if="errorNueva" class="text-sm text-red-600">{{ t(errorNueva) }}</p>
          <div class="flex gap-3 pt-2">
            <button type="button" @click="abrirNueva = false" class="btn-secondary flex-1">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="guardando" class="btn-primary flex-1 disabled:opacity-60">
              {{ guardando ? t('comun.creando') : t('casas.crear') }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ChartColumn, CircleCheck, House, LoaderCircle, MapPin, Plus, Search, SearchX, UserRound, Users } from '@lucide/vue'
import { ref, computed, nextTick, onMounted, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { candidatos, type PerfilBasico } from '@/lib/lideres'

const { t } = useI18n()
const auth = useAuthStore()

// Permisos de esta pantalla (la base los exige igualmente): se ofrece solo lo que la persona puede hacer
const puedeCrearCasa = computed(() => auth.can('casas.crear'))
const puedeEditarCasa = computed(() => auth.can('casas.editar'))
const puedeAsignarPersonas = computed(() => auth.can('miembros.editar'))
const aviso = ref<{ texto: string; error: boolean } | null>(null)
const avisar = (texto: string, error = false) => { aviso.value = { texto, error } }
const perfiles = ref<PerfilBasico[]>([])
const roles = ref<any[]>([])
const sinCasa = ref<any[]>([])
const busquedaSinCasa = ref('')
const candidatosCasa = computed(() => candidatos(roles.value, perfiles.value, 'casas.ver_propia'))
const sinCasaFiltradas = computed(() => {
  const q = busquedaSinCasa.value.trim().toLowerCase()
  return q ? sinCasa.value.filter(m => `${m.nombre} ${m.apellido}`.toLowerCase().includes(q)) : sinCasa.value
})
const dialogoCasa = ref<HTMLElement | null>(null)

const cargando = ref(true)
const casas = ref<any[]>([])
const zonas = ref<any[]>([])
const busqueda = ref('')
const filtroZona = ref('')
const casaActiva = ref<any>(null)
const miembrosCasa = ref<any[]>([])
const abrirNueva = ref(false)
const guardando = ref(false)
// Clave de traducción del error visible ('' = sin error)
const errorNueva = ref('')

// Zonas del sistema ZONA-CÓDIGO; el servidor añade las 6 cifras. nombre: clave de traducción
const ZONAS = [
  { prefijo: 'ZN', nombre: 'zonas.norte' },
  { prefijo: 'ZS', nombre: 'zonas.sur' },
  { prefijo: 'ZE', nombre: 'zonas.este' },
  { prefijo: 'ZO', nombre: 'zonas.oeste' },
  { prefijo: 'ZC', nombre: 'zonas.centro' },
]

const nueva = ref({ nombre: '', zona: '', pais: '', ciudad: '', direccion: '' })

const zonasDisponibles = computed(() => {
  const prefijos = new Set(casas.value.map(c => c.codigo_zona?.split('-')[0]).filter(Boolean))
  return [...prefijos]
})

const totalMiembros = computed(() => casas.value.reduce((acc, c) => acc + (c.count_miembros ?? 0), 0))
const promedioMiembros = computed(() => {
  const activas = casas.value.filter(c => c.activa).length
  return activas ? Math.round(totalMiembros.value / activas) : 0
})

const casasFiltradas = computed(() => {
  let lista = [...casas.value]
  if (filtroZona.value) lista = lista.filter(c => c.codigo_zona?.startsWith(filtroZona.value))
  if (busqueda.value.trim()) {
    const q = busqueda.value.toLowerCase()
    lista = lista.filter(c =>
      c.nombre?.toLowerCase().includes(q) ||
      c.codigo_zona?.toLowerCase().includes(q) ||
      `${c.lider_perfil?.nombre} ${c.lider_perfil?.apellido}`.toLowerCase().includes(q)
    )
  }
  return lista
})

// Cargar miembros al abrir detalle de casa
let focoPrevio: HTMLElement | null = null
watch(casaActiva, async (casa, anterior) => {
  if (!casa) { miembrosCasa.value = []; busquedaSinCasa.value = ''; if (anterior) { focoPrevio?.focus?.(); focoPrevio = null } return }
  if (!anterior) { focoPrevio = document.activeElement as HTMLElement | null; await nextTick(); dialogoCasa.value?.focus() }
  await cargarPersonas(casa)
})

async function cargarPersonas(casa: any) {
  const { data } = await supabase
    .from('miembros')
    .select('id, nombre, apellido, crm_id')
    .eq('casa_oracion_id', casa.id)
    .eq('activo', true)
    .order('nombre')
  miembrosCasa.value = data ?? []
  if (puedeAsignarPersonas.value) await cargarSinCasa()
}

async function cargarSinCasa() {
  const { data } = await supabase.from('miembros').select('id, nombre, apellido').is('casa_oracion_id', null).eq('activo', true).order('nombre').limit(500)
  sinCasa.value = data ?? []
}

async function cargarCandidatos() {
  if (!puedeEditarCasa.value) return
  const [r, p] = await Promise.all([
    supabase.from('roles').select('clave, es_propietario, rol_permisos(permiso)'),
    supabase.from('perfiles').select('id, nombre, apellido, rol, activo').eq('activo', true).order('nombre'),
  ])
  roles.value = r.data ?? []; perfiles.value = p.data ?? []
}

async function actualizarCasa(campos: Record<string, any>, okTexto: string) {
  const casa = casaActiva.value
  if (!casa) return false
  const { error } = await supabase.from('casas_oracion').update(campos).eq('id', casa.id)
  if (error) { avisar(t('lideres.error'), true); return false }
  Object.assign(casa, campos)
  avisar(okTexto)
  return true
}
const cambiarZona = (id: string | null) => actualizarCasa({ zona_id: id }, t('lideres.casa.zonaGuardada'))
async function cambiarLiderCasa(id: string | null) {
  const ok = await actualizarCasa({ lider_id: id }, t('lideres.casa.liderGuardado'))
  if (ok && casaActiva.value) {
    const p = perfiles.value.find(x => x.id === id)
    casaActiva.value.lider_perfil = p ? { nombre: p.nombre, apellido: p.apellido } : null
  }
}

async function anadirPersona(m: any) {
  const casa = casaActiva.value
  if (!casa) return
  const { error } = await supabase.from('miembros').update({ casa_oracion_id: casa.id }).eq('id', m.id)
  if (error) { avisar(t('lideres.error'), true); return }
  sinCasa.value = sinCasa.value.filter(x => x.id !== m.id)
  miembrosCasa.value = [...miembrosCasa.value, { ...m, crm_id: m.crm_id ?? '' }].sort((a, b) => a.nombre.localeCompare(b.nombre))
  casa.count_miembros = (casa.count_miembros ?? 0) + 1
  avisar(t('lideres.casa.personaAnadida', { nombre: `${m.nombre} ${m.apellido}` }))
}

async function quitarPersona(m: any) {
  const casa = casaActiva.value
  if (!casa) return
  const { error } = await supabase.from('miembros').update({ casa_oracion_id: null }).eq('id', m.id)
  if (error) { avisar(t('lideres.error'), true); return }
  miembrosCasa.value = miembrosCasa.value.filter(x => x.id !== m.id)
  sinCasa.value = [...sinCasa.value, m].sort((a, b) => a.nombre.localeCompare(b.nombre))
  casa.count_miembros = Math.max(0, (casa.count_miembros ?? 1) - 1)
  avisar(t('lideres.casa.personaQuitada', { nombre: `${m.nombre} ${m.apellido}` }))
}

async function cargarDatos() {
  cargando.value = true
  const [casasRes, zonasRes] = await Promise.all([
    supabase
      .from('casas_oracion')
      .select('*, lider_perfil:perfiles!casas_oracion_lider_fk(nombre, apellido), count_miembros:miembros!miembros_casa_oracion_fk(count)')
      .order('nombre'),
    supabase.from('zonas').select('id, nombre, codigo, activa').order('nombre'),
  ])
  // Normalizar el count
  casas.value = (casasRes.data ?? []).map(c => ({
    ...c,
    count_miembros: c.count_miembros?.[0]?.count ?? 0
  }))
  zonas.value = zonasRes.data ?? []
  cargando.value = false
}

async function crearCasa() {
  guardando.value = true
  errorNueva.value = ''
  const { error } = await supabase.from('casas_oracion').insert({
    nombre: nueva.value.nombre.trim(),
    // Solo el prefijo de zona: el servidor genera el código completo
    codigo_zona: nueva.value.zona,
    pais: nueva.value.pais.trim(),
    ciudad: nueva.value.ciudad.trim(),
    direccion: nueva.value.direccion.trim(),
    activa: true,
  })
  guardando.value = false
  if (error) {
    errorNueva.value = 'casas.errorCrear'
    return
  }
  abrirNueva.value = false
  nueva.value = { nombre: '', zona: '', pais: '', ciudad: '', direccion: '' }
  await cargarDatos()
}

onMounted(() => { void cargarDatos(); void cargarCandidatos() })
</script>
