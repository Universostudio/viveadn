<template>
  <div class="p-4 sm:p-6 space-y-6">
    <RouterLink to="/eventos" class="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-adn-verde">
      <ArrowLeft class="w-4 h-4" aria-hidden="true" /> {{ t('eventos.volver') }}
    </RouterLink>

    <p v-if="cargando" class="text-center text-gray-400 text-sm py-10" role="status">{{ t('comun.cargando') }}</p>
    <div v-else-if="!evento" class="card text-center py-10 text-gray-500 text-sm">{{ t('eventos.noEncontrado') }}</div>

    <template v-else>
      <div class="flex items-start justify-between gap-3 flex-wrap">
        <div class="min-w-0">
          <h1 :class="['text-2xl font-bold', evento.cancelado ? 'text-gray-400 line-through' : 'text-gray-900']">{{ evento.titulo }}</h1>
          <p class="text-gray-500 text-sm mt-0.5">
            {{ fecha(evento.inicia_en) }}<template v-if="evento.casas_oracion?.nombre"> · {{ evento.casas_oracion.nombre }}</template><template v-else-if="evento.lugar"> · {{ evento.lugar }}</template>
          </p>
          <div class="flex gap-2 mt-2">
            <span class="text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-600">{{ t(`eventos.tipo.${evento.tipo}`) }}</span>
            <span v-if="evento.cancelado" class="text-xs px-2 py-0.5 rounded-full bg-red-50 text-red-600 font-medium">{{ t('eventos.cancelado') }}</span>
          </div>
          <p v-if="evento.descripcion" class="text-sm text-gray-600 mt-3 max-w-2xl whitespace-pre-line">{{ evento.descripcion }}</p>
        </div>
        <div v-if="puedeGestionar" class="flex gap-2 flex-wrap">
          <button @click="abrirEditar" class="btn-secondary text-sm inline-flex items-center gap-1"><Pencil class="w-4 h-4" aria-hidden="true" /> {{ t('eventos.editar') }}</button>
          <button @click="alternarCancelado" class="btn-secondary text-sm">{{ t(evento.cancelado ? 'eventos.reactivar' : 'eventos.cancelarEvento') }}</button>
          <button @click="eliminar" class="btn-secondary text-sm text-red-600 inline-flex items-center gap-1"><Trash2 class="w-4 h-4" aria-hidden="true" /> {{ t('eventos.eliminar') }}</button>
        </div>
      </div>

      <RegistroQr v-if="puedeGestionar" :evento-id="evento.id" :evento-titulo="evento.titulo" />

      <EscanerAsistencia v-if="puedeRegistrar && !evento.cancelado && auth.tieneModulo('credenciales')" :evento-id="evento.id" @registrado="cargar" />

      <div class="card space-y-4">
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><ClipboardCheck class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('eventos.asistencia') }}</h2>
          <p v-if="puedeVer" class="text-sm text-gray-500" role="status">{{ t('eventos.presentesDe', { presentes: totalPresentes, total: lista.length }) }}</p>
        </div>

        <p v-if="!puedeVer && !puedeRegistrar" class="text-sm text-gray-400">{{ t('eventos.sinPermisoAsistencia') }}</p>
        <template v-else>
          <div class="flex flex-col sm:flex-row gap-3">
            <div class="relative flex-1">
              <Search class="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2" aria-hidden="true" />
              <input v-model="busqueda" type="search" :placeholder="t('eventos.buscar')" :aria-label="t('eventos.buscar')" class="w-full pl-9 pr-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
            </div>
            <label v-if="evento.casa_oracion_id" class="inline-flex items-center gap-2 text-sm text-gray-600">
              <input v-model="soloCasa" type="checkbox" class="rounded border-gray-300 text-adn-verde" /> {{ t('eventos.soloCasa') }}
            </label>
            <button v-if="puedeNueva" @click="abrirNueva" class="btn-secondary text-sm inline-flex items-center gap-2"><UserPlus class="w-4 h-4" aria-hidden="true" /> {{ t('eventos.personaNueva') }}</button>
          </div>

          <p v-if="errorRegistro" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(errorRegistro) }}</p>
          <p v-if="!visibles.length" class="text-sm text-gray-400 py-6 text-center">{{ t('eventos.sinMiembros') }}</p>
          <ul v-else class="divide-y divide-gray-50 max-h-[28rem] overflow-y-auto">
            <li v-for="m in visibles" :key="m.id">
              <button type="button" role="checkbox" :aria-checked="presente(m.id)" :disabled="!puedeRegistrar || ocupado === m.id" @click="alternar(m)"
                class="w-full flex items-center gap-3 py-2.5 px-1 text-left hover:bg-gray-50 disabled:cursor-default focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde rounded">
                <span :class="['w-6 h-6 rounded-md border flex items-center justify-center flex-shrink-0', presente(m.id) ? 'bg-adn-verde border-adn-verde text-white' : 'border-gray-300 bg-white']">
                  <Check v-if="presente(m.id)" class="w-4 h-4" aria-hidden="true" />
                </span>
                <span class="text-sm text-gray-900">{{ m.nombre }} {{ m.apellido }}</span>
              </button>
            </li>
          </ul>
        </template>
      </div>
    </template>

    <!-- Modal: editar evento -->
    <div v-if="editando" class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50" @click.self="editando = false" role="dialog" aria-modal="true" :aria-label="t('eventos.editarTitulo')">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ t('eventos.editarTitulo') }}</h2>
        <form @submit.prevent="guardarEdicion" class="space-y-4">
          <CamposEvento v-model="edicion" :casas="casas" id-base="ed" />
          <label v-if="evento?.serie_id" class="flex items-start gap-2 rounded-xl bg-gray-50 p-3 text-sm text-gray-700">
            <input v-model="aplicarSerie" type="checkbox" class="mt-0.5 rounded border-gray-300 text-adn-verde" />
            <span>{{ t('eventos.aplicarSerie') }}<span class="block text-xs text-gray-400">{{ t('eventos.aplicarSerieAyuda') }}</span></span>
          </label>
          <p v-if="errorEdicion" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(errorEdicion) }}</p>
          <div class="flex justify-end gap-3">
            <button type="button" @click="editando = false" class="btn-secondary text-sm">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="guardandoEdicion" class="btn-primary text-sm disabled:opacity-60">{{ guardandoEdicion ? t('comun.guardando') : t('eventos.guardarCambios') }}</button>
          </div>
        </form>
      </div>
    </div>

    <!-- Modal: persona nueva -->
    <div v-if="abrirPersona" class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50" @click.self="abrirPersona = false" role="dialog" aria-modal="true" :aria-label="t('eventos.personaNueva')">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6">
        <h2 class="text-lg font-bold text-gray-900 mb-1">{{ t('eventos.personaNueva') }}</h2>
        <p class="text-sm text-gray-500 mb-4">{{ t('eventos.personaNuevaAyuda') }}</p>
        <form @submit.prevent="guardarPersona" class="space-y-4">
          <div :class="auth.modoAlias ? '' : 'grid grid-cols-2 gap-4'">
            <div>
              <label for="pn-nombre" class="block text-sm font-medium text-gray-700 mb-1">{{ auth.modoAlias ? t('miembros.alias') : t('miembros.nombre') }}</label>
              <input id="pn-nombre" v-model="persona.nombre" required maxlength="100" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
              <p v-if="auth.modoAlias" class="text-xs text-gray-500 mt-1">{{ t('miembros.aliasAyuda') }}</p>
            </div>
            <div v-if="!auth.modoAlias">
              <label for="pn-apellido" class="block text-sm font-medium text-gray-700 mb-1">{{ t('miembros.apellido') }}</label>
              <input id="pn-apellido" v-model="persona.apellido" required maxlength="100" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
            </div>
          </div>
          <div>
            <label for="pn-tel" class="block text-sm font-medium text-gray-700 mb-1">{{ t('miembros.telefono') }}</label>
            <input id="pn-tel" v-model="persona.telefono" type="tel" maxlength="30" placeholder="+34 600 000 000" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <label v-if="puedeConsolidar" class="flex items-start gap-2 text-sm text-gray-700">
            <input v-model="persona.op72" type="checkbox" class="mt-0.5 rounded border-gray-300 text-adn-verde" />
            <span>{{ t('eventos.iniciarOp72') }}<span class="block text-xs text-gray-400">{{ t('eventos.iniciarOp72Ayuda') }}</span></span>
          </label>
          <p v-if="errorPersona" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(errorPersona) }}</p>
          <div class="flex justify-end gap-3">
            <button type="button" @click="abrirPersona = false" class="btn-secondary text-sm">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="guardandoPersona" class="btn-primary text-sm disabled:opacity-60">{{ guardandoPersona ? t('comun.guardando') : t('eventos.guardarYMarcar') }}</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ArrowLeft, Check, ClipboardCheck, Pencil, Search, Trash2, UserPlus } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { esLimitePlan } from '@/lib/plan'
