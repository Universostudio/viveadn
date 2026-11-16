<template>
  <div class="min-h-screen bg-gradient-to-br from-adn-verde to-adn-oscuro flex items-center justify-center p-4">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-lg p-6 sm:p-8">
      <div class="text-center mb-6">
        <LogoAdn class="w-12 h-auto mx-auto mb-3 text-adn-verde" />
        <h1 class="text-2xl font-bold text-adn-verde">{{ t('registro.titulo') }}</h1>
        <p class="text-gray-500 text-sm mt-1">{{ t('registro.subtitulo') }}</p>
      </div>

      <p v-if="estado === 'cargando'" class="py-8 text-center text-sm text-gray-400" role="status">{{ t('comun.cargando') }}</p>

      <div v-else-if="estado === 'cerrado'" class="text-center py-6">
        <p class="font-medium text-gray-800">{{ t('registro.cerradoTitulo') }}</p>
        <p class="text-sm text-gray-500 mt-1">{{ t('registro.cerradoTexto') }}</p>
        <RouterLink :to="{ name: 'login' }" class="btn-secondary inline-block mt-5">{{ t('registro.irAlAcceso') }}</RouterLink>
      </div>

      <div v-else-if="estado === 'enviado'" class="text-center py-4" role="status">
        <div class="w-12 h-12 rounded-full bg-green-100 text-green-700 flex items-center justify-center mx-auto mb-3"><MailCheck class="w-6 h-6" aria-hidden="true" /></div>
        <p class="font-semibold text-gray-900">{{ t('registro.exitoTitulo') }}</p>
        <p class="text-sm text-gray-600 mt-2">{{ t('registro.exitoTexto') }}</p>
        <p class="text-xs text-gray-400 mt-3">{{ t('registro.exitoAyuda') }}</p>
        <RouterLink :to="{ name: 'login' }" class="btn-secondary inline-block mt-5">{{ t('registro.irAlAcceso') }}</RouterLink>
      </div>

      <form v-else @submit.prevent="siguiente" class="space-y-5" novalidate>
        <div>
          <p class="text-xs font-medium text-gray-500" aria-live="polite">{{ t('registro.pasoDe', { n: indice + 1, total: pasos.length }) }}: {{ t('registro.pasos.' + pasoActual) }}</p>
          <div class="mt-2 h-1.5 bg-gray-100 rounded-full overflow-hidden" role="presentation"><div class="h-full bg-adn-verde transition-all" :style="{ width: ((indice + 1) / pasos.length * 100) + '%' }"></div></div>
        </div>

        <!-- 1. Tu iglesia -->
        <fieldset v-show="pasoActual === 'iglesia'" class="space-y-3">
          <legend class="text-sm font-semibold text-gray-900 mb-1">{{ t('registro.tuIglesia') }}</legend>
          <div>
            <label for="rg-nombre" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.nombreIglesia') }}</label>
            <input id="rg-nombre" v-model="form.nombre" maxlength="80" required autocomplete="organization" class="campo" @input="sugerirDireccion" />
          </div>
          <div>
            <label for="rg-slug" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.direccion') }}</label>
            <input id="rg-slug" v-model="form.slug" maxlength="40" required autocapitalize="none" spellcheck="false" class="campo font-mono" @input="direccionEditada = true" />
            <p class="text-xs text-gray-400 mt-1">{{ t('registro.direccionAyuda', { ejemplo: form.slug || 'tu-iglesia' }) }}</p>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label for="rg-pais" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.pais') }}</label>
              <input id="rg-pais" v-model="form.pais" maxlength="80" required autocomplete="country-name" class="campo" />
            </div>
            <div>
              <label for="rg-ciudad" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.ciudad') }}</label>
              <input id="rg-ciudad" v-model="form.ciudad" maxlength="80" required autocomplete="address-level2" class="campo" />
            </div>
          </div>
        </fieldset>

        <!-- 2. Como esta organizada -->
        <fieldset v-show="pasoActual === 'estructura'" class="space-y-3">
          <legend class="text-sm font-semibold text-gray-900 mb-1">{{ t('registro.estructura.titulo') }}</legend>
          <label v-for="o in TIPOS" :key="o" :class="['flex items-start gap-3 border rounded-xl px-4 py-3 cursor-pointer', form.tipo === o ? 'border-adn-verde bg-green-50/50' : 'border-gray-200']">
            <input type="radio" name="rg-tipo" :value="o" v-model="form.tipo" class="mt-1 accent-green-700" />
            <span><span class="block text-sm font-medium text-gray-900">{{ t('registro.estructura.' + o) }}</span><span class="block text-xs text-gray-500">{{ t('registro.estructura.' + o + 'Ayuda') }}</span></span>
          </label>
          <div>
            <label for="rg-personas" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.estructura.personas') }}</label>
            <input id="rg-personas" v-model.number="form.personas" type="number" min="1" max="1000000" inputmode="numeric" class="campo" />
            <p class="text-xs text-gray-400 mt-1">{{ t('registro.estructura.personasAyuda') }}</p>
          </div>
          <div v-if="form.tipo !== 'unica'">
            <label for="rg-sedes" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.estructura.sedes') }}</label>
            <input id="rg-sedes" v-model.number="form.sedes" type="number" min="0" max="200" inputmode="numeric" class="campo" />
            <p class="text-xs text-gray-400 mt-1">{{ t('registro.estructura.sedesAyuda') }}</p>
          </div>
        </fieldset>

        <!-- 3. Tu equipo -->
        <fieldset v-show="pasoActual === 'equipo'" class="space-y-3">
          <legend class="text-sm font-semibold text-gray-900 mb-1">{{ t('registro.tuCuenta') }}</legend>
          <p class="text-xs text-gray-500">{{ t('registro.equipo.propietarioAyuda') }}</p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label for="rg-pnombre" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.nombre') }}</label>
              <input id="rg-pnombre" v-model="form.pnombre" maxlength="60" required autocomplete="given-name" class="campo" />
            </div>
            <div>
              <label for="rg-papellido" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.apellido') }}</label>
              <input id="rg-papellido" v-model="form.papellido" maxlength="60" required autocomplete="family-name" class="campo" />
            </div>
          </div>
          <div>
            <label for="rg-email" class="block text-sm font-medium text-gray-700 mb-1">{{ t('login.correo') }}</label>
            <input id="rg-email" v-model="form.email" type="email" maxlength="254" required autocomplete="email" class="campo" />
            <p class="text-xs text-gray-400 mt-1">{{ t('registro.correoAyuda') }}</p>
          </div>
          <div class="pt-2 border-t border-gray-100 space-y-3">
            <p class="text-sm font-semibold text-gray-900">{{ t('registro.equipo.adminTitulo') }}</p>
            <p class="text-xs text-gray-500">{{ t('registro.equipo.adminAyuda') }}</p>
            <div v-for="(a, i) in form.admins" :key="i" class="border border-gray-200 rounded-xl p-3 space-y-2">
              <div class="grid grid-cols-2 gap-2">
                <input v-model="a.nombre" maxlength="60" :placeholder="t('registro.nombre')" :aria-label="t('registro.nombre') + ' ' + (i + 1)" class="campo" />
                <input v-model="a.apellido" maxlength="60" :placeholder="t('registro.apellido')" :aria-label="t('registro.apellido') + ' ' + (i + 1)" class="campo" />
              </div>
              <input v-model="a.email" type="email" maxlength="254" :placeholder="t('login.correo')" :aria-label="t('login.correo') + ' ' + (i + 1)" class="campo" />
              <button type="button" class="text-xs text-red-600 hover:underline" @click="form.admins.splice(i, 1)">{{ t('registro.equipo.adminQuitar') }}</button>
            </div>
            <button v-if="form.admins.length < MAX_ADMINS" type="button" class="btn-secondary text-sm" @click="form.admins.push({ nombre: '', apellido: '', email: '' })">{{ t('registro.equipo.adminAnadir') }}</button>
          </div>
        </fieldset>

        <!-- 4. Modulos -->
        <fieldset v-if="cat" v-show="pasoActual === 'modulos'" class="space-y-3">
          <legend class="text-sm font-semibold text-gray-900 mb-1">{{ t('registro.modulosPaso.titulo') }}</legend>
          <p class="text-xs text-gray-500">{{ t('registro.modulosPaso.ayuda') }}</p>
          <label v-for="m in contratables" :key="m.clave" :class="['flex items-start gap-3 border rounded-xl px-4 py-3 cursor-pointer', form.modulos.includes(m.clave) ? 'border-adn-verde bg-green-50/50' : 'border-gray-200']">
            <input type="checkbox" :value="m.clave" v-model="form.modulos" class="mt-1 accent-green-700" />
            <span class="min-w-0"><span class="block text-sm font-medium text-gray-900">{{ m.nombre }}</span>
              <span v-if="m.descripcion" class="block text-xs text-gray-500">{{ m.descripcion }}</span>
              <span class="block text-xs text-gray-400">{{ m.clave in cat.precioModulo ? t('registro.modulosPaso.precio', { importe: fmt(cat.precioModulo[m.clave] ?? 0) }) : t('registro.modulosPaso.sinPrecio') }}</span></span>
          </label>
        </fieldset>

        <!-- 5. Plan -->
        <fieldset v-if="cat" v-show="pasoActual === 'plan'" class="space-y-3">
          <legend class="text-sm font-semibold text-gray-900 mb-1">{{ t('registro.planPaso.titulo') }}</legend>
          <p class="text-xs text-gray-500">{{ t('registro.planPaso.ayuda') }}</p>
          <p v-if="ajustes?.propuesta" role="note" class="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">{{ t('planes.aviso') }} <span v-if="!ajustes.moneda">{{ t('planes.sinMoneda') }}</span></p>
          <label v-for="c in comparacion" :key="c.plan" :class="['flex items-start gap-3 border rounded-xl px-4 py-3', !c.cabe ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer', form.plan === c.plan ? 'border-adn-verde bg-green-50/50' : 'border-gray-200']">
            <input type="radio" name="rg-plan" :value="c.plan" v-model="form.plan" :disabled="!c.cabe" class="mt-1 accent-green-700" />
            <span class="flex-1 min-w-0">
              <span class="flex items-center justify-between gap-2">
                <span class="text-sm font-semibold text-gray-900">{{ nombrePlan(c.plan) }}
                  <span v-if="c.plan === recomendada?.plan" class="ml-1 text-xs font-medium text-green-700 bg-green-100 rounded-full px-2 py-0.5">{{ t('planes.calc.recomendado') }}</span></span>
                <span class="text-sm font-bold text-gray-900">{{ t('planes.calc.alMes', { importe: fmt(c.total) }) }}</span>
              </span>
              <span v-if="!c.cabe" class="block text-xs text-amber-700">{{ t('planes.calc.noCabe') }}</span>
              <span v-else-if="c.sinPrecio.length" class="block text-xs text-amber-700">{{ t('planes.calc.sinPrecio') }}</span>
              <span v-else class="block text-xs text-gray-500">{{ limitesTexto(c.plan) }}</span>
            </span>
          </label>
        </fieldset>

        <!-- 6. Confirmar -->
        <fieldset v-show="pasoActual === 'confirmar'" class="space-y-3">
          <legend class="text-sm font-semibold text-gray-900 mb-1">{{ t('registro.confirmarPaso.titulo') }}</legend>
          <ul class="text-sm text-gray-700 space-y-1 bg-gray-50 rounded-xl px-4 py-3">
            <li>{{ t('registro.confirmarPaso.iglesia', { nombre: form.nombre, ciudad: form.ciudad }) }}</li>
            <li>{{ t('registro.confirmarPaso.estructura', { tipo: t('registro.estructura.' + form.tipo), personas: form.personas ?? 0 }) }}</li>
            <li>{{ t('registro.confirmarPaso.propietario', { nombre: form.pnombre + ' ' + form.papellido, email: form.email }) }}</li>
            <li v-if="form.admins.length">{{ t('registro.confirmarPaso.admins', { n: form.admins.length }) }}</li>
            <li v-if="cat && planElegido">{{ t('registro.confirmarPaso.plan', { plan: nombrePlan(planElegido.plan), importe: fmt(planElegido.total) }) }}</li>
          </ul>
          <p class="text-xs text-gray-500">{{ t('registro.confirmarPaso.sinCobro') }}</p>
          <div v-if="requiereCodigo">
            <label for="rg-codigo" class="block text-sm font-medium text-gray-700 mb-1">{{ t('registro.codigo') }}</label>
            <input id="rg-codigo" v-model="form.codigo" maxlength="20" required autocapitalize="characters" spellcheck="false" placeholder="ADN-XXXX-XXXX" class="campo font-mono uppercase" />
            <p class="text-xs text-gray-400 mt-1">{{ t('registro.codigoAyuda') }}</p>
          </div>
          <!-- Campo trampa: las personas no lo ven -->
          <div class="absolute -left-[9999px]" aria-hidden="true">
            <label for="rg-web">Web</label>
            <input id="rg-web" v-model="form.web" tabindex="-1" autocomplete="off" />
          </div>
          <label class="flex items-start gap-2 text-sm text-gray-700">
            <input v-model="form.consentimiento" type="checkbox" class="mt-1" />
            <span>{{ t('registro.consentimiento') }}</span>
          </label>
        </fieldset>

        <p v-if="error" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t(error) }}</p>

        <div class="flex gap-3">
          <button v-if="indice > 0" type="button" class="btn-secondary flex-1" @click="atras">{{ t('registro.atras') }}</button>
          <button type="submit" :disabled="enviando" class="flex-1 btn-primary py-3 text-base disabled:opacity-60">
            {{ esUltimo ? (enviando ? t('registro.enviando') : t('registro.enviar')) : t('registro.siguiente') }}
          </button>
        </div>
        <p class="text-center text-sm text-gray-500">
          {{ t('registro.yaTienes') }} <RouterLink :to="{ name: 'login' }" class="text-adn-verde font-medium hover:underline">{{ t('registro.irAlAcceso') }}</RouterLink>
        </p>
      </form>

      <div class="mt-6 flex justify-center"><SelectorIdioma /></div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { reactive, ref, computed, watch, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { MailCheck } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import LogoAdn from '@/components/LogoAdn.vue'
import SelectorIdioma from '@/components/SelectorIdioma.vue'
import { compararPlanes, recomendado, modulosContratables, formatoImporte } from '@/lib/cotizador'
import type { Catalogo, PlanCat, ModuloCat } from '@/lib/cotizador'

const { t, locale } = useI18n()
const TIPOS = ['unica', 'con_sedes', 'red'] as const
const MAX_ADMINS = 5
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/

const estado = ref<'cargando' | 'abierto' | 'cerrado' | 'enviado'>('cargando')
const requiereCodigo = ref(true)
const enviando = ref(false)
const error = ref('')
const direccionEditada = ref(false)
const cat = ref<Catalogo | null>(null)
const ajustes = ref<{ moneda: string | null; impuestos_incluidos: boolean | null; propuesta: boolean } | null>(null)
const indice = ref(0)
const form = reactive({
  nombre: '', slug: '', pais: '', ciudad: '',
  tipo: 'unica' as (typeof TIPOS)[number], personas: null as number | null, sedes: 0 as number | null,
  pnombre: '', papellido: '', email: '', admins: [] as { nombre: string; apellido: string; email: string }[],
  modulos: [] as string[], plan: '', codigo: '', web: '', consentimiento: false,
})

// Sin catalogo (no cargo) el asistente se acorta: sin modulos ni plan, y el servidor da el plan inicial de siempre
const pasos = computed(() => (cat.value ? ['iglesia', 'estructura', 'equipo', 'modulos', 'plan', 'confirmar'] : ['iglesia', 'estructura', 'equipo', 'confirmar']))
const pasoActual = computed(() => pasos.value[indice.value] ?? 'iglesia')
const esUltimo = computed(() => indice.value === pasos.value.length - 1)

const fmt = (c: number) => formatoImporte(c, ajustes.value?.moneda ?? null, locale.value)
const contratables = computed<ModuloCat[]>(() => (cat.value ? modulosContratables(cat.value) : []))
const requisitos = computed(() => ({ personas: form.personas }))
const comparacion = computed(() => (cat.value ? compararPlanes(cat.value, form.modulos, requisitos.value) : []))
const recomendada = computed(() => (cat.value ? recomendado(cat.value, form.modulos, requisitos.value) : null))
const planElegido = computed(() => comparacion.value.find(c => c.plan === form.plan) ?? null)
const nombrePlan = (clave: string) => cat.value?.planes.find(p => p.clave === clave)?.nombre ?? clave
function limitesTexto(clave: string) {
  const p = cat.value?.planes.find(x => x.clave === clave)
  if (!p) return ''
  const a = p.max_miembros === null ? t('planes.sinLimitePersonas') : t('planes.limitePersonas', { n: p.max_miembros.toLocaleString(locale.value) })
  const b = p.max_usuarios === null ? t('planes.sinLimiteUsuarios') : t('planes.limiteUsuarios', { n: p.max_usuarios })
  return `${a}. ${b}.`
}

// La direccion corta se propone a partir del nombre, sin tildes, hasta que la persona la cambie
const aDireccion = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40).replace(/-+$/, '')
function sugerirDireccion() { if (!direccionEditada.value) form.slug = aDireccion(form.nombre) }

