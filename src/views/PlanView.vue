<template>
  <div class="p-4 sm:p-6 space-y-6 max-w-5xl">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('planes.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-1">{{ t('planes.subtitulo') }}</p>
    </div>

    <p v-if="ajustes?.propuesta" role="note" class="text-sm text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-4 py-3">
      {{ t('planes.aviso') }} <span v-if="!ajustes.moneda">{{ t('planes.sinMoneda') }}</span>
    </p>

    <p v-if="cargando" class="py-10 text-center text-gray-400" role="status">{{ t('comun.cargando') }}</p>
    <p v-else-if="!cat" role="alert" class="bg-red-50 text-red-700 text-sm px-4 py-3 rounded-lg border border-red-200">{{ t('planes.errorCargar') }}</p>

    <template v-else>
      <!-- Tu plan -->
      <section class="card space-y-1" aria-labelledby="pl-tuplan">
        <h2 id="pl-tuplan" class="text-lg font-semibold text-gray-900">{{ t('planes.tuPlan') }}: {{ planActual?.nombre ?? auth.iglesia?.plan }}</h2>
        <p class="text-sm text-gray-600">{{ limiteTexto(planActual) }}</p>
        <p class="text-sm text-gray-600">{{ t('planes.estimacionActual', { importe: fmt(actual.total) }) }}</p>
      </section>

      <!-- Modulos: los que no estan activos, con candado -->
      <section class="card space-y-3" aria-labelledby="pl-modulos">
        <h2 id="pl-modulos" class="text-lg font-semibold text-gray-900">{{ t('planes.modulos.titulo') }}</h2>
        <ul class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <li v-for="m in contratables" :key="m.clave">
            <div v-if="activos.has(m.clave)" class="flex items-start gap-3 border border-green-100 bg-green-50/50 rounded-xl px-4 py-3">
              <Check class="w-5 h-5 text-green-600 mt-0.5 flex-shrink-0" aria-hidden="true" />
              <div class="min-w-0">
                <p class="font-medium text-gray-900">{{ m.nombre }}</p>
                <p class="text-xs text-green-700">{{ t('planes.modulos.activo') }}</p>
              </div>
            </div>
            <button v-else type="button" @click="abrirModulo(m)" :aria-label="t('planes.modulos.abrirDetalle', { modulo: m.nombre })"
              class="w-full text-left flex items-start gap-3 border border-gray-200 rounded-xl px-4 py-3 hover:border-adn-verde hover:bg-gray-50 transition-colors">
              <Lock class="w-5 h-5 text-gray-400 mt-0.5 flex-shrink-0" aria-hidden="true" />
              <div class="min-w-0">
                <p class="font-medium text-gray-700">{{ m.nombre }}</p>
                <p class="text-xs text-gray-500">{{ m.clave in cat.precioModulo ? t('planes.modulos.masPrecio', { importe: fmt(cat.precioModulo[m.clave] ?? 0) }) : t('planes.modulos.porConfirmar') }}</p>
              </div>
            </button>
          </li>
        </ul>
      </section>

      <!-- Calculadora -->
      <section class="card space-y-4" aria-labelledby="pl-calc">
        <div>
          <h2 id="pl-calc" class="text-lg font-semibold text-gray-900">{{ t('planes.calc.titulo') }}</h2>
          <p class="text-sm text-gray-500 mt-0.5">{{ t('planes.calc.descripcion') }}</p>
        </div>
        <div class="grid grid-cols-2 gap-3 max-w-sm">
          <div>
            <label for="pl-personas" class="block text-xs font-medium text-gray-500 mb-1">{{ t('planes.calc.personas') }}</label>
            <input id="pl-personas" v-model.number="personas" type="number" min="0" inputmode="numeric" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm" />
          </div>
          <div>
            <label for="pl-usuarios" class="block text-xs font-medium text-gray-500 mb-1">{{ t('planes.calc.usuarios') }}</label>
            <input id="pl-usuarios" v-model.number="usuarios" type="number" min="0" inputmode="numeric" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm" />
          </div>
        </div>
        <fieldset>
          <legend class="text-xs font-medium text-gray-500 mb-2">{{ t('planes.calc.modulos') }}</legend>
          <div class="flex flex-wrap gap-2">
            <label v-for="m in contratables" :key="m.clave" class="inline-flex items-center gap-2 text-sm border border-gray-200 rounded-full px-3 py-1.5 cursor-pointer has-[:checked]:border-adn-verde has-[:checked]:bg-green-50">
              <input type="checkbox" :value="m.clave" v-model="elegidos" class="accent-green-700" />
              {{ m.nombre }}
            </label>
          </div>
        </fieldset>

        <ul class="space-y-2" :aria-label="t('planes.calc.plan')">
          <li v-for="c in comparacion" :key="c.plan" :class="['border rounded-xl px-4 py-3 flex flex-wrap items-center justify-between gap-2', c.plan === recomendada?.plan ? 'border-adn-verde bg-green-50/50' : 'border-gray-200']">
            <div class="min-w-0">
              <p class="font-semibold text-gray-900">
                {{ nombrePlan(c.plan) }}
                <span v-if="c.plan === recomendada?.plan" class="ml-2 text-xs font-medium text-green-700 bg-green-100 rounded-full px-2 py-0.5">{{ t('planes.calc.recomendado') }}</span>
                <span v-if="c.plan === auth.iglesia?.plan" class="ml-2 text-xs font-medium text-gray-600 bg-gray-100 rounded-full px-2 py-0.5">{{ t('planes.calc.tuPlan') }}</span>
              </p>
              <p v-if="!c.cabe" class="text-xs text-amber-700">{{ t('planes.calc.noCabe') }}</p>
              <p v-else-if="c.sinPrecio.length" class="text-xs text-amber-700">{{ t('planes.calc.sinPrecio') }}</p>
              <p v-else class="text-xs text-gray-500">{{ diferenciaTexto(c.total) }}</p>
            </div>
            <p class="text-lg font-bold text-gray-900">{{ t('planes.calc.alMes', { importe: fmt(c.total) }) }}</p>
          </li>
        </ul>
      </section>
    </template>

    <!-- Aviso de aumento de facturacion al tocar un modulo bloqueado -->
    <div v-if="modulo" class="fixed inset-0 bg-black bg-opacity-40 z-50 overflow-y-auto" @click.self="modulo = null" role="dialog" aria-modal="true" :aria-label="t('planes.modal.titulo', { modulo: modulo.nombre })">
      <div class="min-h-full flex items-center justify-center p-4" @click.self="modulo = null">
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 my-2 space-y-3">
          <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><Lock class="w-5 h-5 text-gray-400" aria-hidden="true" /> {{ t('planes.modal.titulo', { modulo: modulo.nombre }) }}</h2>
          <p v-if="modulo.descripcion" class="text-sm text-gray-500">{{ modulo.descripcion }}</p>
          <p v-if="aumento && !aumento.sinPrecio.length" class="text-sm text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
            {{ t('planes.modal.aumento', { importe: fmt(aumento.total - actual.total), actual: fmt(actual.total), nueva: fmt(aumento.total) }) }}
          </p>
          <p v-else class="text-sm text-gray-600">{{ t('planes.modal.sinPrecio') }}</p>
          <p class="text-sm text-gray-600">{{ t('planes.modal.como') }}</p>
          <button @click="modulo = null" class="btn-primary w-full">{{ t('planes.modal.entendido') }}</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { Lock, Check } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { cotizar, compararPlanes, recomendado, modulosContratables, formatoImporte } from '@/lib/cotizador'
import type { Catalogo, PlanCat, ModuloCat } from '@/lib/cotizador'

const { t, locale } = useI18n()
const auth = useAuthStore()

const cargando = ref(true)
const cat = ref<Catalogo | null>(null)
const ajustes = ref<{ moneda: string | null; impuestos_incluidos: boolean | null; propuesta: boolean } | null>(null)
const modulo = ref<ModuloCat | null>(null)
const elegidos = ref<string[]>([])
const personas = ref<number | null>(null)
const usuarios = ref<number | null>(null)

const fmt = (centimos: number) => formatoImporte(centimos, ajustes.value?.moneda ?? null, locale.value)
const contratables = computed(() => (cat.value ? modulosContratables(cat.value) : []))
// Lo que la iglesia tiene hoy: los modulos que su plan y sus complementos activan
const activos = computed(() => new Set(contratables.value.filter(m => auth.tieneModulo(m.clave)).map(m => m.clave)))
const planActual = computed<PlanCat | undefined>(() => cat.value?.planes.find(p => p.clave === auth.iglesia?.plan))
const actual = computed(() => (cat.value && auth.iglesia ? cotizar(cat.value, auth.iglesia.plan, activos.value) : { total: 0 } as ReturnType<typeof cotizar>))
const aumento = computed(() => (cat.value && auth.iglesia && modulo.value ? cotizar(cat.value, auth.iglesia.plan, [...activos.value, modulo.value.clave]) : null))
const req = computed(() => ({ personas: personas.value || null, usuarios: usuarios.value || null }))
const comparacion = computed(() => (cat.value ? compararPlanes(cat.value, elegidos.value, req.value) : []))
const recomendada = computed(() => (cat.value ? recomendado(cat.value, elegidos.value, req.value) : null))

const nombrePlan = (clave: string) => cat.value?.planes.find(p => p.clave === clave)?.nombre ?? clave
function limiteTexto(p?: PlanCat) {
  if (!p) return ''
  const a = p.max_miembros === null ? t('planes.sinLimitePersonas') : t('planes.limitePersonas', { n: p.max_miembros.toLocaleString(locale.value) })
  const b = p.max_usuarios === null ? t('planes.sinLimiteUsuarios') : t('planes.limiteUsuarios', { n: p.max_usuarios })
  return `${a}. ${b}.`
}
function diferenciaTexto(total: number) {
  const d = total - actual.value.total
  return d === 0 ? t('planes.calc.igual') : d > 0 ? t('planes.calc.diferenciaMas', { importe: fmt(d) }) : t('planes.calc.diferenciaMenos', { importe: fmt(-d) })
}
const abrirModulo = (m: ModuloCat) => { modulo.value = m }

onMounted(async () => {
  const [planes, modulos, planMods, pPlan, pMod, aj] = await Promise.all([
    supabase.from('planes').select('clave, nombre, max_miembros, max_usuarios, orden').eq('activo', true).order('orden'),
    supabase.from('modulos').select('clave, nombre, descripcion, tipo, orden').order('orden'),
    supabase.from('plan_modulos').select('plan, modulo'),
    supabase.from('precios_plan').select('plan, importe_centimos'),
    supabase.from('precios_modulo').select('modulo, importe_centimos'),
    supabase.from('precios_ajustes').select('moneda, impuestos_incluidos, propuesta').maybeSingle(),
  ])
  if (planes.error || modulos.error || planMods.error || pPlan.error || pMod.error || !planes.data || !modulos.data) { cargando.value = false; return }
  const planModulos: Record<string, string[]> = {}
  for (const r of planMods.data ?? []) (planModulos[r.plan] ??= []).push(r.modulo)
  cat.value = {
    planes: planes.data as PlanCat[],
    modulos: modulos.data as ModuloCat[],
    planModulos,
    precioPlan: Object.fromEntries((pPlan.data ?? []).map((r: any) => [r.plan, r.importe_centimos])),
    precioModulo: Object.fromEntries((pMod.data ?? []).map((r: any) => [r.modulo, r.importe_centimos])),
  }
  ajustes.value = aj.data ?? null
  elegidos.value = [...activos.value]
  // El tamano de partida es el real: sin el, la calculadora recomendaria un plan que no cubre a la iglesia
  const { count } = await supabase.from('miembros').select('id', { count: 'exact', head: true }).eq('activo', true)
  if (count) personas.value = count
  cargando.value = false
})
</script>
