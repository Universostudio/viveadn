<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('miPanel.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('miPanel.saludo', { nombre: auth.perfil?.nombre ?? '' }) }}</p>
      </div>
      <div v-if="casas.length > 1">
        <label for="mp-casa" class="block text-xs font-medium text-gray-600 mb-1">{{ t('miPanel.casa') }}</label>
        <select id="mp-casa" v-model="casaId" data-test="casa-selector" class="text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde">
          <option v-for="c in casas" :key="c.id" :value="c.id">{{ c.nombre }}</option>
        </select>
      </div>
    </div>

    <p v-if="aviso" role="status" data-test="aviso" :class="['text-sm px-4 py-3 rounded-lg border', aviso.error ? 'bg-red-50 text-red-700 border-red-200' : 'bg-green-50 text-green-700 border-green-200']">{{ aviso.texto }}</p>

    <div v-if="cargando" class="py-12 text-center text-gray-500 text-sm">{{ t('comun.cargando') }}</div>

    <div v-else-if="!casa" class="card text-sm text-gray-600" data-test="sin-casa">
      <p class="font-medium text-gray-900">{{ t('miPanel.sinCasa') }}</p>
      <p class="mt-1">{{ t('miPanel.sinCasaAyuda') }}</p>
    </div>

    <template v-else>
      <section class="card" aria-labelledby="mp-mi-casa" data-test="mi-casa">
        <h2 id="mp-mi-casa" class="text-base font-semibold text-gray-900">{{ casa.nombre }} <span class="ml-1 text-xs font-mono text-adn-verde">{{ casa.codigo_zona }}</span></h2>
        <p class="text-sm text-gray-600 mt-1">{{ [casa.direccion, casa.ciudad].filter(Boolean).join(', ') }}</p>
        <p class="text-sm text-gray-700 mt-2" data-test="n-personas">{{ t('miPanel.personasN', { n: personas.length }, personas.length) }}</p>
      </section>

      <section v-if="puedePasarLista" class="card space-y-3" aria-labelledby="mp-lista" data-test="pasar-lista">
        <div class="flex items-end justify-between gap-3 flex-wrap">
          <h2 id="mp-lista" class="text-base font-semibold text-gray-900">{{ t('miPanel.pasarLista') }}</h2>
          <div>
            <label for="mp-fecha" class="block text-xs font-medium text-gray-600 mb-1">{{ t('miPanel.fechaReunion') }}</label>
            <input id="mp-fecha" v-model="fecha" type="date" :max="hoy" data-test="lista-fecha" class="text-sm border border-gray-200 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" @change="cargarLista" />
          </div>
        </div>
        <p v-if="!personas.length" class="text-sm text-gray-500">{{ t('miPanel.sinPersonas') }}</p>
        <form v-else @submit.prevent="guardarLista">
          <fieldset>
            <legend class="sr-only">{{ t('miPanel.quienVino') }}</legend>
            <ul class="divide-y divide-gray-50">
              <li v-for="p in personas" :key="p.id" class="py-1">
                <label class="flex items-center gap-3 py-2 text-sm cursor-pointer">
                  <input type="checkbox" class="w-5 h-5 rounded" :checked="marcados.has(p.id)" :data-persona="p.id" @change="alternar(p.id)" />
                  <span class="text-gray-900">{{ p.nombre }} {{ p.apellido }}</span>
                </label>
              </li>
            </ul>
          </fieldset>
          <div class="flex items-center gap-3 mt-3">
            <button type="submit" :disabled="guardando || !fecha" class="btn-primary text-sm disabled:opacity-60" data-test="guardar-lista">{{ t('miPanel.guardarLista') }}</button>
            <span class="text-xs text-gray-500" data-test="presentes">{{ t('miPanel.presentesN', { n: marcados.size, total: personas.length }) }}</span>
          </div>
        </form>
        <div v-if="resumen.length" class="pt-3 border-t border-gray-100" data-test="resumen-semanas">
          <h3 class="text-sm font-semibold text-gray-800 mb-2">{{ t('miPanel.ultimasReuniones') }}</h3>
          <ul class="text-sm text-gray-700 space-y-1">
            <li v-for="r in resumen" :key="r.fecha">{{ formatoFecha(r.fecha + 'T12:00:00') }}: {{ t('miPanel.presentesN', { n: r.presentes, total: r.total }) }}</li>
          </ul>
        </div>
      </section>

      <section class="card" aria-labelledby="mp-gente" data-test="mi-gente">
        <h2 id="mp-gente" class="text-base font-semibold text-gray-900 mb-3">{{ t('miPanel.miGente') }}</h2>
        <p v-if="!personas.length" class="text-sm text-gray-500">{{ t('miPanel.sinPersonas') }}</p>
        <ul v-else class="divide-y divide-gray-50">
          <li v-for="p in personas" :key="p.id" class="py-2 flex flex-wrap items-center gap-2 text-sm" :data-gente="p.id">
            <span class="flex-1 min-w-[8rem] text-gray-900">{{ p.nombre }} {{ p.apellido }}</span>
            <a v-if="enlaceLlamar(p.telefono)" :href="enlaceLlamar(p.telefono)!" data-test="llamar" :aria-label="t('consolidacion.llamarA', { nombre: `${p.nombre} ${p.apellido}` })" class="inline-flex items-center gap-1 text-xs px-3 py-2 rounded-lg border border-gray-200 text-adn-verde focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde"><Phone class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.llamar') }}</a>
            <a v-if="enlaceWhatsApp(p.telefono, auth.iglesia?.pais)" :href="enlaceWhatsApp(p.telefono, auth.iglesia?.pais)!" target="_blank" rel="noopener noreferrer" data-test="whatsapp" :aria-label="t('consolidacion.whatsappA', { nombre: `${p.nombre} ${p.apellido}` })" class="inline-flex items-center gap-1 text-xs px-3 py-2 rounded-lg border border-gray-200 text-adn-verde focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde"><MessageCircle class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('consolidacion.whatsapp') }}</a>
            <span v-if="!p.telefono" class="text-xs text-gray-500">{{ t('consolidacion.sinTelefono') }}</span>
          </li>
        </ul>
      </section>

      <section v-if="auth.can('consolidacion.ver_casa')" class="card" aria-labelledby="mp-nuevos" data-test="nuevos">
        <h2 id="mp-nuevos" class="text-base font-semibold text-gray-900 mb-3">{{ t('miPanel.nuevos') }}</h2>
        <p v-if="!nuevos.length" class="text-sm text-gray-500">{{ t('miPanel.sinNuevos') }}</p>
        <ul v-else class="divide-y divide-gray-50">
          <li v-for="n in nuevos" :key="n.id" class="py-2 flex flex-wrap items-center gap-2 text-sm" data-test="nuevo">
            <span class="flex-1 min-w-[8rem] text-gray-900">{{ n.miembros?.nombre }} {{ n.miembros?.apellido }}</span>
            <EstadoAlerta :estado="n.estado_alerta" />
            <span class="text-xs text-gray-600">{{ t('consolidacion.contactos.titulo') }}: {{ contactosDe(n).length }}/3</span>
            <a v-if="enlaceLlamar(n.miembros?.telefono)" :href="enlaceLlamar(n.miembros?.telefono)!" class="text-xs px-3 py-2 rounded-lg border border-gray-200 text-adn-verde" :aria-label="t('consolidacion.llamarA', { nombre: `${n.miembros?.nombre} ${n.miembros?.apellido}` })">{{ t('consolidacion.llamar') }}</a>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { MessageCircle, Phone } from '@lucide/vue'
