<template>
  <div class="space-y-6" data-test="config-seguimiento">
    <div class="card space-y-4">
      <div>
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><ListChecks class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('seguimiento.titulo') }}</h2>
        <p class="text-sm text-gray-500 mt-0.5">{{ t('seguimiento.ayuda') }}</p>
      </div>

      <p v-if="cargando" class="text-sm text-gray-400" role="status">{{ t('comun.cargando') }}</p>
      <p v-else-if="!disponible" class="text-sm text-gray-600 rounded-lg bg-gray-50 p-3" data-test="seg-no-disponible">{{ t('seguimiento.noDisponible') }}</p>
      <div v-else-if="errorCarga" class="flex flex-wrap items-center gap-3" role="alert" data-test="seg-error-carga">
        <p class="text-sm text-red-600">{{ t('seguimiento.errorCarga') }}</p>
        <button type="button" class="btn-secondary text-sm" data-test="seg-reintentar" @click="cargar">{{ t('seguimiento.reintentar') }}</button>
      </div>

      <template v-else>
        <p v-if="aviso" class="text-sm text-green-800 rounded-lg bg-green-50 p-3" role="status" data-test="seg-aviso">{{ aviso }}</p>
        <p v-if="error" class="text-sm text-red-700 rounded-lg bg-red-50 p-3" role="alert" data-test="seg-error">{{ error }}</p>

        <ul class="space-y-3">
          <li v-for="m in lista" :key="m.id" class="rounded-xl border p-3 space-y-3"
            :class="m.id === activoId ? 'border-adn-verde ring-1 ring-adn-verde/30' : 'border-gray-200'" :data-test="`metodo-${m.clave}`">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="font-semibold text-gray-900 flex flex-wrap items-center gap-2">
                  <span class="truncate">{{ m.nombre }}</span>
                  <span v-if="m.id === activoId" class="text-xs font-medium rounded-full bg-adn-verde text-white px-2 py-0.5" data-test="seg-activo">{{ t('seguimiento.enUso') }}</span>
                  <span class="text-xs font-medium rounded-full bg-gray-100 text-gray-600 px-2 py-0.5">{{ esPlantilla(m) ? t('seguimiento.plantilla') : t('seguimiento.propio') }}</span>
                  <span v-if="m.id === PLANTILLA_SIMPLE_ID" class="text-xs font-medium rounded-full bg-amber-100 text-amber-800 px-2 py-0.5" data-test="seg-por-validar">{{ t('seguimiento.porValidar') }}</span>
                </p>
                <p class="text-sm text-gray-600 mt-1">{{ t('seguimiento.resumen', { pasos: m.pasos, plazo: m.plazo_horas }) }}</p>
                <p class="text-xs text-gray-500">{{ t('seguimiento.tramos', tramos(m)) }}</p>
              </div>
              <div class="flex flex-wrap gap-2">
                <button v-if="m.id !== activoId" type="button" class="btn-primary text-sm" :disabled="ocupado" :data-test="`seg-usar-${m.clave}`" @click="activar(m)">{{ t('seguimiento.usar') }}</button>
                <button v-if="esPlantilla(m) && conModulo && propios.length < MAX_METODOS_PROPIOS" type="button" class="btn-secondary text-sm" :disabled="ocupado" :data-test="`seg-copiar-${m.clave}`" @click="copiar(m)">{{ t('seguimiento.copiar') }}</button>
                <button v-if="esPropio(m) && conModulo" type="button" class="btn-secondary text-sm" :data-test="`seg-editar-${m.clave}`" @click="abrir(m)">{{ editando?.id === m.id ? t('seguimiento.cerrar') : t('seguimiento.editar') }}</button>
              </div>
            </div>

            <!-- Edición de un método propio -->
            <form v-if="editando?.id === m.id" class="space-y-3 border-t border-gray-100 pt-3" novalidate data-test="seg-editor" @submit.prevent="guardar">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div class="sm:col-span-2">
                  <label for="seg-nombre" class="block text-sm font-medium text-gray-700 mb-1">{{ t('seguimiento.campos.nombre') }}</label>
                  <input id="seg-nombre" v-model="borrador.nombre" type="text" :maxlength="MAX_NOMBRE" :aria-invalid="!!errores.nombre" aria-describedby="seg-nombre-e"
                    class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" data-test="seg-f-nombre" />
                  <p v-if="errores.nombre" id="seg-nombre-e" class="text-xs text-red-600 mt-1" data-test="seg-e-nombre">{{ t(errores.nombre) }}</p>
                </div>
                <div>
                  <label for="seg-pasos" class="block text-sm font-medium text-gray-700 mb-1">{{ t('seguimiento.campos.pasos') }}</label>
                  <select id="seg-pasos" v-model.number="borrador.pasos" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-adn-verde" data-test="seg-f-pasos">
                    <option :value="1">1</option><option :value="2">2</option><option :value="3">3</option>
                  </select>
                  <p v-if="errores.pasos" class="text-xs text-red-600 mt-1" data-test="seg-e-pasos">{{ t(errores.pasos) }}</p>
                  <p class="text-xs text-gray-500 mt-1">{{ t('seguimiento.campos.pasosAyuda') }}</p>
                </div>
                <div>
                  <label for="seg-plazo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('seguimiento.campos.plazo') }}</label>
                  <input id="seg-plazo" v-model="borrador.plazo_horas" type="number" inputmode="numeric" min="1" :max="MAX_PLAZO_HORAS" :aria-invalid="!!errores.plazo"
                    class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" data-test="seg-f-plazo" />
                  <p v-if="errores.plazo" class="text-xs text-red-600 mt-1" data-test="seg-e-plazo">{{ t(errores.plazo) }}</p>
                  <p class="text-xs text-gray-500 mt-1">{{ t('seguimiento.campos.plazoAyuda') }}</p>
                </div>
                <div>
                  <label for="seg-amarillo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('seguimiento.campos.amarillo') }}</label>
                  <input id="seg-amarillo" v-model="borrador.umbral_amarillo_horas" type="number" inputmode="numeric" min="1" :aria-invalid="!!errores.amarillo"
                    class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" data-test="seg-f-amarillo" />
                  <p v-if="errores.amarillo" class="text-xs text-red-600 mt-1" data-test="seg-e-amarillo">{{ t(errores.amarillo) }}</p>
                </div>
                <div>
                  <label for="seg-naranja" class="block text-sm font-medium text-gray-700 mb-1">{{ t('seguimiento.campos.naranja') }}</label>
                  <input id="seg-naranja" v-model="borrador.umbral_naranja_horas" type="number" inputmode="numeric" min="1" :aria-invalid="!!errores.naranja"
                    class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" data-test="seg-f-naranja" />
                  <p v-if="errores.naranja" class="text-xs text-red-600 mt-1" data-test="seg-e-naranja">{{ t(errores.naranja) }}</p>
                </div>
                <div class="sm:col-span-2">
                  <label for="seg-primer" class="block text-sm font-medium text-gray-700 mb-1">{{ t('seguimiento.campos.primer') }}</label>
                  <input id="seg-primer" v-model="borrador.primer_contacto_horas" type="number" inputmode="numeric" min="1" :aria-invalid="!!errores.primer"
                    class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde sm:max-w-xs" data-test="seg-f-primer" />
                  <p v-if="errores.primer" class="text-xs text-red-600 mt-1" data-test="seg-e-primer">{{ t(errores.primer) }}</p>
                  <p class="text-xs text-gray-500 mt-1">{{ t('seguimiento.campos.primerAyuda') }}</p>
                </div>
              </div>

              <p v-if="uso" class="text-xs text-gray-600" data-test="seg-uso">{{ t('seguimiento.uso', { total: uso.total, abiertos: uso.abiertos }) }}</p>
              <p v-if="uso && uso.abiertos > 0 && cambiaPlazo" class="text-sm text-amber-800 rounded-lg bg-amber-50 p-3" role="status" data-test="seg-aviso-procesos">{{ t('seguimiento.avisoProcesos', { n: uso.abiertos }) }}</p>

              <div class="flex flex-wrap items-center gap-2">
                <button type="submit" class="btn-primary text-sm" :disabled="ocupado || !cambios" data-test="seg-guardar">{{ ocupado ? t('seguimiento.guardando') : t('seguimiento.guardar') }}</button>
                <button v-if="plantillaDeOrigen" type="button" class="btn-secondary text-sm" :disabled="ocupado" data-test="seg-restaurar" @click="restaurar">{{ t('seguimiento.restaurar', { nombre: plantillaDeOrigen.nombre }) }}</button>
                <button v-if="m.id !== activoId" type="button" class="btn-secondary text-sm text-red-700" :disabled="ocupado" data-test="seg-archivar" @click="confirmandoArchivo = true">{{ t('seguimiento.archivar') }}</button>
              </div>
              <p v-if="m.id === activoId" class="text-xs text-gray-500">{{ t('seguimiento.activoNoArchiva') }}</p>

              <div v-if="confirmandoArchivo" role="alertdialog" aria-labelledby="seg-arch-t" class="rounded-lg border border-amber-300 bg-amber-50 p-3 space-y-2" data-test="seg-confirmar-archivo">
                <p id="seg-arch-t" class="text-sm text-amber-900">{{ t('seguimiento.archivarConfirma', { nombre: m.nombre }) }}</p>
                <div class="flex gap-2">
                  <button type="button" class="btn-primary text-sm" :disabled="ocupado" data-test="seg-archivar-si" @click="archivar(m)">{{ t('seguimiento.archivarSi') }}</button>
                  <button type="button" class="btn-secondary text-sm" data-test="seg-archivar-no" @click="confirmandoArchivo = false">{{ t('seguimiento.archivarNo') }}</button>
                </div>
              </div>
            </form>
          </li>
        </ul>

        <p v-if="!conModulo" class="text-sm text-gray-600 rounded-lg bg-gray-50 p-3" data-test="seg-solo-premium">{{ t('seguimiento.soloPremium') }}</p>
        <p v-else-if="propios.length >= MAX_METODOS_PROPIOS" class="text-sm text-gray-600" data-test="seg-maximo">{{ t('seguimiento.maximo', { n: MAX_METODOS_PROPIOS }) }}</p>
      </template>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { ListChecks } from '@lucide/vue'