// Al llegar al paso del plan se propone el recomendado, y si el elegido deja de cubrir el tamano se cambia
watch([pasoActual, comparacion], () => {
  if (pasoActual.value !== 'plan') return
  const actual = comparacion.value.find(c => c.plan === form.plan)
  if (!actual || !actual.cabe) form.plan = recomendada.value?.plan ?? comparacion.value.find(c => c.cabe)?.plan ?? ''
})

async function codigoDe(err: unknown): Promise<string> {
  try {
    const resp = (err as { context?: Response })?.context
    if (resp?.json) return (await resp.json()).error ?? ''
  } catch { /* sin detalle */ }
  return ''
}

onMounted(async () => {
  const { data, error: err } = await supabase.functions.invoke('registro-iglesia', { body: { accion: 'catalogo' } })
  if (!err && typeof data?.abierto === 'boolean' && Array.isArray(data.planes) && Array.isArray(data.modulos)) {
    requiereCodigo.value = data.requiere_codigo !== false
    const planModulos: Record<string, string[]> = {}
    for (const r of data.plan_modulos ?? []) (planModulos[r.plan] ??= []).push(r.modulo)
    cat.value = {
      planes: data.planes as PlanCat[], modulos: data.modulos as ModuloCat[], planModulos,
      precioPlan: Object.fromEntries((data.precios_plan ?? []).map((r: any) => [r.plan, r.importe_centimos])),
      precioModulo: Object.fromEntries((data.precios_modulo ?? []).map((r: any) => [r.modulo, r.importe_centimos])),
    }
    ajustes.value = data.ajustes ?? null
    estado.value = data.abierto ? 'abierto' : 'cerrado'
    return
  }
  // Sin catalogo, el registro corto de siempre
  const { data: d2, error: e2 } = await supabase.functions.invoke('registro-iglesia', { body: { accion: 'consultar' } })
  if (e2 || typeof d2?.abierto !== 'boolean') { estado.value = 'cerrado'; return }
  requiereCodigo.value = d2.requiere_codigo !== false
  estado.value = d2.abierto ? 'abierto' : 'cerrado'
})

