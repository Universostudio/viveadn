<template>
  <div class="min-h-screen bg-gradient-to-br from-adn-verde to-adn-oscuro flex items-center justify-center p-4">
    <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-8 text-center">
      <p v-if="estado === 'cargando'" class="text-gray-500 text-sm" role="status">{{ t('comun.cargando') }}</p>

      <template v-else-if="estado === 'valido' || estado === 'revocado'">
        <component :is="estado === 'valido' ? ShieldCheck : ShieldAlert" :class="['w-14 h-14 mx-auto mb-3', estado === 'valido' ? 'text-green-600' : 'text-red-500']" aria-hidden="true" />
        <h1 class="text-xl font-bold text-gray-900">{{ t('verificar.' + estado) }}</h1>
        <p class="text-sm text-gray-500 mt-1">{{ t('verificar.' + estado + 'Texto') }}</p>
        <dl class="mt-6 text-left divide-y divide-gray-100 text-sm">
          <div v-if="datos.titular" class="py-3"><dt class="text-xs text-gray-500">{{ t('verificar.titular') }}</dt><dd class="font-semibold text-gray-900 mt-0.5">{{ datos.titular }}</dd></div>
          <div class="py-3"><dt class="text-xs text-gray-500">{{ t('verificar.programa') }}</dt><dd class="font-semibold text-gray-900 mt-0.5">{{ datos.programa }}</dd></div>
          <div class="py-3"><dt class="text-xs text-gray-500">{{ t('verificar.iglesia') }}</dt><dd class="font-semibold text-gray-900 mt-0.5">{{ datos.iglesia }}</dd></div>
          <div class="py-3"><dt class="text-xs text-gray-500">{{ t('verificar.emitido') }}</dt><dd class="font-semibold text-gray-900 mt-0.5">{{ fecha(datos.emitido_en) }}</dd></div>
        </dl>
      </template>

      <template v-else-if="estado === 'noEncontrado'">
        <ShieldQuestion class="w-14 h-14 mx-auto mb-3 text-amber-500" aria-hidden="true" />
        <h1 class="text-xl font-bold text-gray-900">{{ t('verificar.noEncontrado') }}</h1>
        <p class="text-sm text-gray-500 mt-1">{{ t('verificar.noEncontradoTexto') }}</p>
      </template>

      <template v-else>
        <TriangleAlert class="w-14 h-14 mx-auto mb-3 text-amber-500" aria-hidden="true" />
        <h1 class="text-xl font-bold text-gray-900">{{ t('verificar.error') }}</h1>
        <p class="text-sm text-gray-500 mt-1">{{ t('verificar.errorTexto') }}</p>
      </template>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ShieldAlert, ShieldCheck, ShieldQuestion, TriangleAlert } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { formatoFecha } from '@/i18n'

const { t } = useI18n()
const route = useRoute()
const estado = ref<'cargando' | 'valido' | 'revocado' | 'noEncontrado' | 'error'>('cargando')
const datos = ref<{ titular?: string; programa?: string; iglesia?: string; emitido_en?: string }>({})
const fecha = (f?: string) => (f ? formatoFecha(f, { dateStyle: 'long' }) : '')

// La direccion lleva el codigo del certificado: que no se indexe ni se pase a otros sitios
const metas: HTMLMetaElement[] = []
function meta(nombre: string, contenido: string) {
  const m = document.createElement('meta')
  m.name = nombre
  m.content = contenido
  document.head.appendChild(m)
  metas.push(m)
}

async function codigoDe(err: unknown): Promise<string> {
  try {
    const resp = (err as { context?: Response })?.context
    if (resp?.json) return (await resp.json()).error ?? ''
  } catch { /* sin detalle */ }
  return ''
}

onMounted(async () => {
  meta('robots', 'noindex, nofollow')
  meta('referrer', 'no-referrer')
  const { data, error } = await supabase.functions.invoke('verificar-certificado', { body: { codigo: String(route.params.codigo ?? '') } })
  if (error) { estado.value = (await codigoDe(error)) === 'no_valido' ? 'noEncontrado' : 'error'; return }
  if (data?.estado !== 'valido' && data?.estado !== 'revocado') { estado.value = 'noEncontrado'; return }
  datos.value = data
  estado.value = data.estado
})
onBeforeUnmount(() => metas.forEach(m => m.remove()))
</script>
