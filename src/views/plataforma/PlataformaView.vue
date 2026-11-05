<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">{{ t('plataforma.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-0.5">{{ t('plataforma.subtitulo') }}</p>
      </div>
      <button @click="abrirNueva = true" class="btn-primary inline-flex items-center gap-2"><Plus class="w-4 h-4" aria-hidden="true" /> {{ t('plataforma.nueva') }}</button>
    </div>

    <p v-if="mensaje()" :class="['text-sm px-4 py-3 rounded-lg border', mensajeError ? 'bg-red-50 text-red-700 border-red-200' : 'bg-green-50 text-green-700 border-green-200']">
      {{ mensaje() }}
    </p>

    <!-- Resumen global de todas las iglesias -->
    <section v-if="!cargando && iglesias.length" :aria-label="t('plataforma.resumen.titulo')" class="space-y-3">
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div v-for="k in resumen.tarjetas" :key="k.clave" class="card-stat">
          <div>
            <p class="text-2xl font-bold text-gray-900">{{ k.valor }}</p>
            <p class="text-xs text-gray-500">{{ t(`plataforma.resumen.${k.clave}`) }}</p>
          </div>
        </div>
      </div>
      <div v-if="resumen.porPlan.length" class="card">
        <p class="text-xs font-medium text-gray-600 mb-2">{{ t('plataforma.resumen.porPlan') }}</p>
        <ul class="space-y-2">
          <li v-for="p in resumen.porPlan" :key="p.clave" class="flex items-center gap-3 text-sm">
            <span class="w-28 truncate text-gray-700">{{ p.nombre }}</span>
            <span class="flex-1 h-2 rounded-full bg-gray-100 overflow-hidden"><span class="block h-full bg-adn-verde" :style="{ width: p.porcentaje + '%' }"></span></span>
            <span class="w-24 text-right text-xs text-gray-500">{{ t('plataforma.resumen.iglesiasMiembros', { i: p.iglesias, m: p.miembros }) }}</span>
          </li>
        </ul>
      </div>
    </section>

    <!-- Registro de iglesias: apertura, codigos de acceso a la beta -->
    <section v-if="!cargando" class="card space-y-4" :aria-label="t('plataforma.registro.titulo')">
      <div>
        <h2 class="text-lg font-semibold text-gray-900">{{ t('plataforma.registro.titulo') }}</h2>
        <p class="text-sm text-gray-500 mt-0.5">{{ t('plataforma.registro.ayuda') }}</p>
      </div>
      <div class="flex flex-wrap gap-x-6 gap-y-2">
        <label class="inline-flex items-center gap-2 text-sm text-gray-700"><input type="checkbox" :checked="registro.abierto" @change="guardarAjustesRegistro(($event.target as HTMLInputElement).checked, registro.requiere_codigo)" /> {{ t('plataforma.registro.abierto') }}</label>
        <label class="inline-flex items-center gap-2 text-sm text-gray-700"><input type="checkbox" :checked="registro.requiere_codigo" @change="guardarAjustesRegistro(registro.abierto, ($event.target as HTMLInputElement).checked)" /> {{ t('plataforma.registro.requiereCodigo') }}</label>
      </div>
      <p v-if="registro.abierto" class="text-xs text-gray-400">{{ t('plataforma.registro.enlace') }} <span class="font-mono">{{ origen }}/registro</span></p>

      <div v-if="codigoCreado" role="status" class="rounded-lg border border-green-200 bg-green-50 p-3 text-sm">
        <p class="text-green-800 font-medium">{{ t('plataforma.registro.codigoCreado') }}</p>
        <p class="mt-1 flex flex-wrap items-center gap-3"><span class="font-mono text-base text-green-900 select-all">{{ codigoCreado }}</span>
          <button type="button" @click="copiarCodigo" class="btn-secondary text-xs">{{ codigoCopiado ? t('dar.copiado') : t('dar.copiar') }}</button></p>
        <p class="text-xs text-green-700 mt-1">{{ t('plataforma.registro.codigoUnaVez') }}</p>
      </div>

      <form @submit.prevent="crearCodigo" class="flex flex-wrap items-end gap-3">
        <div><label for="cd-eti" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.registro.etiqueta') }}</label>
          <input id="cd-eti" v-model="nuevoCodigo.etiqueta" required maxlength="80" class="text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" /></div>
        <div><label for="cd-usos" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.registro.usos') }}</label>
          <input id="cd-usos" v-model.number="nuevoCodigo.usos_max" type="number" min="1" max="1000" required class="w-24 text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" /></div>
        <div><label for="cd-dias" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.registro.dias') }}</label>
          <input id="cd-dias" v-model.number="nuevoCodigo.dias" type="number" min="0" max="365" required class="w-24 text-sm border border-gray-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" /></div>
        <button type="submit" class="btn-primary text-sm">{{ t('plataforma.registro.crear') }}</button>
      </form>

      <div v-if="registro.codigos.length" class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="text-left text-xs text-gray-500 border-b border-gray-100"><tr>
            <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataforma.registro.etiqueta') }}</th>
            <th scope="col" class="py-2 pr-3 font-medium text-right">{{ t('plataforma.registro.usados') }}</th>
            <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataforma.registro.vence') }}</th>
            <th scope="col" class="py-2 font-medium text-right">{{ t('plataforma.registro.estado') }}</th></tr></thead>
          <tbody class="divide-y divide-gray-50">
            <tr v-for="c in registro.codigos" :key="c.id">
              <td class="py-2 pr-3 text-gray-900">{{ c.etiqueta }}</td>
              <td class="py-2 pr-3 text-right">{{ c.usos }} / {{ c.usos_max }}</td>
              <td class="py-2 pr-3 text-gray-500">{{ c.vence_en ? new Date(c.vence_en).toLocaleDateString(locale) : t('plataforma.registro.sinVencimiento') }}</td>
              <td class="py-2 text-right"><button type="button" @click="estadoCodigo(c)" :class="['text-xs px-3 py-1 rounded-full border', c.activo ? 'border-green-200 text-green-700 bg-green-50' : 'border-gray-200 text-gray-500']">{{ c.activo ? t('comun.activo') : t('comun.inactivo') }}</button></td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else class="text-sm text-gray-400">{{ t('plataforma.registro.sinCodigos') }}</p>
    </section>

    <div v-if="cargando" class="py-12 text-center text-gray-400 text-sm">{{ t('plataforma.cargando') }}</div>

    <div v-else class="space-y-4">
      <div v-for="ig in iglesias" :key="ig.id" class="card space-y-4">
        <div class="flex items-start justify-between gap-3 flex-wrap">
          <div class="min-w-0">
            <div class="flex items-center gap-2 flex-wrap">
              <h2 class="text-lg font-semibold text-gray-900 truncate">{{ ig.nombre }}</h2>
              <span v-if="ig.es_demo" class="text-xs bg-adn-arena text-adn-profundo px-2 py-0.5 rounded-full font-medium">{{ t('plataforma.demo') }}</span>
              <span :class="['text-xs px-2 py-0.5 rounded-full font-medium', ig.activa ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700']">
                {{ t('plataforma.etapa.' + (ig.etapa ?? (ig.activa ? 'activa' : 'suspendida'))) }}
              </span>
              <span v-if="ig.etapa === 'prueba' && ig.prueba_hasta" class="text-xs text-gray-400">
                {{ t('plataforma.pruebaHasta', { fecha: new Date(ig.prueba_hasta).toLocaleDateString() }) }}
              </span>
            </div>
            <p class="text-xs text-gray-400 mt-0.5">
              {{ ig.slug }} · {{ t('plataforma.miembros', ig.miembros ?? 0) }} · {{ t('plataforma.usuarios', ig.usuarios ?? 0) }}
              <span v-if="limiteMiembros(ig)"> · {{ t('plataforma.limite', limiteMiembros(ig)) }}</span>
            </p>
          </div>

          <div class="flex items-center gap-2">
            <label class="text-xs text-gray-500">{{ t('plataforma.plan') }}</label>
            <select :value="ig.plan" @change="cambiarPlan(ig, ($event.target as HTMLSelectElement).value)"
              class="text-sm border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option v-for="p in planes" :key="p.clave" :value="p.clave">{{ p.nombre }}</option>
            </select>
          </div>
        </div>

        <div class="flex flex-wrap items-end gap-3">
          <div>
            <label :for="`madre-${ig.id}`" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.red.madre') }}</label>
            <select :id="`madre-${ig.id}`" :value="ig.iglesia_madre_id ?? ''" :disabled="tieneSedes(ig)"
              @change="vincular(ig, ($event.target as HTMLSelectElement).value || null, ig.red_acceso)"
              class="text-sm border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-adn-verde disabled:bg-gray-50 disabled:text-gray-400">
              <option value="">{{ t('plataforma.red.independiente') }}</option>
              <option v-for="m in posiblesMadres(ig)" :key="m.id" :value="m.id">{{ m.nombre }}</option>
            </select>
          </div>
          <div v-if="ig.iglesia_madre_id">
            <label :for="`acceso-${ig.id}`" class="block text-xs font-medium text-gray-600 mb-1">{{ t('plataforma.red.acceso') }}</label>
            <select :id="`acceso-${ig.id}`" :value="ig.red_acceso" @change="vincular(ig, ig.iglesia_madre_id, ($event.target as HTMLSelectElement).value)"
              class="text-sm border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option value="resumen">{{ t('plataforma.red.resumen') }}</option>
              <option value="ninguno">{{ t('plataforma.red.ninguno') }}</option>
            </select>
          </div>
          <p v-if="tieneSedes(ig)" class="text-xs text-gray-400 pb-2">{{ t('plataforma.red.conSedes', { n: numeroSedes(ig) }) }}</p>
        </div>

        <div>
          <p class="text-xs font-medium text-gray-600 mb-2">{{ t('plataforma.complementos') }}</p>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="m in modulosOpcionales(ig)" :key="m.clave"
              @click="alternarModulo(ig, m)"
              :disabled="m.delPlan"
              :title="m.delPlan ? t('plataforma.incluidoEnPlan') : ''"
              :class="['text-xs px-3 py-1.5 rounded-full border transition-colors',
                m.delPlan ? 'bg-gray-50 text-gray-400 border-gray-100 cursor-default'
                : m.activo ? 'bg-adn-verde text-white border-adn-verde'
                : 'bg-white text-gray-600 border-gray-200 hover:border-adn-verde']"
            >
              <span class="inline-flex items-center gap-1.5">
                <component :is="m.delPlan ? Check : m.activo ? CircleCheck : Circle" class="w-3.5 h-3.5" aria-hidden="true" />{{ m.nombre }}
              </span>
            </button>
          </div>
        </div>

        <div class="flex justify-end">
          <select :value="ig.etapa" @change="cambiarEtapa(ig, ($event.target as HTMLSelectElement))"
            class="text-xs text-gray-500 border border-gray-200 rounded-lg px-2 py-1 bg-white">
            <option v-for="e in ETAPAS" :key="e" :value="e">{{ t('plataforma.etapa.' + e) }}</option>
          </select>
        </div>
      </div>
    </div>

    <!-- Modal: nueva iglesia -->
    <div v-if="abrirNueva" class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50" @click.self="abrirNueva = false">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 max-h-[90vh] overflow-y-auto">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ t('plataforma.nueva') }}</h2>
        <form @submit.prevent="crearIglesia" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.nombre') }}</label>
            <input v-model="nueva.nombre" required minlength="2" maxlength="80" class="campo" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.direccionInterna') }}</label>
            <input v-model="nueva.slug" required pattern="[a-z0-9]+(-[a-z0-9]+)*" minlength="3" maxlength="40" placeholder="casa-reino" class="campo" />
            <p class="text-xs text-gray-400 mt-1">{{ t('plataforma.slugAyuda') }}</p>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.pais') }}</label>
              <input v-model="nueva.pais" required maxlength="80" class="campo" />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.ciudad') }}</label>
              <input v-model="nueva.ciudad" required maxlength="80" class="campo" />
            </div>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataforma.plan') }}</label>
            <select v-model="nueva.plan" class="campo">
              <option v-for="p in planes" :key="p.clave" :value="p.clave">{{ p.nombre }}</option>
            </select>
          </div>
          <div class="border-t border-gray-100 pt-4 space-y-3">
            <p class="text-sm font-medium text-gray-700">{{ t('plataforma.propietario') }}</p>
            <div class="grid grid-cols-2 gap-3">
              <input v-model="nueva.nombre_propietario" required :placeholder="t('plataforma.nombrePlaceholder')" class="campo" />
              <input v-model="nueva.apellido_propietario" required :placeholder="t('plataforma.apellidoPlaceholder')" class="campo" />
            </div>
            <input v-model="nueva.email" type="email" required :placeholder="t('plataforma.ejemploEmail')" class="campo" />
          </div>
          <label class="flex items-center gap-2 text-sm text-gray-600">
            <input v-model="nueva.es_demo" type="checkbox" class="rounded" /> {{ t('plataforma.esDemo') }}
          </label>
          <p v-if="errorNueva" class="text-sm text-red-600">{{ errorNueva }}</p>
          <div class="flex gap-3 pt-2">
            <button type="button" @click="abrirNueva = false" class="btn-secondary flex-1">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="creando" class="btn-primary flex-1 disabled:opacity-60">
              {{ creando ? t('comun.creando') : t('plataforma.crear') }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Check, Circle, CircleCheck, Plus } from '@lucide/vue'
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useI18n } from 'vue-i18n'