// Validacion amable de cada paso; el servidor vuelve a validarlo todo
function validarPaso(): string {
  const p = pasoActual.value
  if (p === 'iglesia') {
    if (form.nombre.trim().length < 2) return 'registro.validacion.iglesia'
    if (!SLUG_RE.test(form.slug) || form.slug.length < 3) return 'registro.validacion.direccion'
    if (!form.pais.trim() || !form.ciudad.trim()) return 'registro.validacion.iglesia'
  } else if (p === 'estructura') {
    if (!Number.isInteger(form.personas) || (form.personas as number) < 1) return 'registro.validacion.personas'
    if (form.tipo !== 'unica' && (!Number.isInteger(form.sedes) || (form.sedes as number) < 0)) return 'registro.validacion.sedes'
  } else if (p === 'equipo') {
    if (!form.pnombre.trim() || !form.papellido.trim() || !EMAIL_RE.test(form.email.trim())) return 'registro.validacion.equipo'
    const vistos = new Set([form.email.trim().toLowerCase()])
    for (const a of form.admins) {
      const e = a.email.trim().toLowerCase()
      if (!a.nombre.trim() || !a.apellido.trim() || !EMAIL_RE.test(e)) return 'registro.validacion.admin'
      if (vistos.has(e)) return 'registro.validacion.adminRepetido'
      vistos.add(e)
    }
  } else if (p === 'plan') {
    if (!planElegido.value || !planElegido.value.cabe) return 'registro.validacion.plan'
  } else if (p === 'confirmar') {
    if (requiereCodigo.value && !form.codigo.trim()) return 'registro.errores.codigo'
    if (!form.consentimiento) return 'registro.errores.consentimiento'
  }
  return ''
}