import { useI18n } from 'vue-i18n'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useSeguimientoStore } from '@/stores/seguimiento'
import {
  PLANTILLA_OP72_ID, PLANTILLA_SIMPLE_ID, MAX_METODOS_PROPIOS, MAX_PLAZO_HORAS, MAX_NOMBRE,
  esPlantilla, esPropio, ordenarMetodos, tramos, validarMetodo, borradorDe, valoresDe, hayCambios, cambiaElPlazo, restaurarDesde, copiaDe, errorDeBase,
  type MetodoFila, type BorradorMetodo,
} from '@/lib/metodoSeguimiento'

const { t } = useI18n()
const auth = useAuthStore()
const seg = useSeguimientoStore()

const cargando = ref(true)
const errorCarga = ref(false)
const disponible = computed(() => seg.disponible === true)
const metodos = ref<MetodoFila[]>([])
const activoId = ref<string>(PLANTILLA_OP72_ID)
const hayConfig = ref(false)
const ocupado = ref(false)
const aviso = ref('')
const error = ref('')

// Crear y editar un método propio exige el módulo del plan (Premium); elegir entre las plantillas, no
const conModulo = computed(() => auth.tieneModulo('seguimiento_propio'))
const lista = computed(() => ordenarMetodos(metodos.value))
const propios = computed(() => metodos.value.filter(m => esPropio(m) && !m.archivado_en))