import { useI18n } from 'vue-i18n'
import { supabase } from '@/lib/supabase'
import { formatoFecha } from '@/i18n'
import { useAuthStore } from '@/stores/auth'
import EstadoAlerta from '@/components/EstadoAlerta.vue'
import { conAlerta } from '@/lib/alertas'
import { useSeguimientoStore } from '@/stores/seguimiento'
import { contactosDe, enlaceLlamar, enlaceWhatsApp } from '@/lib/seguimiento'
import { hoyLocal, planDeAsistencia, resumenPorFecha } from '@/lib/asistencia'

const { t } = useI18n()
const auth = useAuthStore()
const seg = useSeguimientoStore()
const puedePasarLista = computed(() => auth.can('asistencia.registrar_propia', 'asistencia.registrar'))

const cargando = ref(true)
const casas = ref<any[]>([])
const casaId = ref('')
const personas = ref<any[]>([])
const nuevos = ref<any[]>([])
const hoy = hoyLocal()
const fecha = ref(hoy)
const existentes = ref<{ id: string; miembro_id: string; presente: boolean | null }[]>([])
const marcados = ref<Set<string>>(new Set())
const resumen = ref<{ fecha: string; presentes: number; total: number }[]>([])
const guardando = ref(false)
const aviso = ref<{ texto: string; error: boolean } | null>(null)
const avisar = (texto: string, error = false) => { aviso.value = { texto, error } }
const casa = computed(() => casas.value.find(c => c.id === casaId.value) ?? null)

