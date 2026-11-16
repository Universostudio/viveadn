<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('lideres.zonas.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('lideres.zonas.subtitulo') }}</p>
    </div>

    <p v-if="aviso" role="status" data-test="aviso" :class="['text-sm px-4 py-3 rounded-lg border', aviso.error ? 'bg-red-50 text-red-700 border-red-200' : 'bg-green-50 text-green-700 border-green-200']">{{ aviso.texto }}</p>

    <form v-if="puedeGestionar" class="card space-y-3" aria-labelledby="zn-nueva" @submit.prevent="crear" data-test="form-zona">
      <h2 id="zn-nueva" class="text-base font-semibold text-gray-900">{{ t('lideres.zonas.nueva') }}</h2>
      <div class="flex flex-wrap items-end gap-3">
        <div>
          <label for="zn-codigo" class="block text-xs font-medium text-gray-600 mb-1">{{ t('lideres.zonas.codigo') }}</label>
          <input id="zn-codigo" v-model="nueva.codigo" required maxlength="10" data-test="zona-codigo" aria-describedby="zn-codigo-ayuda"
            class="w-32 text-sm border border-gray-200 rounded-lg px-3 py-2 font-mono uppercase focus:outline-none focus:ring-2 focus:ring-adn-verde" />
        </div>
        <div class="flex-1 min-w-[12rem]">
          <label for="zn-nombre" class="block text-xs font-medium text-gray-600 mb-1">{{ t('lideres.zonas.nombre') }}</label>
          <input id="zn-nombre" v-model="nueva.nombre" required maxlength="80" data-test="zona-nombre"
            class="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" />
        </div>
        <button type="submit" :disabled="guardando" class="btn-primary text-sm disabled:opacity-60" data-test="zona-crear">{{ t('lideres.zonas.crear') }}</button>
      </div>
      <p id="zn-codigo-ayuda" class="text-xs text-gray-500">{{ t('lideres.zonas.codigoAyuda') }}</p>
    </form>

    <div v-if="cargando" class="py-12 text-center text-gray-500 text-sm">{{ t('comun.cargando') }}</div>
    <section v-else class="card" aria-labelledby="zn-lista">
      <h2 id="zn-lista" class="text-base font-semibold text-gray-900 mb-3">{{ t('lideres.zonas.lista', { n: zonas.length }) }}</h2>
      <p v-if="!zonas.length" class="text-sm text-gray-500" data-test="sin-zonas">{{ t('lideres.zonas.vacia') }}</p>
      <p v-else-if="puedeGestionar && !candidatosZona.length" class="text-sm text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 mb-3" data-test="sin-candidatos">{{ t('lideres.zonas.sinCandidatos') }}</p>
      <ul class="divide-y divide-gray-100">
        <li v-for="z in zonas" :key="z.id" :data-zona="z.id" class="py-3 flex flex-wrap items-center gap-3">
          <div class="min-w-0 flex-1">
            <p class="font-medium text-gray-900">{{ z.nombre }} <span class="ml-1 text-xs font-mono text-adn-verde">{{ z.codigo }}</span>
              <span v-if="z.activa === false" class="ml-1 text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full">{{ t('comun.inactiva') }}</span></p>
            <p class="text-xs text-gray-500">{{ t('lideres.zonas.casasN', { n: conteo.porZona[z.id] ?? 0 }, conteo.porZona[z.id] ?? 0) }}</p>
          </div>
          <div class="flex items-center gap-2">
            <label :for="`zn-lider-${z.id}`" class="text-xs text-gray-600">{{ t('lideres.zonas.lider') }}</label>
            <select v-if="puedeGestionar" :id="`zn-lider-${z.id}`" :value="z.lider_id ?? ''" data-test="zona-lider" @change="cambiarLider(z, ($event.target as HTMLSelectElement).value || null)"
              class="text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option value="">{{ t('lideres.sinLider') }}</option>
              <option v-for="p in candidatosZona" :key="p.id" :value="p.id">{{ p.nombre }} {{ p.apellido }}</option>
            </select>
            <span v-else :id="`zn-lider-${z.id}`" class="text-sm text-gray-700">{{ nombreLider(z.lider_id) }}</span>
          </div>
          <button v-if="puedeGestionar" type="button" class="text-xs px-3 py-2 rounded-lg border border-gray-200 text-gray-700 hover:border-adn-verde focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde"
            :aria-pressed="z.activa !== false" data-test="zona-activa" @click="alternar(z)">{{ z.activa === false ? t('lideres.zonas.activar') : t('lideres.zonas.desactivar') }}</button>
        </li>
      </ul>
      <p v-if="conteo.sinZona" class="text-xs text-amber-800 mt-3" data-test="casas-sin-zona">{{ t('lideres.zonas.casasSinZona', { n: conteo.sinZona }, conteo.sinZona) }}</p>
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { candidatos, casasPorZona, codigoDeZonaValido, normalizarCodigoZona, type PerfilBasico } from '@/lib/lideres'

const { t } = useI18n()
const auth = useAuthStore()
const puedeGestionar = computed(() => auth.can('zonas.gestionar'))

const cargando = ref(true)
const zonas = ref<any[]>([])
const casas = ref<{ zona_id: string | null }[]>([])
const perfiles = ref<PerfilBasico[]>([])
const roles = ref<any[]>([])
const guardando = ref(false)
const aviso = ref<{ texto: string; error: boolean } | null>(null)
const avisar = (texto: string, error = false) => { aviso.value = { texto, error } }
const nueva = ref({ codigo: '', nombre: '' })

const conteo = computed(() => casasPorZona(casas.value))
const candidatosZona = computed(() => candidatos(roles.value, perfiles.value, 'casas.ver_zona'))
const nombreLider = (id: string | null) => {
  const p = perfiles.value.find(x => x.id === id)
  return p ? `${p.nombre} ${p.apellido}` : t('lideres.sinLider')
}

async function cargar() {
  cargando.value = true
  const [z, c, r, p] = await Promise.all([
    supabase.from('zonas').select('id, codigo, nombre, lider_id, activa').order('nombre'),
    supabase.from('casas_oracion').select('id, zona_id'),
    supabase.from('roles').select('clave, es_propietario, rol_permisos(permiso)'),
    supabase.from('perfiles').select('id, nombre, apellido, rol, activo').eq('activo', true).order('nombre'),
  ])
  if (z.error) avisar(t('lideres.error'), true)
  zonas.value = z.data ?? []; casas.value = c.data ?? []; roles.value = r.data ?? []; perfiles.value = p.data ?? []
  cargando.value = false
}

async function crear() {
  const codigo = normalizarCodigoZona(nueva.value.codigo)
  if (!codigoDeZonaValido(codigo)) { avisar(t('lideres.zonas.codigoInvalido'), true); return }
  guardando.value = true
  const { error } = await supabase.from('zonas').insert({ codigo, nombre: nueva.value.nombre.trim() })
  guardando.value = false
  if (error) { avisar(t('lideres.zonas.errorCrear'), true); return }
  nueva.value = { codigo: '', nombre: '' }
  avisar(t('lideres.zonas.creada'))
  await cargar()
}

async function cambiarLider(z: any, id: string | null) {
  const { error } = await supabase.from('zonas').update({ lider_id: id }).eq('id', z.id)
  if (error) { avisar(t('lideres.zonas.errorLider'), true); await cargar(); return }
  z.lider_id = id
  avisar(t('lideres.zonas.liderGuardado'))
}

async function alternar(z: any) {
  const activa = z.activa === false
  const { error } = await supabase.from('zonas').update({ activa }).eq('id', z.id)
  if (error) { avisar(t('lideres.error'), true); return }
  z.activa = activa
  avisar(t(activa ? 'lideres.zonas.activada' : 'lideres.zonas.desactivada'))
}

onMounted(cargar)
</script>