const editando = ref<MetodoFila | null>(null)
const borrador = ref<BorradorMetodo>({ nombre: '', pasos: 3, plazo_horas: 72, umbral_amarillo_horas: 24, umbral_naranja_horas: 48, primer_contacto_horas: null })
const uso = ref<{ total: number; abiertos: number } | null>(null)
const confirmandoArchivo = ref(false)

const errores = computed(() => validarMetodo(borrador.value))
const cambios = computed(() => !!editando.value && hayCambios(editando.value, borrador.value))
const cambiaPlazo = computed(() => !!editando.value && Object.keys(errores.value).length === 0 && cambiaElPlazo(editando.value, borrador.value))
const plantillaDeOrigen = computed(() => {
  const o = editando.value?.plantilla_origen
  return o ? metodos.value.find(m => m.id === o && !m.archivado_en) ?? null : null
})

function limpiarMensajes() { aviso.value = ''; error.value = '' }

async function cargar() {
  cargando.value = true; errorCarga.value = false
  const ok = await seg.asegurar()
  if (!ok) { cargando.value = false; return }
  const [m, c] = await Promise.all([
    supabase.from('adn_seguimiento_metodos').select('*'),
    supabase.from('adn_seguimiento_config').select('metodo_id').maybeSingle(),
  ])
  if (m.error || c.error) { errorCarga.value = true; cargando.value = false; return }
  metodos.value = (m.data ?? []) as MetodoFila[]
  hayConfig.value = !!c.data
  activoId.value = c.data?.metodo_id ?? PLANTILLA_OP72_ID
  // Si el método que se editaba ya no existe o se archivó, se cierra el editor
  if (editando.value) {
    const vigente = metodos.value.find(x => x.id === editando.value!.id && !x.archivado_en)
    if (vigente) editando.value = vigente; else cerrar()
  }
  cargando.value = false
}