function alternar(id: string) {
  const s = new Set(marcados.value)
  if (s.has(id)) s.delete(id); else s.add(id)
  marcados.value = s
}

async function cargarCasas() {
  cargando.value = true
  const { data } = await supabase.from('casas_oracion').select('id, nombre, codigo_zona, direccion, ciudad').eq('activa', true).order('nombre')
  casas.value = data ?? []
  casaId.value = casas.value[0]?.id ?? ''
  if (!casaId.value) cargando.value = false
}

async function cargarCasa() {
  if (!casaId.value) return
  cargando.value = true
  await seg.asegurar()
  const desde = new Date(Date.now() - 28 * 86_400_000).toISOString().slice(0, 10)
  const [p, n, r] = await Promise.all([
    supabase.from('miembros').select('id, nombre, apellido, telefono').eq('casa_oracion_id', casaId.value).eq('activo', true).order('nombre'),
    auth.can('consolidacion.ver_casa')
      ? supabase.from('consolidaciones').select('*, miembros!consolidaciones_miembro_fk(nombre, apellido, telefono)' + seg.embeber()).eq('casa_oracion_id', casaId.value).eq('completado', false)
      : Promise.resolve({ data: [] as any[] }),
    puedePasarLista.value ? supabase.from('asistencias').select('fecha, presente').eq('casa_oracion_id', casaId.value).gte('fecha', desde) : Promise.resolve({ data: [] as any[] }),
  ])
  personas.value = p.data ?? []
  nuevos.value = (n.data ?? []).map(conAlerta)
  resumen.value = resumenPorFecha(r.data ?? [])
  await cargarLista()
  cargando.value = false
}

async function cargarLista() {
  if (!casaId.value || !puedePasarLista.value) return
  const { data } = await supabase.from('asistencias').select('id, miembro_id, presente').eq('casa_oracion_id', casaId.value).eq('fecha', fecha.value)
  existentes.value = data ?? []
  marcados.value = new Set(existentes.value.filter(e => e.presente).map(e => e.miembro_id))
}

async function guardarLista() {
  if (!casa.value || !fecha.value) return
  const plan = planDeAsistencia(casa.value.id, fecha.value, personas.value.map(p => p.id), existentes.value, marcados.value)
  guardando.value = true
  let fallo = false
  if (plan.insertar.length) {
    const { error } = await supabase.from('asistencias').insert(plan.insertar)
    if (error) fallo = true
  }
  for (const u of plan.actualizar) {
    const { error } = await supabase.from('asistencias').update({ presente: u.presente }).eq('id', u.id)
    if (error) fallo = true
  }
  guardando.value = false
  if (fallo) { avisar(t('miPanel.errorLista'), true); await cargarLista(); return }
  avisar(t('miPanel.listaGuardada'))
  await cargarCasa()
}

watch(casaId, () => { void cargarCasa() })
onMounted(async () => { await cargarCasas(); if (casaId.value) await cargarCasa() })
</script>