import { useAuthStore } from '@/stores/auth'
import { leerTodo } from '@/lib/paginar'
import { aInputLocal, errorFechas } from '@/lib/eventos'
import type { FormEvento } from '@/lib/eventos'
import CamposEvento from '@/components/CamposEvento.vue'
import RegistroQr from '@/components/RegistroQr.vue'
import EscanerAsistencia from '@/components/EscanerAsistencia.vue'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const auth = useAuthStore()

const puedeGestionar = computed(() => auth.can('eventos.gestionar'))
const puedeVer = computed(() => auth.can('asistencia.ver'))
const puedeRegistrar = computed(() => auth.can('asistencia.registrar', 'asistencia.registrar_propia'))
const puedeConsolidar = computed(() => auth.can('consolidacion.crear'))
// Una persona nueva se crea como miembro y se marca presente: hacen falta los dos permisos
const puedeNueva = computed(() => auth.can('miembros.crear') && auth.can('asistencia.registrar'))

const cargando = ref(true)
const evento = ref<any>(null)
const miembros = ref<any[]>([])
const asistencia = ref<Record<string, { id: string; presente: boolean }>>({})
const busqueda = ref('')
const soloCasa = ref(true)
const ocupado = ref('')
const errorRegistro = ref('')

const fecha = (iso: string) => new Date(iso).toLocaleString(locale.value, { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })
const presente = (miembroId: string) => asistencia.value[miembroId]?.presente === true