const { t, locale } = useI18n()

const iglesias = ref<any[]>([])
const planes = ref<any[]>([])
const modulos = ref<any[]>([])
const planModulos = ref<any[]>([])
const cargando = ref(true)
// Aviso como función para que se traduzca de nuevo si cambia el idioma
const mensaje = ref<() => string>(() => '')
const mensajeError = ref(false)
const abrirNueva = ref(false)
const creando = ref(false)
const errorNueva = ref('')

const vacia = () => ({
  nombre: '', slug: '', pais: '', ciudad: '', plan: 'semilla',
  nombre_propietario: '', apellido_propietario: '', email: '', es_demo: false,
})
const nueva = ref(vacia())

// Resumen global: sale de la misma lista que ya devuelve la funcion de la plataforma
const resumen = computed(() => {
  const todas = iglesias.value
  const reales = todas.filter((i: any) => !i.es_demo)
  const activas = reales.filter((i: any) => i.activa)
  const suma = (l: any[], campo: string) => l.reduce((n, i) => n + (Number(i[campo]) || 0), 0)
  const miembrosTotales = suma(reales, 'miembros')
  const porPlan = planes.value.map((p: any) => {
    const delPlan = activas.filter((i: any) => i.plan === p.clave)
    return { clave: p.clave, nombre: p.nombre, iglesias: delPlan.length, miembros: suma(delPlan, 'miembros') }
  }).filter((p: any) => p.iglesias > 0)
  const maximo = Math.max(1, ...porPlan.map((p: any) => p.iglesias))
  return {
    tarjetas: [
      { clave: 'activas', valor: activas.length },
      { clave: 'suspendidas', valor: reales.length - activas.length },
      { clave: 'demos', valor: todas.length - reales.length },
      { clave: 'miembros', valor: miembrosTotales.toLocaleString(locale.value) },
    ],
    porPlan: porPlan.map((p: any) => ({ ...p, porcentaje: Math.round((p.iglesias / maximo) * 100) })),
  }
})

