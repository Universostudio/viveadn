<template>
  <section class="card space-y-4" :aria-labelledby="idTitulo" data-test="tabla-inquilinos">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <h2 :id="idTitulo" class="text-base font-semibold text-gray-900">{{ titulo }}</h2>
      <slot name="cabecera" />
    </div>

    <div class="flex flex-wrap items-end gap-3">
      <div class="flex-1 min-w-[12rem]">
        <label :for="idBuscar" class="block text-xs font-medium text-gray-600 mb-1">{{ t('panelMaestro.tabla.buscar') }}</label>
        <div class="relative">
          <Search class="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2" aria-hidden="true" />
          <input :id="idBuscar" v-model="texto" type="search" autocomplete="off" :placeholder="t('panelMaestro.tabla.buscarEjemplo')"
            class="w-full text-sm border border-gray-200 rounded-lg pl-9 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-adn-verde" data-test="buscar" />
        </div>
      </div>
      <div role="group" :aria-label="t('panelMaestro.tabla.filtros')" class="flex flex-wrap gap-2">
        <button v-for="f in FILTROS" :key="f" type="button" :aria-pressed="filtro === f" :data-filtro="f" @click="filtro = f"
          :class="['text-xs px-3 py-2 rounded-full border focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde',
            filtro === f ? 'bg-adn-verde text-white border-adn-verde' : 'bg-white text-gray-700 border-gray-200 hover:border-adn-verde']">
          {{ t('panelMaestro.tabla.filtro.' + f) }} <span class="opacity-75">({{ cuentas[f] }})</span>
        </button>
      </div>
    </div>

    <p role="status" class="sr-only">{{ t('panelMaestro.tabla.resultados', { n: filtrados.length }, filtrados.length) }}</p>

    <p v-if="!filtrados.length" class="text-sm text-gray-400 py-6 text-center" data-test="sin-resultados">{{ vacio ?? t('panelMaestro.tabla.sinResultados') }}</p>

    <template v-else>
      <!-- Escritorio: tabla -->
      <div class="hidden md:block overflow-x-auto">
        <table class="w-full text-sm">
          <caption class="sr-only">{{ titulo }}</caption>
          <thead class="text-left text-xs text-gray-500 border-b border-gray-100">
            <tr>
              <th scope="col" class="py-2 pr-3 font-medium">{{ etiquetaNombre ?? t('panelMaestro.tabla.columna.nombre') }}</th>
              <th scope="col" class="py-2 pr-3 font-medium">{{ t('panelMaestro.tabla.columna.plan') }}</th>
              <th scope="col" class="py-2 pr-3 font-medium">{{ t('panelMaestro.tabla.columna.estado') }}</th>
              <th scope="col" class="py-2 pr-3 font-medium text-right">{{ t('panelMaestro.tabla.columna.miembros') }}</th>
              <th scope="col" class="py-2 pr-3 font-medium">{{ t('panelMaestro.tabla.columna.modulos') }}</th>
              <th scope="col" class="py-2 font-medium text-right">{{ t('panelMaestro.tabla.columna.acciones') }}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-50">
            <tr v-for="i in visibles" :key="i.id" :data-inquilino="i.id">
              <td class="py-3 pr-3">
                <div class="flex items-center gap-3">
                  <span class="w-9 h-9 rounded-lg bg-adn-arena text-adn-profundo flex items-center justify-center font-bold flex-shrink-0" aria-hidden="true">{{ inicial(i) }}</span>
                  <div class="min-w-0">
                    <p class="font-medium text-gray-900 truncate">{{ i.nombre }} <span v-if="i.demo" class="ml-1 text-xs bg-adn-arena text-adn-profundo px-2 py-0.5 rounded-full">{{ t('panelMaestro.tabla.demo') }}</span></p>
                    <p class="text-xs text-gray-400 truncate">{{ i.subtitulo }}</p>
                  </div>
                </div>
              </td>
              <td class="py-3 pr-3"><span v-if="i.plan" class="text-xs bg-gray-100 text-gray-700 px-2 py-0.5 rounded-full">{{ i.plan.nombre }}</span></td>
              <td class="py-3 pr-3">
                <span class="inline-flex items-center gap-1.5 text-xs font-medium"><span :class="['w-2 h-2 rounded-full', punto(i)]" aria-hidden="true"></span>{{ i.estadoEtiqueta }}</span>
                <p v-if="i.detalleEstado" :class="['text-xs mt-0.5', i.detalleUrgente ? 'text-red-700 font-medium' : 'text-gray-400']">{{ i.detalleEstado }}</p>
              </td>
              <td class="py-3 pr-3 text-right tabular-nums">{{ i.miembros.toLocaleString(locale) }}</td>
              <td class="py-3 pr-3">
                <ul class="flex flex-wrap gap-1" :aria-label="t('panelMaestro.tabla.columna.modulos')">
                  <li v-for="m in i.modulos.slice(0, 4)" :key="m.clave" :class="['text-xs px-2 py-0.5 rounded-full border', m.activo ? 'bg-green-50 text-green-800 border-green-200' : 'bg-white text-gray-400 border-gray-200']">
                    {{ m.nombre }}<span class="sr-only"> ({{ t(m.activo ? 'comun.activo' : 'comun.inactivo') }})</span>
                  </li>
                  <li v-if="i.modulos.length > 4" class="text-xs text-gray-400 px-1">+{{ i.modulos.length - 4 }}</li>
                </ul>
              </td>
              <td class="py-3 text-right whitespace-nowrap">
                <template v-for="a in acciones(i)" :key="a.clave">
                  <RouterLink v-if="a.ruta" :to="a.ruta" :data-accion="a.clave" :class="enlace(a)">{{ a.etiqueta }}<span class="sr-only"> {{ i.nombre }}</span></RouterLink>
                  <button v-else type="button" :data-accion="a.clave" :class="enlace(a)" @click="emit('accion', a.clave, i)">{{ a.etiqueta }}<span class="sr-only"> {{ i.nombre }}</span></button>
                </template>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Móvil: una tarjeta por fila -->
      <ul class="md:hidden space-y-3">
        <li v-for="i in visibles" :key="i.id" :data-inquilino="i.id" class="border border-gray-100 rounded-xl p-3 space-y-2">
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <p class="font-medium text-gray-900 truncate">{{ i.nombre }} <span v-if="i.demo" class="ml-1 text-xs bg-adn-arena text-adn-profundo px-2 py-0.5 rounded-full">{{ t('panelMaestro.tabla.demo') }}</span></p>
              <p class="text-xs text-gray-400 truncate">{{ i.subtitulo }}</p>
            </div>
            <span v-if="i.plan" class="text-xs bg-gray-100 text-gray-700 px-2 py-0.5 rounded-full flex-shrink-0">{{ i.plan.nombre }}</span>
          </div>
          <p class="text-xs flex flex-wrap items-center gap-x-3 gap-y-1">
            <span class="inline-flex items-center gap-1.5 font-medium"><span :class="['w-2 h-2 rounded-full', punto(i)]" aria-hidden="true"></span>{{ i.estadoEtiqueta }}</span>
            <span v-if="i.detalleEstado" :class="i.detalleUrgente ? 'text-red-700 font-medium' : 'text-gray-400'">{{ i.detalleEstado }}</span>
            <span class="text-gray-500">{{ t('panelMaestro.tabla.miembrosN', { n: i.miembros.toLocaleString(locale) }, i.miembros) }}</span>
          </p>
          <div class="flex flex-wrap gap-2 pt-1">
            <template v-for="a in acciones(i)" :key="a.clave">
              <RouterLink v-if="a.ruta" :to="a.ruta" :class="enlaceMovil(a)">{{ a.etiqueta }}<span class="sr-only"> {{ i.nombre }}</span></RouterLink>
              <button v-else type="button" :class="enlaceMovil(a)" @click="emit('accion', a.clave, i)">{{ a.etiqueta }}<span class="sr-only"> {{ i.nombre }}</span></button>
            </template>
          </div>
        </li>
      </ul>

      <div v-if="filtrados.length > limite" class="text-center">
        <button type="button" class="btn-secondary text-sm" @click="limite += TAMANO" data-test="mostrar-mas">{{ t('panelMaestro.tabla.mostrarMas', { n: filtrados.length - limite }) }}</button>
      </div>
    </template>
  </section>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Search } from '@lucide/vue'