const lista = computed(() => miembros.value.filter(m => !(evento.value?.casa_oracion_id && soloCasa.value) || m.casa_oracion_id === evento.value.casa_oracion_id))
const visibles = computed(() => {
  const q = busqueda.value.trim().toLowerCase()
  return lista.value.filter(m => !q || `${m.nombre} ${m.apellido}`.toLowerCase().includes(q))
})
const totalPresentes = computed(() => lista.value.filter(m => presente(m.id)).length)

async function cargar() {
  const id = String(route.params.id)
  const { data: ev } = await supabase.from('eventos')
    .select('id, titulo, descripcion, tipo, inicia_en, termina_en, lugar, cancelado, casa_oracion_id, serie_id, casas_oracion!eventos_casa_fk(nombre)')
    .eq('id', id).maybeSingle()
  evento.value = ev
  if (ev) {
    const [ms, as] = await Promise.all([
      leerTodo<any>((d, h) => supabase.from('miembros').select('id, nombre, apellido, casa_oracion_id').eq('activo', true).order('nombre').order('id').range(d, h)),
      leerTodo<any>((d, h) => supabase.from('asistencia_evento').select('id, miembro_id, presente').eq('evento_id', id).order('id').range(d, h)),
    ])
    if (!ms || !as) errorRegistro.value = 'eventos.errorCargar'
    miembros.value = ms ?? []
    asistencia.value = Object.fromEntries((as ?? []).map(a => [a.miembro_id, { id: a.id, presente: a.presente }]))
  }
  cargando.value = false
}

// Marcar crea la fila; desmarcar la deja con presente en falso, que también pueden hacer los líderes de casa
async function alternar(m: any) {
  errorRegistro.value = ''
  ocupado.value = m.id
  const actual = asistencia.value[m.id]
  if (!actual) {
    const { data, error } = await supabase.from('asistencia_evento').insert({ evento_id: evento.value.id, miembro_id: m.id, presente: true }).select('id').single()
    if (error || !data) errorRegistro.value = 'eventos.errorRegistrar'
    else asistencia.value = { ...asistencia.value, [m.id]: { id: data.id, presente: true } }
  } else {
    const nuevo = !actual.presente
    const { data, error } = await supabase.from('asistencia_evento').update({ presente: nuevo }).eq('id', actual.id).select('id')
    if (error || !data?.length) errorRegistro.value = 'eventos.errorRegistrar'
    else asistencia.value = { ...asistencia.value, [m.id]: { id: actual.id, presente: nuevo } }
  }
  ocupado.value = ''
}

async function alternarCancelado() {
  const { error } = await supabase.from('eventos').update({ cancelado: !evento.value.cancelado }).eq('id', evento.value.id)
  if (!error) evento.value = { ...evento.value, cancelado: !evento.value.cancelado }
}