// Red de iglesias: una madre con sedes (un solo nivel). La base rechaza cualquier cadena mas larga.
const numeroSedes = (ig: any) => iglesias.value.filter((x: any) => x.iglesia_madre_id === ig.id).length
const tieneSedes = (ig: any) => numeroSedes(ig) > 0
const posiblesMadres = (ig: any) => iglesias.value.filter((x: any) => x.id !== ig.id && !x.iglesia_madre_id)
const vincular = (ig: any, madre: string | null, acceso: string) =>
  ejecutar({ accion: 'vincular_red', iglesia_id: ig.id, madre_id: madre, red_acceso: acceso }, () => t('plataforma.red.guardada', { iglesia: ig.nombre }))

// Registro de iglesias: ajustes y codigos de acceso a la beta
const origen = window.location.origin
const registro = ref<{ abierto: boolean; requiere_codigo: boolean; codigos: any[] }>({ abierto: false, requiere_codigo: true, codigos: [] })
const nuevoCodigo = ref({ etiqueta: '', usos_max: 1, dias: 30 })
const codigoCreado = ref('')
const codigoCopiado = ref(false)

async function guardarAjustesRegistro(abierto: boolean, requiereCodigo: boolean) {
  await ejecutar({ accion: 'registro_ajustes', abierto, requiere_codigo: requiereCodigo }, () => t('plataforma.registro.guardado'))
}
async function crearCodigo() {
  try {
    const d = await llamar({ accion: 'codigo_crear', ...nuevoCodigo.value })
    codigoCreado.value = d.codigo
    nuevoCodigo.value = { etiqueta: '', usos_max: 1, dias: 30 }
    await cargar()
  } catch (e: any) { const texto = e.message; avisar(() => texto, true) }
}
const estadoCodigo = (c: any) => ejecutar({ accion: 'codigo_estado', id: c.id, activo: !c.activo }, () => t('plataforma.registro.guardado'))
async function copiarCodigo() {
  try { await navigator.clipboard.writeText(codigoCreado.value); codigoCopiado.value = true; setTimeout(() => { codigoCopiado.value = false }, 2000) } catch { /* se puede copiar a mano */ }
}