function atras() { error.value = ''; if (indice.value > 0) indice.value-- }
async function siguiente() {
  error.value = validarPaso()
  if (error.value) return
  if (!esUltimo.value) { indice.value++; return }
  await enviar()
}

async function enviar() {
  enviando.value = true
  const cuerpo: Record<string, unknown> = {
    accion: 'registrar', web: form.web, consentimiento: form.consentimiento, codigo: form.codigo,
    iglesia: { nombre: form.nombre, slug: form.slug, pais: form.pais, ciudad: form.ciudad },
    propietario: { nombre: form.pnombre, apellido: form.papellido, email: form.email },
    estructura: { tipo: form.tipo, personas: form.personas, sedes: form.tipo === 'unica' ? 0 : (form.sedes ?? 0) },
    administradores: form.admins.map(a => ({ nombre: a.nombre, apellido: a.apellido, email: a.email })),
  }
  // Solo se propone plan y modulos si el catalogo cargo; el servidor los comprueba contra el catalogo real
  if (cat.value) { cuerpo.plan = form.plan; cuerpo.modulos = form.modulos }
  const { error: err } = await supabase.functions.invoke('registro-iglesia', { body: cuerpo })
  enviando.value = false
  if (!err) { estado.value = 'enviado'; return }
  const c = await codigoDe(err)
  if (c === 'cerrado') { estado.value = 'cerrado'; return }
  if (['datos', 'consentimiento', 'codigo', 'slug', 'limite', 'plan', 'modulos'].includes(c)) error.value = `registro.errores.${c}`
  else error.value = 'registro.errores.generico'
  // Si el problema esta en un paso anterior, se vuelve a el
  const destino: Record<string, string> = { slug: 'iglesia', plan: cat.value ? 'plan' : 'estructura', modulos: 'modulos' }
  const i = destino[c] ? pasos.value.indexOf(destino[c] as string) : -1
  if (i >= 0) indice.value = i
}
</script>

<style scoped>
.campo { @apply w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde; }
</style>
