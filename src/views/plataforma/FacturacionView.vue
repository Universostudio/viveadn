<template>
  <div class="space-y-6" data-test="pm-facturacion">
    <div class="flex items-center gap-3 flex-wrap">
      <h1 class="text-2xl font-bold text-gray-900">{{ t('plataformaPanel.facturacion.titulo') }}</h1>
      <span class="text-xs font-semibold bg-amber-100 text-amber-900 px-2 py-0.5 rounded-full" data-test="datos-de-prueba">{{ t('plataformaPanel.facturacion.datosDePrueba') }}</span>
    </div>
    <p class="text-sm text-gray-600 max-w-3xl">{{ t('plataformaPanel.facturacion.explicacion') }}</p>

    <p v-if="estado === 'cargando'" class="text-sm text-gray-500" role="status">{{ t('comun.cargando') }}</p>
    <p v-else-if="estado === 'error'" class="card text-sm text-red-700" role="alert" data-test="fact-error">{{ t('plataformaPanel.facturacion.errorCarga') }}</p>
    <template v-else-if="sim">
      <p v-if="aviso" class="text-sm text-green-800 rounded-lg bg-green-50 p-3" role="status" data-test="fact-aviso">{{ aviso }}</p>
      <p v-if="error" class="text-sm text-red-700 rounded-lg bg-red-50 p-3" role="alert" data-test="fact-fallo">{{ error }}</p>
      <p v-if="!sim.migrado" class="text-sm text-gray-700 rounded-lg bg-gray-50 border border-gray-200 p-3" data-test="fact-sin-migracion">{{ t('plataformaPanel.facturacion.sinMigracion') }}</p>

      <section class="card" aria-labelledby="f-tabla">
        <h2 id="f-tabla" class="text-base font-semibold text-gray-900 mb-1">{{ t('plataformaPanel.facturacion.ingresoEsperado') }}</h2>
        <p class="text-3xl font-bold text-gray-900" data-test="fact-total">{{ totalTexto }}</p>
        <p v-if="sim.incompleto" class="text-sm text-amber-800 mt-1" data-test="fact-incompleto">{{ t('plataformaPanel.facturacion.incompleto') }}</p>
        <p v-else-if="!sim.pagando" class="text-sm text-gray-600 mt-1" data-test="fact-ceros">{{ t('plataformaPanel.facturacion.ceroSinIglesias') }}</p>
        <div class="overflow-x-auto mt-4">
          <table class="w-full text-sm" data-test="fact-tabla">
            <thead class="text-left text-xs text-gray-500 border-b border-gray-100"><tr>
              <th scope="col" class="py-2 pr-3 font-medium">{{ t('plataformaPanel.facturacion.plan') }}</th>
              <th scope="col" class="py-2 px-3 font-medium text-right">{{ t('plataformaPanel.facturacion.pagan') }}</th>
              <th scope="col" class="py-2 px-3 font-medium text-right">{{ t('plataformaPanel.facturacion.mensual') }}</th>
              <th scope="col" class="py-2 px-3 font-medium text-right">{{ t('plataformaPanel.facturacion.anual') }}</th>
              <th scope="col" class="py-2 px-3 font-medium text-right">{{ t('plataformaPanel.facturacion.ingreso') }}</th>
              <th scope="col" class="py-2 pl-3"><span class="sr-only">{{ t('plataformaPanel.facturacion.fijar') }}</span></th></tr></thead>
            <tbody class="divide-y divide-gray-50">
              <tr v-for="p in sim.planes" :key="p.clave" :data-plan="p.clave">
                <th scope="row" class="py-2 pr-3 text-left font-medium text-gray-900">{{ p.nombre }}</th>
                <td class="py-2 px-3 text-right tabular-nums" data-campo="pagan">{{ p.iglesias }}</td>
                <td class="py-2 px-3 text-right tabular-nums" data-campo="mensual">{{ dinero(p.precio_mensual_centimos, p.moneda) ?? t('plataformaPanel.facturacion.sinPrecio') }}</td>
                <td class="py-2 px-3 text-right tabular-nums" data-campo="anual">{{ dinero(p.precio_anual_centimos, p.moneda) ?? t('plataformaPanel.facturacion.sinPrecio') }}</td>
                <td class="py-2 px-3 text-right tabular-nums" data-campo="ingreso">
                  <template v-if="p.causa === 'sin_precio'">{{ t('plataformaPanel.facturacion.noCalculable') }}</template>
                  <template v-else>{{ dinero(p.ingreso_mensual_centimos, p.moneda) ?? '0' }}<span v-if="p.causa === 'sin_iglesias'" class="block text-xs text-gray-500">{{ t('plataformaPanel.facturacion.causaSinIglesias') }}</span></template>
                </td>
                <td class="py-2 pl-3 text-right"><button v-if="sim.migrado" type="button" class="btn-secondary text-xs" :data-fijar="p.clave" @click="editar(p)">{{ t('plataformaPanel.facturacion.fijar') }}</button></td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-if="sim.plan_desconocido" class="text-xs text-amber-800 mt-2" data-test="fact-desconocido">{{ t('plataformaPanel.facturacion.planDesconocido', { n: sim.plan_desconocido }) }}</p>
      </section>

      <section class="card space-y-3" aria-labelledby="f-imp" data-test="fact-impuestos">
        <h2 id="f-imp" class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.facturacion.imp.titulo') }}</h2>
        <p v-if="sim.impuestos?.estado !== 'configurado'" class="text-sm font-medium text-amber-900 rounded-lg bg-amber-50 p-3" data-test="imp-pendiente">{{ t('plataformaPanel.facturacion.imp.pendiente') }}</p>
        <p v-else class="text-sm text-gray-700" data-test="imp-configurado">{{ t('plataformaPanel.facturacion.imp.configurado', { n: sim.impuestos.activas }) }}</p>
        <p class="text-xs text-gray-500">{{ t('plataformaPanel.facturacion.imp.nota') }}</p>
        <p v-if="impError" class="text-sm text-red-700 rounded-lg bg-red-50 p-3" role="alert" data-test="imp-fallo">{{ impError }}</p>
        <p v-if="impAviso" class="text-sm text-green-800 rounded-lg bg-green-50 p-3" role="status" data-test="imp-aviso">{{ impAviso }}</p>
        <div class="overflow-x-auto">
          <table v-if="impFilas.length" class="w-full text-sm" data-test="imp-tabla">
            <thead class="text-left text-xs text-gray-500 border-b border-gray-100"><tr>
              <th scope="col" class="py-2 pr-2 font-medium">{{ t('plataformaPanel.facturacion.imp.region') }}</th>
              <th scope="col" class="py-2 px-2 font-medium">{{ t('plataformaPanel.facturacion.imp.concepto') }}</th>
              <th scope="col" class="py-2 px-2 font-medium">{{ t('plataformaPanel.facturacion.imp.tasa') }}</th>
              <th scope="col" class="py-2 px-2 font-medium">{{ t('plataformaPanel.facturacion.imp.incluido') }}</th>
              <th scope="col" class="py-2 px-2 font-medium">{{ t('plataformaPanel.facturacion.imp.activo') }}</th>
              <th scope="col" class="py-2 pl-2"><span class="sr-only">{{ t('plataformaPanel.facturacion.imp.quitar') }}</span></th></tr></thead>
            <tbody class="divide-y divide-gray-50">
              <tr v-for="(f, i) in impFilas" :key="i" data-imp-fila>
                <td class="py-1 pr-2"><input v-model="f.region" maxlength="12" :aria-label="t('plataformaPanel.facturacion.imp.region')" data-campo="region" class="w-24 px-2 py-1 border border-gray-200 rounded-lg uppercase" /></td>
                <td class="py-1 px-2"><input v-model="f.concepto" maxlength="60" :aria-label="t('plataformaPanel.facturacion.imp.concepto')" data-campo="concepto" class="w-40 px-2 py-1 border border-gray-200 rounded-lg" /></td>
                <td class="py-1 px-2"><input v-model="f.tasa" inputmode="decimal" :aria-label="t('plataformaPanel.facturacion.imp.tasa')" data-campo="tasa" class="w-20 px-2 py-1 border border-gray-200 rounded-lg" /></td>
                <td class="py-1 px-2"><select v-model="f.incluido" :aria-label="t('plataformaPanel.facturacion.imp.incluido')" data-campo="incluido" class="px-2 py-1 border border-gray-200 rounded-lg">
                  <option value="">{{ t('plataformaPanel.facturacion.imp.sinDefinir') }}</option><option value="si">{{ t('plataformaPanel.facturacion.imp.si') }}</option><option value="no">{{ t('plataformaPanel.facturacion.imp.no') }}</option></select></td>
                <td class="py-1 px-2"><input v-model="f.activo" type="checkbox" :aria-label="t('plataformaPanel.facturacion.imp.activo')" data-campo="activo" /></td>
                <td class="py-1 pl-2 text-right"><button type="button" class="btn-secondary text-xs" data-imp-quitar @click="impFilas.splice(i, 1)">{{ t('plataformaPanel.facturacion.imp.quitar') }}</button></td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="flex gap-2 flex-wrap">
          <button type="button" class="btn-secondary text-sm" data-test="imp-anadir" @click="impFilas.push({ region: '', concepto: '', tasa: '', incluido: '', activo: false })">{{ t('plataformaPanel.facturacion.imp.anadir') }}</button>
          <button type="button" class="btn-primary text-sm" :disabled="ocupado" data-test="imp-guardar" @click="guardarImpuestos">{{ t('plataformaPanel.facturacion.imp.guardar') }}</button>
        </div>
      </section>

      <form v-if="edicion" class="card space-y-3" novalidate data-test="fact-form" @submit.prevent="guardar">
        <h2 class="text-base font-semibold text-gray-900">{{ t('plataformaPanel.facturacion.fijarPara', { plan: edicion.nombre }) }}</h2>
        <p class="text-xs text-gray-500">{{ t('plataformaPanel.facturacion.fijarNota') }}</p>
        <div class="grid sm:grid-cols-3 gap-3">
          <div><label for="fp-mensual" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataformaPanel.facturacion.mensual') }}</label>
            <input id="fp-mensual" v-model="edicion.mensual" inputmode="decimal" data-test="fp-mensual" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm" /></div>
          <div><label for="fp-anual" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataformaPanel.facturacion.anual') }}</label>
            <input id="fp-anual" v-model="edicion.anual" inputmode="decimal" data-test="fp-anual" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm" /></div>
          <div><label for="fp-moneda" class="block text-sm font-medium text-gray-700 mb-1">{{ t('plataformaPanel.facturacion.moneda') }}</label>
            <input id="fp-moneda" v-model="edicion.moneda" maxlength="3" data-test="fp-moneda" class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm uppercase" /></div>
        </div>
        <div class="flex gap-2">
          <button type="submit" class="btn-primary text-sm" :disabled="ocupado" data-test="fp-guardar">{{ t('plataformaPanel.facturacion.guardar') }}</button>
          <button type="button" class="btn-secondary text-sm" @click="edicion = null">{{ t('plataformaPanel.facturacion.cancelar') }}</button>
        </div>
      </form>

      <section class="card" aria-labelledby="f-fuera" data-test="fact-fuera">
        <h2 id="f-fuera" class="text-base font-semibold text-gray-900 mb-1">{{ t('plataformaPanel.facturacion.fuera') }}</h2>
        <p class="text-xs text-gray-500 mb-2">{{ t('plataformaPanel.facturacion.fueraNota') }}</p>
        <ul class="grid grid-cols-2 sm:grid-cols-3 gap-2 text-sm">
          <li v-for="(n, k) in sim.fuera_del_calculo" :key="k" :data-fuera="k">{{ t('plataformaPanel.facturacion.motivo.' + k) }}: <strong class="tabular-nums">{{ n }}</strong></li>
        </ul>
      </section>

      <TarjetaSinConectar id="facturacion" :titulo="t('plataformaPanel.facturacion.cobrosReales')" :falta="t('plataformaPanel.faltaFacturacion')" />
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import TarjetaSinConectar from '@/panel-maestro/TarjetaSinConectar.vue'
import { usePlataformaStore } from '@/stores/plataforma'

