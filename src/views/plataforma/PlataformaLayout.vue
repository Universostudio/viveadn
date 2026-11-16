<template>
  <PanelShell :producto="'Vive ADN'" marca="V" :etiqueta="t('plataformaPanel.etiqueta')" :grupos="grupos"
    :usuario="{ nombre: auth.nombreCompleto || auth.user?.email || '', rol: t('plataformaPanel.rol') }"
    :buscador="t('plataformaPanel.buscar')" :seccion="seccion" @salir="salir" @buscar="buscar">
    <template #pie>
      <button v-if="auth.tieneIglesia" type="button" data-test="entrar-iglesia" @click="entrarAMiIglesia"
        class="w-full inline-flex items-center gap-2 text-sm text-adn-verde border border-adn-verde/30 rounded-lg px-3 py-2 hover:bg-adn-arena focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde">
        <Church class="w-4 h-4 flex-shrink-0" aria-hidden="true" />
        <span class="text-left">{{ t('plataformaPanel.contexto.entrar', { iglesia: auth.nombreIglesia }) }}</span>
      </button>
      <SelectorIdioma id="selector-idioma-panel" class="px-3" ocultar-etiqueta />
      <PieLegal class="px-3" />
    </template>

    <div class="p-4 sm:p-6 space-y-6">
      <p v-if="pm.aviso" role="status" data-test="aviso"
        :class="['text-sm px-4 py-3 rounded-lg border', pm.aviso.error ? 'bg-red-50 text-red-700 border-red-200' : 'bg-green-50 text-green-700 border-green-200']">{{ pm.aviso.texto() }}</p>
      <RouterView />
    </div>
  </PanelShell>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { Activity, Church, CirclePlus, KeyRound, LayoutDashboard, LifeBuoy, Layers, Receipt, Timer } from '@lucide/vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PanelShell from '@/panel-maestro/PanelShell.vue'
import type { GrupoMenu } from '@/panel-maestro/tipos'
import SelectorIdioma from '@/components/SelectorIdioma.vue'
import PieLegal from '@/components/PieLegal.vue'
import { useAuthStore } from '@/stores/auth'
import { usePlataformaStore } from '@/stores/plataforma'

const { t } = useI18n()
const auth = useAuthStore()
const pm = usePlataformaStore()
const route = useRoute()
const router = useRouter()

onMounted(() => { void pm.asegurarCargada() })

const seccion = computed(() => {
  const s = route.meta.seccion as string | undefined
  // La portada ya es el Panel Maestro: no se repite en la ruta
  return s && s !== 'portada' ? t('plataformaPanel.menu.' + s) : ''
})

// Contadores del menú: salen de la misma lista que ya carga el panel, sin consultas aparte
const contadorIglesias = computed(() => pm.visibles.length || null)
const contadorPruebas = computed(() => pm.visibles.filter(i => (i.etapa ?? (i.activa ? 'activa' : 'suspendida')) === 'prueba' && !i.es_demo).length || null)

const grupos = computed<GrupoMenu[]>(() => [
  { titulo: t('plataformaPanel.grupo.control'), items: [
    { to: '/plataforma', etiqueta: t('plataformaPanel.menu.portada'), icono: LayoutDashboard, exacto: true },
    { to: '/plataforma/iglesias', etiqueta: t('plataformaPanel.menu.iglesias'), icono: Church, contador: contadorIglesias.value },
    { to: '/plataforma/nueva-iglesia', etiqueta: t('plataformaPanel.menu.nueva'), icono: CirclePlus },
  ] },
  { titulo: t('plataformaPanel.grupo.negocio'), items: [
    { to: '/plataforma/pruebas', etiqueta: t('plataformaPanel.menu.pruebas'), icono: Timer, contador: contadorPruebas.value },
    { to: '/plataforma/planes', etiqueta: t('plataformaPanel.menu.planes'), icono: Layers },
    { to: '/plataforma/facturacion', etiqueta: t('plataformaPanel.menu.facturacion'), icono: Receipt, sinConectar: true },
  ] },
  { titulo: t('plataformaPanel.grupo.sistema'), items: [
    { to: '/plataforma/registro', etiqueta: t('plataformaPanel.menu.registro'), icono: KeyRound },
    { to: '/plataforma/sistema', etiqueta: t('plataformaPanel.menu.sistema'), icono: Activity },
  ] },
  { titulo: t('plataformaPanel.grupo.soporte'), items: [
    { to: '/plataforma/soporte', etiqueta: t('plataformaPanel.menu.soporte'), icono: LifeBuoy, sinConectar: true },
  ] },
])

function buscar(texto: string) {
  router.push({ name: 'pm-iglesias', query: texto ? { q: texto } : {} })
}

function entrarAMiIglesia() {
  auth.fijarContexto('iglesia')
  router.push({ name: 'dashboard' })
}

async function salir() {
  await auth.logout()
  pm.limpiar()
  router.push('/login')
}
</script>