async function llamar(cuerpo: Record<string, unknown>) {
  const { data, error } = await supabase.functions.invoke('plataforma', {
    body: { ...cuerpo, origen: window.location.origin },
  })
  if (error) {
    // La función devuelve el motivo en el cuerpo de la respuesta de error
    let motivo = t('plataforma.errorGenerico')
    try {
      const resp = (error as any).context
      if (resp?.json) motivo = (await resp.json()).error ?? motivo
    } catch { /* se queda el mensaje genérico */ }
    throw new Error(motivo)
  }
  return data
}

async function cargar() {
  cargando.value = true
  try {
    const d = await llamar({ accion: 'listar' })
    iglesias.value = d.iglesias
    planes.value = d.planes
    modulos.value = d.modulos
    planModulos.value = d.plan_modulos
    registro.value = await llamar({ accion: 'registro_estado' })
  } catch (e: any) {
    const texto = e.message
    avisar(() => texto, true)
  }
  cargando.value = false
}

function avisar(texto: () => string, error = false) {
  mensaje.value = texto
  mensajeError.value = error
}

function limiteMiembros(ig: any) {
  return planes.value.find(p => p.clave === ig.plan)?.max_miembros ?? null
}

// Módulos que no son del núcleo: incluidos por el plan o contratables aparte
function modulosOpcionales(ig: any) {
  return modulos.value
    .filter(m => m.tipo !== 'nucleo')
    .map(m => ({
      ...m,
      delPlan: planModulos.value.some(pm => pm.plan === ig.plan && pm.modulo === m.clave),
      activo: ig.addons.some((a: any) => a.modulo === m.clave && a.activo),
    }))
}

