<template>
  <div class="flex h-[100dvh] bg-adn-arena overflow-hidden">
    <a href="#panel-contenido" class="sr-only focus:not-sr-only focus:absolute focus:z-50 focus:bg-white focus:px-3 focus:py-2 focus:rounded">{{ t('panelMaestro.saltar') }}</a>

    <div v-if="abierto" class="fixed inset-0 bg-black/40 z-30 lg:hidden" @click="cerrar" aria-hidden="true"></div>

    <aside :id="idMenu" :class="['fixed inset-y-0 left-0 z-40 w-64 bg-white border-r border-gray-100 flex flex-col shadow-sm transition-transform duration-200',
        'lg:static lg:translate-x-0 lg:flex-shrink-0', abierto ? 'translate-x-0' : '-translate-x-full']"
      :aria-label="etiqueta" @keydown.esc="cerrar">
      <div class="px-5 py-5 border-b border-gray-100 flex items-center gap-3">
        <div class="w-9 h-9 bg-adn-verde rounded-lg flex items-center justify-center flex-shrink-0"><span class="text-white text-lg font-bold" aria-hidden="true">{{ marca }}</span></div>
        <div class="min-w-0">
          <p class="font-display font-bold text-adn-verde text-sm leading-tight truncate">{{ producto }}</p>
          <p class="text-xs font-medium text-adn-profundo bg-adn-arena inline-block px-2 py-0.5 rounded-full mt-0.5" data-test="etiqueta-panel">{{ etiqueta }}</p>
        </div>
      </div>

      <nav class="flex-1 px-3 py-4 overflow-y-auto space-y-4" :aria-label="etiqueta">
        <div v-for="g in grupos" :key="g.titulo">
          <p class="px-3 text-[11px] font-semibold uppercase tracking-wide text-gray-500 mb-1">{{ g.titulo }}</p>
          <ul class="space-y-1">
            <li v-for="item in g.items" :key="item.to">
              <RouterLink :to="item.to" custom v-slot="{ href, isActive, isExactActive, navigate }">
                <a :href="href" @click="navigate" :aria-current="(item.exacto ? isExactActive : isActive) ? 'page' : undefined"
                  :class="['nav-item', (item.exacto ? isExactActive : isActive) ? 'active' : '']" :data-nav="item.to">
                  <component :is="item.icono" class="w-5 h-5 flex-shrink-0" aria-hidden="true" />
                  <span class="text-sm font-medium flex-1 min-w-0 truncate">{{ item.etiqueta }}</span>
                  <span v-if="item.contador" class="bg-adn-oro text-adn-profundo text-xs rounded-full px-2 py-0.5 font-bold">{{ item.contador }}<span class="sr-only"> {{ t('panelMaestro.pendientes') }}</span></span>
                  <span v-else-if="item.sinConectar" class="text-[10px] text-gray-500 border border-gray-200 rounded-full px-1.5 py-0.5">{{ t('panelMaestro.sinConectarCorto') }}</span>
                </a>
              </RouterLink>
            </li>
          </ul>
        </div>
      </nav>

      <div class="px-3 py-4 border-t border-gray-100 space-y-3">
        <slot name="pie" />
        <div class="flex items-center gap-3 px-3">
          <div class="w-8 h-8 bg-adn-oro rounded-full flex items-center justify-center flex-shrink-0"><span class="text-white text-sm font-bold" aria-hidden="true">{{ usuario.nombre[0]?.toUpperCase() ?? 'U' }}</span></div>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-gray-900 truncate">{{ usuario.nombre }}</p>
            <p class="text-xs text-gray-500 truncate">{{ usuario.rol }}</p>
          </div>
          <button type="button" @click="emit('salir')" class="text-gray-500 hover:text-red-600 p-1 rounded focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde" :title="t('panelMaestro.salir')" :aria-label="t('panelMaestro.salir')">
            <LogOut class="w-5 h-5" aria-hidden="true" />
          </button>
        </div>
      </div>
    </aside>

    <div class="flex-1 flex flex-col min-w-0">
      <header class="flex items-center gap-3 px-4 py-3 bg-white border-b border-gray-100 flex-shrink-0">
        <button type="button" ref="botonMenu" @click="abierto = true" class="lg:hidden w-10 h-10 -ml-2 flex items-center justify-center rounded-lg text-adn-verde hover:bg-adn-arena focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde"
          :aria-label="t('panelMaestro.abrirMenu')" :aria-expanded="abierto" :aria-controls="idMenu"><Menu class="w-6 h-6" aria-hidden="true" /></button>
        <p class="text-sm text-gray-500 hidden sm:block min-w-0 truncate" data-test="ruta-panel"><span class="font-medium text-gray-700">{{ etiqueta }}</span><template v-if="seccion"><span class="mx-1.5" aria-hidden="true">/</span>{{ seccion }}</template></p>
        <form role="search" class="flex-1 max-w-md ml-auto" @submit.prevent="buscar">
          <label for="panel-buscar" class="sr-only">{{ buscador }}</label>
          <div class="relative">
            <Search class="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2" aria-hidden="true" />
            <input id="panel-buscar" v-model="consulta" type="search" autocomplete="off" :placeholder="buscador" data-test="buscador-global"
              class="w-full text-sm border border-gray-200 rounded-lg pl-9 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
        </form>
        <p class="text-xs text-gray-500 hidden md:block flex-shrink-0">{{ fechaTexto }}</p>
      </header>

      <main id="panel-contenido" tabindex="-1" class="flex-1 overflow-y-auto focus:outline-none">
        <slot />
      </main>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import { LogOut, Menu, Search } from '@lucide/vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import type { GrupoMenu } from './tipos'

const props = defineProps<{
  /** Nombre del producto, junto a la marca */
  producto: string
  /** Inicial de la marca */
  marca: string
  /** Etiqueta del panel: «Panel Maestro» */
  etiqueta: string
  grupos: GrupoMenu[]
  usuario: { nombre: string; rol: string }
  buscador: string
  /** Nombre de la sección actual, para la ruta de la barra superior */
  seccion?: string
}>()
const emit = defineEmits<{ (e: 'salir'): void; (e: 'buscar', texto: string): void }>()

const { t, locale } = useI18n()
const route = useRoute()
const abierto = ref(false)
const consulta = ref('')
const botonMenu = ref<HTMLButtonElement | null>(null)
const idMenu = 'panel-menu'

const fechaTexto = computed(() => new Date().toLocaleDateString(locale.value, { weekday: 'long', day: 'numeric', month: 'long' }))

function cerrar() {
  const estabaAbierto = abierto.value
  abierto.value = false
  // El foco vuelve al botón que abrió el menú
  if (estabaAbierto) nextTick(() => botonMenu.value?.focus())
}
function buscar() { emit('buscar', consulta.value.trim()) }

// Cierra el cajón al navegar y lleva el foco al contenido para quien usa teclado o lector de pantalla
watch(() => route.fullPath, () => {
  abierto.value = false
  nextTick(() => document.getElementById('panel-contenido')?.focus({ preventScroll: true }))
})
void props
</script>