import { useI18n } from 'vue-i18n'
import { FILTROS, contarPorFiltro, filtrarInquilinos } from './filtros'
import type { AccionInquilino, FiltroInquilinos, Inquilino } from './tipos'

const TAMANO = 25
const props = withDefaults(defineProps<{
  titulo: string
  inquilinos: Inquilino[]
  acciones: (i: Inquilino) => AccionInquilino[]
  busquedaInicial?: string
  filtroInicial?: FiltroInquilinos
  vacio?: string
  /** Título de la primera columna; por defecto «Nombre» */
  etiquetaNombre?: string
  id?: string
}>(), { busquedaInicial: '', filtroInicial: 'todas' })
const emit = defineEmits<{ (e: 'accion', clave: string, inquilino: Inquilino): void }>()

const { t, locale } = useI18n()
const idTitulo = `ti-${props.id ?? 'tabla'}`
const idBuscar = `ti-buscar-${props.id ?? 'tabla'}`
const texto = ref(props.busquedaInicial)
const filtro = ref<FiltroInquilinos>(props.filtroInicial)
const limite = ref(TAMANO)

// La búsqueda de la barra superior cambia la consulta de la ruta: la tabla la sigue
watch(() => props.busquedaInicial, v => { texto.value = v })
watch([texto, filtro], () => { limite.value = TAMANO })

const cuentas = computed(() => contarPorFiltro(props.inquilinos))
const filtrados = computed(() => filtrarInquilinos(props.inquilinos, filtro.value, texto.value))
const visibles = computed(() => filtrados.value.slice(0, limite.value))

const inicial = (i: Inquilino) => i.nombre.trim()[0]?.toUpperCase() ?? '?'
const punto = (i: Inquilino) => i.estado === 'activa' ? 'bg-green-500' : i.estado === 'prueba' ? 'bg-amber-500' : i.estado === 'suspendida' ? 'bg-red-500' : 'bg-gray-400'
const enlace = (a: AccionInquilino) => ['text-xs px-2 py-1 rounded hover:underline focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde', a.variante === 'peligro' ? 'text-red-700' : 'text-adn-verde']
const enlaceMovil = (a: AccionInquilino) => ['text-xs px-3 py-2 rounded-lg border focus:outline-none focus-visible:ring-2 focus-visible:ring-adn-verde', a.variante === 'peligro' ? 'text-red-700 border-red-200' : 'text-adn-verde border-gray-200']
</script>