async function activar(m: MetodoFila) {
  limpiarMensajes(); ocupado.value = true
  const iglesiaId = auth.iglesiaId
  const { error: e } = hayConfig.value
    ? await supabase.from('adn_seguimiento_config').update({ metodo_id: m.id }).eq('iglesia_id', iglesiaId)
    : await supabase.from('adn_seguimiento_config').insert({ iglesia_id: iglesiaId, metodo_id: m.id })
  ocupado.value = false
  if (e) { error.value = t(errorDeBase(e)); return }
  await cargar()
  aviso.value = t('seguimiento.avisos.elegido', { nombre: m.nombre })
}

async function copiar(origen: MetodoFila) {
  limpiarMensajes(); ocupado.value = true
  const fila = copiaDe(origen, metodos.value.map(m => m.clave))
  const { data, error: e } = await supabase.from('adn_seguimiento_metodos').insert({ ...fila, iglesia_id: auth.iglesiaId }).select('*').single()
  ocupado.value = false
  if (e || !data) { error.value = t(errorDeBase(e)); return }
  await cargar()
  const nuevo = metodos.value.find(m => m.id === data.id)
  if (nuevo) await abrir(nuevo)
  aviso.value = t('seguimiento.avisos.creado')
}

async function abrir(m: MetodoFila) {
  if (editando.value?.id === m.id) { cerrar(); return }
  limpiarMensajes()
  editando.value = m; borrador.value = borradorDe(m); confirmandoArchivo.value = false; uso.value = null
  const { data } = await supabase.rpc('adn_seguimiento_en_uso', { p_metodo: m.id })
  if (editando.value?.id === m.id && data && typeof data === 'object') uso.value = data as { total: number; abiertos: number }
}

function cerrar() { editando.value = null; uso.value = null; confirmandoArchivo.value = false }

function restaurar() {
  if (!plantillaDeOrigen.value) return
  limpiarMensajes()
  borrador.value = restaurarDesde(plantillaDeOrigen.value, borrador.value)
  aviso.value = t('seguimiento.avisos.restaurado')
}

async function guardar() {
  const m = editando.value
  if (!m || ocupado.value) return
  limpiarMensajes()
  if (Object.keys(errores.value).length) { error.value = t('seguimiento.errores.revisa'); return }
  if (!cambios.value) return
  ocupado.value = true
  const { error: e } = await supabase.from('adn_seguimiento_metodos').update(valoresDe(borrador.value)).eq('id', m.id)
  ocupado.value = false
  if (e) { error.value = t(errorDeBase(e)); return }
  await cargar()
  aviso.value = t('seguimiento.avisos.guardado')
  if (editando.value) borrador.value = borradorDe(editando.value)
}

async function archivar(m: MetodoFila) {
  limpiarMensajes(); ocupado.value = true
  const { error: e } = await supabase.from('adn_seguimiento_metodos').update({ archivado_en: new Date().toISOString() }).eq('id', m.id)
  ocupado.value = false
  confirmandoArchivo.value = false
  if (e) { error.value = t(errorDeBase(e)); return }
  cerrar()
  await cargar()
  aviso.value = t('seguimiento.avisos.archivado')
}

onMounted(cargar)
</script>
