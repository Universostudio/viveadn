<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div>
        <RouterLink to="/formacion" class="text-sm text-adn-verde hover:underline inline-flex items-center gap-1"><ArrowLeft class="w-4 h-4" aria-hidden="true" /> {{ t('formacion.programas.volver') }}</RouterLink>
        <h1 class="text-2xl font-bold text-gray-900 mt-1">{{ t('formacion.programas.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('formacion.programas.subtitulo') }}</p>
      </div>
      <button v-if="puedeProgramas" @click="abrirNuevo" class="btn-primary flex items-center gap-2"><Plus class="w-4 h-4" aria-hidden="true" /> {{ t('formacion.programas.nuevo') }}</button>
    </div>

    <p v-if="error" class="text-sm text-red-600" role="alert">{{ t(error) }}</p>
    <p v-if="cargando" class="text-sm text-gray-500" role="status">{{ t('comun.cargando') }}</p>

    <div v-else-if="programas.length === 0" class="card text-center py-12 text-gray-400">
      <GraduationCap class="w-10 h-10 mx-auto mb-2 text-gray-300" aria-hidden="true" />
      <p>{{ t('formacion.programas.vacio') }}</p>
    </div>

    <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Lista de programas -->
      <div class="space-y-3">
        <button v-for="p in programas" :key="p.id" @click="seleccionado = p.id"
          :class="['card w-full text-left transition-all', seleccionado === p.id ? 'ring-2 ring-adn-verde' : 'hover:shadow-md']">
          <div class="flex items-start justify-between gap-2">
            <p class="font-semibold text-gray-900">{{ p.nombre }}</p>
            <span v-if="!p.activo" class="text-xs bg-gray-100 text-gray-500 px-2 py-0.5 rounded-full">{{ t('formacion.programas.inactivo') }}</span>
          </div>
          <p class="text-xs text-gray-500 mt-1">{{ t('formacion.programas.lecciones', p.programa_lecciones.length) }} · {{ t('formacion.programas.inscritos', inscripcionesDe(p.id).length) }} · {{ t('formacion.programas.completados', inscripcionesDe(p.id).filter(i => i.estado === 'completado').length) }}</p>
        </button>
      </div>

      <!-- Detalle -->
      <div v-if="actual" class="lg:col-span-2 space-y-6">
        <div class="card space-y-4">
          <div class="flex items-start justify-between gap-3 flex-wrap">
            <div class="min-w-0">
              <h2 class="text-lg font-semibold text-gray-900">{{ actual.nombre }}</h2>
              <p v-if="actual.descripcion" class="text-sm text-gray-600 mt-1">{{ actual.descripcion }}</p>
            </div>
            <div v-if="puedeProgramas" class="flex items-center gap-3 text-sm">
              <button @click="abrirEditar" class="text-adn-verde hover:underline">{{ t('formacion.programas.editarBoton') }}</button>
              <button @click="alternarActivo" class="text-gray-500 hover:underline">{{ actual.activo ? t('formacion.programas.desactivar') : t('formacion.programas.activar') }}</button>
              <button @click="borrarPrograma" class="text-red-600 hover:underline">{{ t('formacion.programas.eliminarBoton') }}</button>
            </div>
          </div>

          <div>
            <h3 class="text-sm font-semibold text-gray-700 mb-2">{{ t('formacion.programas.leccionesTitulo') }}</h3>
            <p v-if="leccionesOrdenadas.length === 0" class="text-sm text-gray-500">{{ t('formacion.programas.sinLecciones') }}</p>
            <ol class="space-y-1.5">
              <li v-for="(l, i) in leccionesOrdenadas" :key="l.id" class="flex items-center gap-2 text-sm bg-gray-50 rounded-lg px-3 py-2">
                <span class="w-6 text-gray-400 text-right">{{ i + 1 }}</span>
                <span class="flex-1 min-w-0 truncate text-gray-800">{{ l.titulo }}</span>
                <template v-if="puedeProgramas">
                  <button @click="mover(i, -1)" :disabled="i === 0" :aria-label="t('formacion.programas.subir')" class="text-gray-400 hover:text-gray-700 disabled:opacity-30"><ChevronUp class="w-4 h-4" aria-hidden="true" /></button>
                  <button @click="mover(i, 1)" :disabled="i === leccionesOrdenadas.length - 1" :aria-label="t('formacion.programas.bajar')" class="text-gray-400 hover:text-gray-700 disabled:opacity-30"><ChevronDown class="w-4 h-4" aria-hidden="true" /></button>
                  <button @click="quitarLeccion(l)" :aria-label="t('formacion.programas.eliminarBoton')" class="text-gray-400 hover:text-red-600"><Trash2 class="w-4 h-4" aria-hidden="true" /></button>
                </template>
              </li>
            </ol>
            <form v-if="puedeProgramas" @submit.prevent="añadirLeccion" class="flex gap-2 mt-3">
              <input v-model="tituloLeccion" required maxlength="150" :placeholder="t('formacion.programas.nuevaLeccion')" :aria-label="t('formacion.programas.nuevaLeccion')"
                class="flex-1 px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
              <button type="submit" class="btn-secondary text-sm">{{ t('formacion.programas.añadir') }}</button>
            </form>
          </div>
        </div>

        <div class="card space-y-4">
          <div class="flex items-center justify-between gap-3 flex-wrap">
            <h3 class="text-lg font-semibold text-gray-900">{{ t('formacion.programas.alumnos') }}</h3>
            <form v-if="puedeActualizar && actual.activo" @submit.prevent="inscribir" class="flex gap-2">
              <select v-model="miembroNuevo" required :aria-label="t('formacion.programas.inscribirA')" class="text-sm border border-gray-200 rounded-lg px-2 py-1.5 bg-white max-w-[14rem]">
                <option value="" disabled>{{ t('formacion.programas.inscribirA') }}</option>
                <option v-for="m in miembrosLibres" :key="m.id" :value="m.id">{{ `${m.nombre} ${m.apellido}`.trim() }}</option>
              </select>
              <button type="submit" class="btn-secondary text-sm flex items-center gap-1"><UserPlus class="w-4 h-4" aria-hidden="true" /> {{ t('formacion.programas.inscribir') }}</button>
            </form>
          </div>
          <p v-if="inscripcionesActuales.length === 0" class="text-sm text-gray-500">{{ t('formacion.programas.sinAlumnos') }}</p>
          <ul class="space-y-3">
            <li v-for="i in inscripcionesActuales" :key="i.id" class="border border-gray-100 rounded-xl p-3">
              <div class="flex items-center justify-between gap-3 flex-wrap">
                <p class="font-medium text-gray-900">{{ `${i.miembros?.nombre ?? ''} ${i.miembros?.apellido ?? ''}`.trim() }}</p>
                <div class="flex items-center gap-3">
                  <span :class="['text-xs px-2 py-0.5 rounded-full font-medium', claseEstado(i.estado)]">{{ t('formacion.programas.estado.' + i.estado) }}</span>
                  <button v-if="puedeActualizar && i.estado !== 'completado'" @click="cambiarAbandono(i)" class="text-xs text-gray-500 hover:underline">
                    {{ i.estado === 'abandonado' ? t('formacion.programas.retomar') : t('formacion.programas.abandonar') }}
                  </button>
                  <!-- Un certificado ya emitido sigue siendo valido aunque la inscripcion se reabra: se puede ver y revocar siempre -->
                  <button v-if="certDe(i)" @click="verCertificado(i)" class="text-xs text-adn-verde hover:underline">{{ t('formacion.programas.certificado.ver') }}</button>
                  <button v-else-if="i.estado === 'completado' && puedeCertificar" @click="emitirCertificado(i)" class="text-xs text-adn-verde font-medium hover:underline">{{ t('formacion.programas.certificado.emitir') }}</button>
                  <button v-if="certDe(i) && puedeCertificar" @click="alternarRevocado(certDe(i))" class="text-xs text-gray-500 hover:underline">
                    {{ certDe(i).revocado_en ? t('formacion.programas.certificado.restaurar') : t('formacion.programas.certificado.revocar') }}
                  </button>
                  <button v-if="puedeActualizar" @click="desinscribir(i)" class="text-xs text-red-600 hover:underline">{{ t('formacion.programas.quitar') }}</button>
                </div>
              </div>
              <div class="h-1.5 bg-gray-100 rounded-full overflow-hidden mt-2">
                <div class="h-full bg-adn-verde rounded-full transition-all" :style="{ width: porcentaje(i) + '%' }"></div>
              </div>
              <p class="text-xs text-gray-500 mt-1">{{ i.avance_formacion.length }} / {{ leccionesOrdenadas.length }}</p>
              <div class="flex flex-wrap gap-1.5 mt-2">
                <button v-for="(l, k) in leccionesOrdenadas" :key="l.id" @click="alternarAvance(i, l)" :disabled="!puedeActualizar"
                  :title="l.titulo" :aria-pressed="hecha(i, l.id)"
                  :class="['text-xs px-2 py-1 rounded-lg border transition-colors', hecha(i, l.id) ? 'bg-adn-verde text-white border-adn-verde' : 'bg-white text-gray-600 border-gray-200 hover:border-adn-verde']">
                  <Check v-if="hecha(i, l.id)" class="w-3 h-3 inline -mt-0.5" aria-hidden="true" /> {{ k + 1 }}
                </button>
              </div>
            </li>
          </ul>
        </div>
      </div>
    </div>

    <!-- Certificado imprimible, con el QR que lleva a la verificacion publica -->
    <div v-if="certificadoAbierto" class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50 overflow-y-auto" @click.self="certificadoAbierto = null" role="dialog" aria-modal="true" :aria-label="t('formacion.programas.certificado.titulo')">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-2xl p-6 my-6">
        <div class="certificado-imprimible border-4 border-double border-adn-verde rounded-xl p-8 text-center bg-white">
          <p v-if="certificadoAbierto.cert.revocado_en" class="text-sm font-bold text-red-600 uppercase tracking-wide mb-3">{{ t('formacion.programas.certificado.revocadoAviso') }}</p>
          <p class="text-sm uppercase tracking-widest text-gray-500">{{ auth.nombreIglesia }}</p>
          <h2 class="text-3xl font-bold text-adn-verde mt-2">{{ t('formacion.programas.certificado.titulo') }}</h2>
          <p class="text-sm text-gray-500 mt-6">{{ t('formacion.programas.certificado.otorgado') }}</p>
          <p class="text-2xl font-bold text-gray-900 mt-1">{{ `${certificadoAbierto.insc.miembros?.nombre ?? ''} ${certificadoAbierto.insc.miembros?.apellido ?? ''}`.trim() }}</p>
          <p class="text-sm text-gray-500 mt-4">{{ t('formacion.programas.certificado.porCompletar') }}</p>
          <p class="text-xl font-semibold text-gray-900 mt-1">{{ certificadoAbierto.cert.programa_nombre }}</p>
          <p class="text-sm text-gray-500 mt-4">{{ t('formacion.programas.certificado.emitidoEl', { fecha: formatoFecha(certificadoAbierto.cert.emitido_en, { dateStyle: 'long' }) }) }}</p>
          <div class="mt-6 flex flex-col items-center gap-1">
            <img v-if="qrImagen" :src="qrImagen" :alt="t('formacion.programas.certificado.qrAlt')" width="120" height="120" />
            <p class="text-xs text-gray-500 break-all">{{ t('formacion.programas.certificado.verificaEn') }}<br /><span class="font-mono">{{ enlaceVerificacion(certificadoAbierto.cert) }}</span></p>
          </div>
        </div>
        <div class="flex gap-3 mt-4">
          <button @click="certificadoAbierto = null" class="btn-secondary flex-1">{{ t('formacion.programas.certificado.cerrar') }}</button>
          <button @click="imprimir" class="btn-primary flex-1">{{ t('formacion.programas.certificado.imprimir') }}</button>
        </div>
      </div>
    </div>

    <!-- Crear o editar programa -->
    <div v-if="modal" class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50" @click.self="modal = null" role="dialog" aria-modal="true">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ modal === 'nuevo' ? t('formacion.programas.nuevo') : t('formacion.programas.editar') }}</h2>
        <form @submit.prevent="guardarPrograma" class="space-y-4">
          <div>
            <label for="pf-nombre" class="block text-sm font-medium text-gray-700 mb-1">{{ t('formacion.programas.nombre') }}</label>
            <input id="pf-nombre" v-model="form.nombre" required maxlength="120" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <div>
            <label for="pf-desc" class="block text-sm font-medium text-gray-700 mb-1">{{ t('formacion.programas.descripcion') }}</label>
            <textarea id="pf-desc" v-model="form.descripcion" rows="3" maxlength="1000" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde"></textarea>
          </div>
          <div class="flex gap-3">
            <button type="button" @click="modal = null" class="btn-secondary flex-1">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="guardando" class="btn-primary flex-1 disabled:opacity-60">{{ guardando ? t('comun.guardando') : t('formacion.programas.guardar') }}</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { ArrowLeft, Check, ChevronDown, ChevronUp, GraduationCap, Plus, Trash2, UserPlus } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { leerTodo } from '@/lib/paginar'
import { useAuthStore } from '@/stores/auth'
import { formatoFecha } from '@/i18n'
import QRCode from 'qrcode'

const { t } = useI18n()
const auth = useAuthStore()
const puedeProgramas = computed(() => auth.can('formacion.programas'))
const puedeActualizar = computed(() => auth.can('formacion.actualizar'))
const puedeCertificar = computed(() => auth.can('formacion.certificar'))

const cargando = ref(true)
const error = ref('')
const programas = ref<any[]>([])
const inscripciones = ref<any[]>([])
const certificados = ref<any[]>([])
const certificadoAbierto = ref<{ cert: any; insc: any } | null>(null)
const qrImagen = ref('')
const miembros = ref<any[]>([])
const seleccionado = ref<string | null>(null)
const modal = ref<null | 'nuevo' | 'editar'>(null)
const guardando = ref(false)
const form = ref({ nombre: '', descripcion: '' })
const tituloLeccion = ref('')
const miembroNuevo = ref('')

const actual = computed(() => programas.value.find(p => p.id === seleccionado.value) ?? null)
const leccionesOrdenadas = computed(() => [...(actual.value?.programa_lecciones ?? [])].sort((a: any, b: any) => a.orden - b.orden))
const inscripcionesDe = (programaId: string) => inscripciones.value.filter(i => i.programa_id === programaId)
const inscripcionesActuales = computed(() => (actual.value ? inscripcionesDe(actual.value.id) : []))
const miembrosLibres = computed(() => {
  const ya = new Set(inscripcionesActuales.value.map(i => i.miembro_id))
  return miembros.value.filter(m => !ya.has(m.id))
})
const hecha = (i: any, leccionId: string) => i.avance_formacion.some((a: any) => a.leccion_id === leccionId)
const porcentaje = (i: any) => (leccionesOrdenadas.value.length ? Math.round((i.avance_formacion.length / leccionesOrdenadas.value.length) * 100) : 0)
const claseEstado = (e: string) => (e === 'completado' ? 'bg-green-100 text-green-700' : e === 'abandonado' ? 'bg-gray-100 text-gray-500' : 'bg-amber-100 text-amber-700')

async function cargar() {
  error.value = ''
  // La API devuelve como mucho 1000 filas por peticion: inscripciones y miembros se leen por paginas, con orden estable
  const [pRes, ins, m, certs] = await Promise.all([
    supabase.from('programas_formacion').select('id, nombre, descripcion, activo, orden, programa_lecciones(id, orden, titulo, descripcion)').order('orden').order('nombre'),
    leerTodo<any>((d, h) => supabase.from('inscripciones_formacion').select('id, programa_id, miembro_id, estado, completado_en, miembros(nombre, apellido), avance_formacion(leccion_id)').order('inscrito_en').order('id').range(d, h)),
    leerTodo<any>((d, h) => supabase.from('miembros').select('id, nombre, apellido').eq('activo', true).order('nombre').order('id').range(d, h)),
    leerTodo<any>((d, h) => supabase.from('certificados').select('id, inscripcion_id, codigo, programa_nombre, emitido_en, revocado_en').order('emitido_en').order('id').range(d, h)),
  ])
  if (pRes.error || !ins || !m || !certs) { error.value = 'formacion.programas.errorCargar'; cargando.value = false; return }
  programas.value = pRes.data ?? []
  inscripciones.value = ins
  certificados.value = certs
  miembros.value = m
  if (!seleccionado.value || !programas.value.some(p => p.id === seleccionado.value)) seleccionado.value = programas.value[0]?.id ?? null
  cargando.value = false
}

// Ejecuta una operacion y recarga; si falla, avisa sin dejar la pantalla a medias
async function hacer(op: PromiseLike<{ error: unknown }>) {
  error.value = ''
  const { error: e } = await op
  if (e) { error.value = 'formacion.programas.errorGuardar'; return false }
  await cargar()
  return true
}

function abrirNuevo() { form.value = { nombre: '', descripcion: '' }; modal.value = 'nuevo' }
function abrirEditar() { form.value = { nombre: actual.value.nombre, descripcion: actual.value.descripcion ?? '' }; modal.value = 'editar' }

async function guardarPrograma() {
  guardando.value = true
  const datos = { nombre: form.value.nombre.trim(), descripcion: form.value.descripcion.trim() || null }
  if (modal.value === 'nuevo') {
    const { data, error: e } = await supabase.from('programas_formacion').insert({ ...datos, orden: programas.value.length }).select('id').single()
    guardando.value = false
    if (e || !data) { error.value = 'formacion.programas.errorGuardar'; return }
    modal.value = null
    seleccionado.value = data.id
    await cargar()
    return
  }
  const ok = await hacer(supabase.from('programas_formacion').update(datos).eq('id', actual.value.id))
  guardando.value = false
  if (ok) modal.value = null
}

const alternarActivo = () => hacer(supabase.from('programas_formacion').update({ activo: !actual.value.activo }).eq('id', actual.value.id))
async function borrarPrograma() {
  const programa = actual.value
  if (!programa || !window.confirm(t('formacion.programas.confirmarBorrar', { nombre: programa.nombre }))) return
  await hacer(supabase.from('programas_formacion').delete().eq('id', programa.id))
}

async function añadirLeccion() {
  const titulo = tituloLeccion.value.trim()
  if (!titulo) return
  const siguiente = leccionesOrdenadas.value.length ? leccionesOrdenadas.value[leccionesOrdenadas.value.length - 1].orden + 1 : 1
  if (await hacer(supabase.from('programa_lecciones').insert({ programa_id: actual.value.id, titulo, orden: siguiente }))) tituloLeccion.value = ''
}
const quitarLeccion = (l: any) => hacer(supabase.from('programa_lecciones').delete().eq('id', l.id))
async function mover(i: number, delta: number) {
  const a = leccionesOrdenadas.value[i]
  const b = leccionesOrdenadas.value[i + delta]
  if (!a || !b) return
  // Se intercambian los numeros de orden de las dos lecciones
  const r1 = await supabase.from('programa_lecciones').update({ orden: b.orden }).eq('id', a.id)
  const r2 = await supabase.from('programa_lecciones').update({ orden: a.orden }).eq('id', b.id)
  if (r1.error || r2.error) error.value = 'formacion.programas.errorGuardar'
  await cargar()
}

async function inscribir() {
  if (!miembroNuevo.value) return
  if (await hacer(supabase.from('inscripciones_formacion').insert({ programa_id: actual.value.id, miembro_id: miembroNuevo.value }))) miembroNuevo.value = ''
}
const desinscribir = (i: any) => window.confirm(t('formacion.programas.confirmarQuitar')) ? hacer(supabase.from('inscripciones_formacion').delete().eq('id', i.id)) : undefined
const cambiarAbandono = (i: any) => hacer(supabase.from('inscripciones_formacion').update({ estado: i.estado === 'abandonado' ? 'en_curso' : 'abandonado' }).eq('id', i.id))
const alternarAvance = (i: any, l: any) => hecha(i, l.id)
  ? hacer(supabase.from('avance_formacion').delete().eq('inscripcion_id', i.id).eq('leccion_id', l.id))
  : hacer(supabase.from('avance_formacion').insert({ programa_id: i.programa_id, inscripcion_id: i.id, leccion_id: l.id }))

// ---- Certificados ----
const certDe = (i: any) => certificados.value.find(c => c.inscripcion_id === i.id)
const enlaceVerificacion = (c: any) => `${window.location.origin}/verificar/${c.codigo}`

async function verCertificado(i: any) {
  const cert = certDe(i)
  if (!cert) return
  qrImagen.value = await QRCode.toDataURL(enlaceVerificacion(cert), { width: 360, margin: 1, errorCorrectionLevel: 'M' })
  certificadoAbierto.value = { cert, insc: i }
}
async function emitirCertificado(i: any) {
  error.value = ''
  const { error: e } = await supabase.rpc('emitir_certificado', { p_inscripcion: i.id })
  if (e) { error.value = 'formacion.programas.certificado.errorEmitir'; return }
  await cargar()
  await verCertificado(i)
}
async function alternarRevocado(c: any) {
  const revocar = !c.revocado_en
  if (revocar && !window.confirm(t('formacion.programas.certificado.confirmarRevocar'))) return
  error.value = ''
  const { error: e } = await supabase.rpc('revocar_certificado', { p_id: c.id, p_revocar: revocar })
  if (e) { error.value = 'formacion.programas.errorGuardar'; return }
  await cargar()
}
const imprimir = () => window.print()

onMounted(cargar)
</script>

<style>
/* Al imprimir solo sale el certificado */
@media print {
  body * { visibility: hidden; }
  .certificado-imprimible, .certificado-imprimible * { visibility: visible; }
  .certificado-imprimible { position: fixed; left: 0; top: 0; width: 100%; border-width: 6px; }
}
</style>