const { t, locale } = useI18n()
const pm = usePlataformaStore()
const estado = ref<'cargando' | 'ok' | 'error'>('cargando')
const sim = ref<any | null>(null)
const aviso = ref(''); const error = ref(''); const ocupado = ref(false)
const edicion = ref<{ clave: string; nombre: string; mensual: string; anual: string; moneda: string } | null>(null)

function dinero(c: number | null | undefined, moneda: string | null | undefined): string | null {
  if (c === null || c === undefined || !moneda) return null
  try { return new Intl.NumberFormat(locale.value, { style: 'currency', currency: moneda }).format(c / 100) } catch { return `${(c / 100).toFixed(2)} ${moneda}` }
}
const totalTexto = computed(() => {
  const m = Object.entries(sim.value?.ingreso_mensual_por_moneda ?? {}) as [string, number][]
  return m.length ? m.map(([mon, c]) => dinero(c, mon)).join(' + ') : '0'
})

const impFilas = ref<{ region: string; concepto: string; tasa: string; incluido: '' | 'si' | 'no'; activo: boolean }[]>([])
const impError = ref(''); const impAviso = ref('')
const filasDeImpuestos = (reglas: any[]) => (reglas ?? []).map(r => ({ region: r.region, concepto: r.concepto, tasa: String(r.tasa_pct), incluido: (r.incluido_en_precio === true ? 'si' : r.incluido_en_precio === false ? 'no' : '') as '' | 'si' | 'no', activo: !!r.activo }))
async function cargar() {
  try { sim.value = await pm.llamar({ accion: 'facturacion_simulacion' }); impFilas.value = filasDeImpuestos(sim.value?.impuestos?.reglas); estado.value = 'ok' } catch { estado.value = 'error' }
}
async function guardarImpuestos() {
  impError.value = ''; impAviso.value = ''
  const reglas: Record<string, unknown>[] = []
  for (const f of impFilas.value) {
    const tasa = Number(f.tasa.trim().replace(',', '.'))
    if (!f.tasa.trim() || !Number.isFinite(tasa)) { impError.value = t('plataformaPanel.facturacion.imp.tasaNoValida'); return }
    reglas.push({ region: f.region, concepto: f.concepto, tasa_pct: tasa, activo: f.activo, incluido_en_precio: f.incluido === '' ? null : f.incluido === 'si' })
  }
  ocupado.value = true
  try { await pm.llamar({ accion: 'impuestos_guardar', reglas }); await cargar(); impAviso.value = t('plataformaPanel.facturacion.imp.guardado') } catch (x) { impError.value = (x as Error).message } finally { ocupado.value = false }
}
const aTexto = (c: number | null) => (c === null ? '' : String(c / 100))
function editar(p: any) { aviso.value = ''; error.value = ''; edicion.value = { clave: p.clave, nombre: p.nombre, mensual: aTexto(p.precio_mensual_centimos), anual: aTexto(p.precio_anual_centimos), moneda: p.moneda ?? '' } }
const aCentimos = (v: string): number | null | undefined => {
  const s = v.trim().replace(',', '.')
  if (!s) return null
  const n = Number(s)
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) : undefined
}
async function guardar() {
  const e = edicion.value; if (!e) return
  aviso.value = ''; error.value = ''
  const mensual = aCentimos(e.mensual), anual = aCentimos(e.anual)
  if (mensual === undefined || anual === undefined) { error.value = t('plataformaPanel.facturacion.precioNoValido'); return }
  ocupado.value = true
  try {
    await pm.llamar({ accion: 'plan_precio_fijar', plan: e.clave, precio_mensual_centimos: mensual, precio_anual_centimos: anual, moneda: e.moneda })
    edicion.value = null
    await cargar()
    aviso.value = t('plataformaPanel.facturacion.guardado')
  } catch (x) { error.value = (x as Error).message } finally { ocupado.value = false }
}
onMounted(cargar)
</script>