async function ejecutar(cuerpo: Record<string, unknown>, ok: () => string) {
  try {
    await llamar(cuerpo)
    avisar(ok)
    await cargar()
  } catch (e: any) {
    const texto = e.message
    avisar(() => texto, true)
    await cargar()
  }
}

const cambiarPlan = (ig: any, plan: string) =>
  ejecutar({ accion: 'cambiar_plan', iglesia_id: ig.id, plan }, () => t('plataforma.planActualizado', { iglesia: ig.nombre }))

const alternarModulo = (ig: any, m: any) => {
  const clave = m.activo ? 'plataforma.moduloQuitado' : 'plataforma.moduloActivado'
  return ejecutar({ accion: 'modulo_addon', iglesia_id: ig.id, modulo: m.clave, activo: !m.activo },
    () => t(clave, { modulo: m.nombre, iglesia: ig.nombre }))
}

const ETAPAS = ['onboarding', 'prueba', 'activa', 'receso', 'suspendida']

function cambiarEtapa(ig: any, el: HTMLSelectElement) {
  const etapa = el.value
  if (etapa === ig.etapa) return
  const nombre = t('plataforma.etapa.' + etapa)
  if (!window.confirm(t('plataforma.confirmarEtapa', { iglesia: ig.nombre, etapa: nombre }))) { el.value = ig.etapa; return }
  ejecutar({ accion: 'etapa', iglesia_id: ig.id, etapa },
    () => t('plataforma.etapaCambiada', { iglesia: ig.nombre, etapa: nombre }))
}

async function crearIglesia() {
  creando.value = true
  errorNueva.value = ''
  try {
    await llamar({ accion: 'crear_iglesia', ...nueva.value })
    abrirNueva.value = false
    const correo = nueva.value.email
    avisar(() => t('plataforma.creada', { correo }))
    nueva.value = vacia()
    await cargar()
  } catch (e: any) {
    errorNueva.value = e.message
  }
  creando.value = false
}

onMounted(cargar)
</script>

<style scoped>
.campo {
  @apply w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde;
}
</style>