async function eliminar() {
  if (!window.confirm(t('eventos.confirmarEliminar'))) return
  const { error } = await supabase.from('eventos').delete().eq('id', evento.value.id)
  if (!error) router.push('/eventos')
}

// ---- Editar evento ----
const editando = ref(false)
const guardandoEdicion = ref(false)
const errorEdicion = ref('')
const aplicarSerie = ref(false)
const casas = ref<any[]>([])
const edicion = ref<FormEvento>({ titulo: '', tipo: 'culto', casa_id: '', inicio: '', fin: '', lugar: '', descripcion: '' })

async function abrirEditar() {
  const e = evento.value
  edicion.value = {
    titulo: e.titulo, tipo: e.tipo, casa_id: e.casa_oracion_id ?? '', inicio: aInputLocal(e.inicia_en), fin: aInputLocal(e.termina_en),
    lugar: e.lugar ?? '', descripcion: e.descripcion ?? '',
  }
  aplicarSerie.value = false
  errorEdicion.value = ''
  editando.value = true
  if (!casas.value.length) {
    const { data } = await supabase.from('casas_oracion').select('id, nombre, codigo_zona').eq('activa', true).order('nombre')
    casas.value = data ?? []
  }
}

async function guardarEdicion() {
  errorEdicion.value = ''
  const f = edicion.value
  const err = errorFechas(f.inicio, f.fin)
  if (err) { errorEdicion.value = err; return }
  guardandoEdicion.value = true
  const comunes = {
    titulo: f.titulo.trim(), tipo: f.tipo, lugar: f.lugar.trim() || null,
    descripcion: f.descripcion.trim() || null, casa_oracion_id: f.casa_id || null,
  }
  const iniciaAntes = evento.value.inicia_en
  const { data, error } = await supabase.from('eventos')
    .update({ ...comunes, inicia_en: new Date(f.inicio).toISOString(), termina_en: f.fin ? new Date(f.fin).toISOString() : null })
    .eq('id', evento.value.id).select('id')
  let fallo = !!error || !data?.length
  // En una serie, los cambios que no son de fecha pasan también a las reuniones siguientes
  if (!fallo && aplicarSerie.value && evento.value.serie_id) {
    const { error: errS } = await supabase.from('eventos').update(comunes).eq('serie_id', evento.value.serie_id).gt('inicia_en', iniciaAntes)
    fallo = !!errS
  }
  guardandoEdicion.value = false
  if (fallo) { errorEdicion.value = 'eventos.errorEditar'; return }
  editando.value = false
  await cargar()
}

// ---- Persona nueva ----
const abrirPersona = ref(false)
const guardandoPersona = ref(false)
const errorPersona = ref('')
const persona = ref({ nombre: '', apellido: '', telefono: '', op72: false })

function abrirNueva() {
  persona.value = { nombre: '', apellido: '', telefono: '', op72: puedeConsolidar.value }
  errorPersona.value = ''
  abrirPersona.value = true
}

async function guardarPersona() {
  errorPersona.value = ''
  guardandoPersona.value = true
  const p = persona.value
  const { data: m, error } = await supabase.from('miembros').insert({
    nombre: p.nombre.trim(), apellido: auth.modoAlias ? '' : p.apellido.trim(), telefono: p.telefono.trim() || null,
    casa_oracion_id: evento.value.casa_oracion_id ?? null, activo: true,
  }).select('id, nombre, apellido, casa_oracion_id').single()
  if (error || !m) { guardandoPersona.value = false; errorPersona.value = esLimitePlan(error) ? 'plan.limiteMiembros' : 'eventos.errorPersona'; return }
  miembros.value = [...miembros.value, m].sort((a, b) => a.nombre.localeCompare(b.nombre))
  const { data: a, error: errA } = await supabase.from('asistencia_evento').insert({ evento_id: evento.value.id, miembro_id: m.id, presente: true }).select('id').single()
  if (!errA && a) asistencia.value = { ...asistencia.value, [m.id]: { id: a.id, presente: true } }
  let fallo = !!errA
  if (p.op72 && puedeConsolidar.value) {
    const { error: errC } = await supabase.from('consolidaciones').insert({
      miembro_id: m.id, fecha_conversion: new Date().toISOString(), notas: t('eventos.notaOp72', { evento: evento.value.titulo }),
    })
    fallo = fallo || !!errC
  }
  guardandoPersona.value = false
  if (fallo) { errorPersona.value = 'eventos.errorParcial'; return }
  abrirPersona.value = false
}

onMounted(cargar)
</script>
