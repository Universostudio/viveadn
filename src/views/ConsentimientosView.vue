<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('consentimiento.pantalla.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('consentimiento.pantalla.subtitulo') }}</p>
      </div>
      <RouterLink to="/comunicacion" class="text-sm text-adn-verde hover:underline font-medium">{{ t('consentimiento.pantalla.volver') }}</RouterLink>
    </div>

    <p v-if="!puedeVer" class="text-sm text-gray-500">{{ t('comunicacion.errores.sinPermiso') }}</p>

    <template v-else>
      <p v-if="!puedeEditar" class="text-sm text-gray-500">{{ t('comunicacion.soloLectura') }}</p>

      <div class="card space-y-4">
        <label for="buscar" class="block text-sm font-medium text-gray-700">{{ t('consentimiento.pantalla.buscar') }}</label>
        <input id="buscar" v-model="busqueda" type="search" maxlength="100" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" @input="buscarSoon" />
        <p v-if="error" class="text-sm text-red-600" role="alert">{{ error }}</p>
        <p v-if="guardado" class="text-sm text-emerald-700" role="status">{{ t('consentimiento.pantalla.guardado') }}</p>
        <p v-if="!cargando && !miembros.length" class="text-sm text-gray-400 py-4 text-center">{{ t('consentimiento.pantalla.sinResultados') }}</p>

        <ul class="divide-y divide-gray-100">
          <li v-for="m in miembros" :key="m.id" class="py-3 space-y-2">
            <div class="flex items-start justify-between gap-3 flex-wrap">
              <div class="min-w-0">
                <p class="text-sm font-medium text-gray-900">{{ m.nombre }} {{ m.apellido }}</p>
                <p class="text-xs text-gray-500 truncate">{{ [m.email, m.telefono].filter(Boolean).join(' · ') }}</p>
              </div>
              <button v-if="puedeEditar" type="button" class="btn-secondary text-xs" @click="abrirFormulario(m.id)">{{ t('consentimiento.pantalla.registrar') }}</button>
            </div>
            <p class="text-xs text-gray-600 flex gap-3 flex-wrap">
              <span v-for="canal in CANALES" :key="canal">
                {{ t(`consentimiento.canal.${canal}`) }}:
                <span :class="['px-1.5 py-0.5 rounded-full', clase(estadoDe(m.id, canal))]">{{ t(`consentimiento.estado.${estadoDe(m.id, canal)}`) }}</span>
                <template v-if="fila(m.id, canal)"> · {{ t(`consentimiento.origen.${origenClave(fila(m.id, canal)!.origen)}`) }} · {{ formatoFecha(new Date(fila(m.id, canal)!.actualizado_en), { day: 'numeric', month: 'short', year: 'numeric' }) }}</template>
              </span>
            </p>
            <form v-if="abierto === m.id" class="grid grid-cols-1 sm:grid-cols-4 gap-2 items-end bg-gray-50 rounded-lg p-3" @submit.prevent="registrar(m.id)">
              <label class="text-xs text-gray-600">{{ t('consentimiento.pantalla.canal') }}
                <select v-model="form.canal" class="mt-1 w-full px-2 py-2 border border-gray-200 rounded-lg text-sm bg-white">
                  <option v-for="c in CANALES" :key="c" :value="c">{{ t(`consentimiento.canal.${c}`) }}</option>
                </select>
              </label>
              <label class="text-xs text-gray-600">{{ t('consentimiento.pantalla.estado') }}
                <select v-model="form.estado" class="mt-1 w-full px-2 py-2 border border-gray-200 rounded-lg text-sm bg-white">
                  <option v-for="e in ESTADOS" :key="e" :value="e">{{ t(`consentimiento.estado.${e}`) }}</option>
                </select>
              </label>
              <label class="text-xs text-gray-600">{{ t('consentimiento.pantalla.origen') }}
                <select v-model="form.origen" class="mt-1 w-full px-2 py-2 border border-gray-200 rounded-lg text-sm bg-white">
                  <option v-for="o in ORIGENES" :key="o" :value="o">{{ t(`consentimiento.origen.${o}`) }}</option>
                </select>
              </label>
              <div class="flex gap-2">
                <button type="submit" class="btn-primary text-xs" :disabled="guardando">{{ t('consentimiento.pantalla.guardar') }}</button>
                <button type="button" class="btn-secondary text-xs" @click="abierto = null">{{ t('comun.cancelar') }}</button>
              </div>
            </form>
          </li>
        </ul>
      </div>

      <!-- Auditoría: solo altas, nadie la modifica -->
      <div class="card">
        <h2 class="text-lg font-semibold text-gray-900 mb-1">{{ t('consentimiento.pantalla.auditoria') }}</h2>
        <p class="text-xs text-gray-500 mb-3">{{ t('consentimiento.pantalla.auditoriaAyuda') }}</p>
        <p v-if="!auditoria.length" class="text-sm text-gray-400 py-4 text-center">{{ t('consentimiento.pantalla.auditoriaVacia') }}</p>
        <ul v-else class="divide-y divide-gray-100 text-sm">
          <li v-for="a in auditoria" :key="a.id" class="py-2">
            <p class="text-gray-800">
              {{ nombres[a.miembro_id] ?? t('consentimiento.pantalla.miembroBorrado') }} ·
              {{ t(`consentimiento.canal.${a.canal}`) }}:
              {{ a.estado_anterior ? t(`consentimiento.estado.${a.estado_anterior}`) : t('consentimiento.pantalla.sinRegistro') }} →
              <span class="font-medium">{{ t(`consentimiento.estado.${a.estado_nuevo}`) }}</span>
            </p>
            <p class="text-xs text-gray-500">
              {{ formatoFecha(new Date(a.created_at), { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) }} ·
              {{ t(`consentimiento.origen.${origenClave(a.origen)}`) }} ·
              {{ a.usuario_id ? (quien[a.usuario_id] ?? t('consentimiento.pantalla.equipo')) : t('consentimiento.pantalla.sinUsuario') }}
            </p>
          </li>
        </ul>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { formatoFecha } from '@/i18n'

type Canal = 'email' | 'sms' | 'whatsapp'
type Estado = 'suscrito' | 'nunca' | 'cancelado' | 'sin_dato'
interface Miembro { id: string; nombre: string; apellido: string | null; email: string | null; telefono: string | null }
interface Fila { miembro_id: string; canal: Canal; estado: Estado; origen: string; actualizado_en: string }
interface Auditoria { id: number; miembro_id: string; canal: Canal; estado_anterior: Estado | null; estado_nuevo: Estado; origen: string; usuario_id: string | null; created_at: string }

const { t } = useI18n()
const auth = useAuthStore()
const CANALES: Canal[] = ['email', 'sms', 'whatsapp']
const ESTADOS: Estado[] = ['suscrito', 'sin_dato', 'nunca', 'cancelado']
// Desde dónde consta el consentimiento. Los demás orígenes (wix, baja, enlace) los pone el sistema.
const ORIGENES = ['manual', 'formulario', 'papel', 'verbal']
const CONOCIDOS = ['manual', 'formulario', 'papel', 'verbal', 'wix', 'baja', 'enlace']

const puedeVer = computed(() => auth.can('comunicacion.ver', 'comunicacion.enviar'))
const puedeEditar = computed(() => auth.can('comunicacion.enviar'))

const busqueda = ref('')
const miembros = ref<Miembro[]>([])
const filas = ref<Fila[]>([])
const auditoria = ref<Auditoria[]>([])
const nombres = ref<Record<string, string>>({})
const quien = ref<Record<string, string>>({})
const cargando = ref(true)
const error = ref('')
const guardado = ref(false)
const guardando = ref(false)
const abierto = ref<string | null>(null)
const form = ref<{ canal: Canal; estado: Estado; origen: string }>({ canal: 'email', estado: 'suscrito', origen: 'formulario' })

const fila = (id: string, canal: Canal) => filas.value.find(f => f.miembro_id === id && f.canal === canal)
const estadoDe = (id: string, canal: Canal): Estado => fila(id, canal)?.estado ?? 'sin_dato'
const origenClave = (o: string) => (CONOCIDOS.includes(o) ? o : 'otro')
const clase = (e: Estado) => e === 'suscrito' ? 'bg-emerald-100 text-emerald-800' : e === 'cancelado' ? 'bg-red-100 text-red-800' : 'bg-gray-100 text-gray-700'

let temporizador: ReturnType<typeof setTimeout> | undefined
function buscarSoon() { clearTimeout(temporizador); temporizador = setTimeout(cargarMiembros, 300) }

async function cargarMiembros() {
  cargando.value = true
  error.value = ''
  // Sin los caracteres que PostgREST usa para separar condiciones
  const q = busqueda.value.replace(/[,()%*]/g, ' ').trim()
  let consulta = supabase.from('miembros').select('id, nombre, apellido, email, telefono').order('nombre').limit(25)
  if (q) consulta = consulta.or(`nombre.ilike.%${q}%,apellido.ilike.%${q}%,email.ilike.%${q}%`)
  const { data, error: err } = await consulta
  if (err) { error.value = t('consentimiento.errorCarga'); cargando.value = false; return }
  miembros.value = (data ?? []) as Miembro[]
  if (miembros.value.length) {
    const { data: cs } = await supabase.from('adn_consentimientos').select('miembro_id, canal, estado, origen, actualizado_en').in('miembro_id', miembros.value.map(m => m.id))
    filas.value = (cs ?? []) as Fila[]
  } else filas.value = []
  cargando.value = false
}

async function cargarAuditoria() {
  const { data } = await supabase.from('adn_consentimiento_auditoria')
    .select('id, miembro_id, canal, estado_anterior, estado_nuevo, origen, usuario_id, created_at').order('id', { ascending: false }).limit(30)
  auditoria.value = (data ?? []) as Auditoria[]
  const ids = [...new Set(auditoria.value.map(a => a.miembro_id))]
  if (ids.length) {
    const { data: ms } = await supabase.from('miembros').select('id, nombre, apellido').in('id', ids)
    nombres.value = Object.fromEntries((ms ?? []).map(m => [m.id, `${m.nombre} ${m.apellido ?? ''}`.trim()]))
  }
  const us = [...new Set(auditoria.value.map(a => a.usuario_id).filter((x): x is string => !!x))]
  if (us.length) {
    const { data: ps } = await supabase.from('perfiles').select('id, nombre, apellido').in('id', us)
    quien.value = Object.fromEntries((ps ?? []).map(p => [p.id, `${p.nombre} ${p.apellido ?? ''}`.trim()]))
  }
}

function abrirFormulario(id: string) {
  abierto.value = abierto.value === id ? null : id
  guardado.value = false
}

async function registrar(id: string) {
  guardando.value = true
  error.value = ''
  guardado.value = false
  const { error: err } = await supabase.rpc('adn_registrar_consentimiento', {
    p_miembro: id, p_canal: form.value.canal, p_estado: form.value.estado, p_origen: form.value.origen,
  })
  guardando.value = false
  if (err) { error.value = /ADN_SIN_PERMISO/.test(err.message) ? t('comunicacion.errores.sinPermiso') : t('consentimiento.errorGuardar'); return }
  guardado.value = true
  abierto.value = null
  await Promise.all([cargarMiembros(), cargarAuditoria()])
}

onMounted(() => { if (puedeVer.value) { cargarMiembros(); cargarAuditoria() } })
</script>
