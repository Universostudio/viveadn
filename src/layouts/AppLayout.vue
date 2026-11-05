<template>
  <div class="flex h-[100dvh] bg-adn-arena overflow-hidden">
    <!-- Fondo oscuro del menú en móvil -->
    <div
      v-if="menuAbierto"
      class="fixed inset-0 bg-black/40 z-30 lg:hidden"
      @click="menuAbierto = false"
    ></div>

    <!-- Sidebar: menú deslizable en móvil, fija en escritorio -->
    <aside
      :class="[
        'fixed inset-y-0 left-0 z-40 w-64 bg-white border-r border-gray-100 flex flex-col shadow-sm transition-transform duration-200',
        'lg:static lg:translate-x-0 lg:flex-shrink-0',
        menuAbierto ? 'translate-x-0' : '-translate-x-full'
      ]"
    >
      <!-- Logo -->
      <div class="px-6 py-5 border-b border-gray-100">
        <div class="flex items-center gap-3">
          <div class="w-9 h-9 bg-adn-verde rounded-lg flex items-center justify-center">
            <span class="text-white text-lg font-bold">V</span>
          </div>
          <div>
            <p class="font-display font-bold text-adn-verde text-sm leading-tight">ViveADN</p>
            <p class="text-xs text-gray-400">{{ iglesiaName }}</p>
          </div>
        </div>
      </div>

      <!-- Navegación -->
      <nav class="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
        <RouterLink v-for="item in navItems" :key="item.to" :to="item.to" custom v-slot="{ href, isActive, isExactActive, navigate }">
          <a :href="href" @click="navigate" :aria-current="(item.to === '/' ? isExactActive : isActive) ? 'page' : undefined"
            :class="['nav-item', (item.to === '/' ? isExactActive : isActive) ? 'active' : '']">
            <component :is="item.icon" class="w-5 h-5 flex-shrink-0" aria-hidden="true" />
            <span class="text-sm font-medium">{{ t(item.label) }}</span>
            <!-- Badge alerta consolidación -->
            <span v-if="item.badge && consolidacionPendientes > 0"
              class="ml-auto bg-red-500 text-white text-xs rounded-full px-2 py-0.5 font-bold">
              {{ consolidacionPendientes }}
            </span>
          </a>
        </RouterLink>
      </nav>

      <!-- Usuario -->
      <div class="px-3 py-4 border-t border-gray-100">
        <div class="flex items-center gap-3 px-3 py-2">
          <div class="w-8 h-8 bg-adn-oro rounded-full flex items-center justify-center flex-shrink-0">
            <span class="text-white text-sm font-bold">{{ inicial }}</span>
          </div>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-gray-900 truncate">{{ nombreCompleto }}</p>
            <p class="text-xs text-gray-400 truncate capitalize">{{ rol }}</p>
          </div>
          <button @click="logout" class="text-gray-400 hover:text-red-500 transition-colors" :title="t('menu.salir')" :aria-label="t('menu.salir')">
            <LogOut class="w-5 h-5" aria-hidden="true" />
          </button>
        </div>
        <div v-if="auth.rolesDisponibles.length" class="px-3 pt-2">
          <label for="ver-como" class="block text-xs text-gray-500 mb-1">{{ t('verComo.etiqueta') }}</label>
          <select id="ver-como" :value="auth.verComo?.clave ?? ''" @change="auth.simularRol(($event.target as HTMLSelectElement).value || null)"
            class="w-full text-xs border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-adn-verde">
            <option value="">{{ t('verComo.ninguno') }}</option>
            <option v-for="r in auth.rolesDisponibles" :key="r.clave" :value="r.clave">{{ r.nombre }}</option>
          </select>
        </div>
        <SelectorIdioma id="selector-idioma-menu" class="px-3 pt-2" ocultar-etiqueta />
      </div>
    </aside>

    <!-- Contenido principal -->
    <div class="flex-1 flex flex-col min-w-0">
      <!-- Barra superior (solo móvil) -->
      <header class="lg:hidden flex items-center gap-3 px-4 py-3 bg-white border-b border-gray-100 flex-shrink-0">
        <button
          @click="menuAbierto = true"
          class="w-10 h-10 -ml-2 flex items-center justify-center rounded-lg text-adn-verde hover:bg-adn-arena"
          :aria-label="t('menu.abrirMenu')"
        ><Menu class="w-6 h-6" aria-hidden="true" /></button>
        <p class="font-display font-bold text-adn-verde">ViveADN</p>
      </header>

      <div v-if="auth.verComo" role="status" class="bg-amber-100 text-amber-900 text-xs px-4 py-2 flex items-center justify-between gap-3 flex-wrap">
        <span>{{ t('verComo.aviso', { rol: auth.verComo.nombre }) }}</span>
        <button type="button" class="underline font-medium" @click="auth.simularRol(null)">{{ t('verComo.salir') }}</button>
      </div>
      <main class="flex-1 overflow-y-auto">
        <RouterView />
      </main>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch, type Component } from 'vue'
import {
  LayoutDashboard, Users, House, HeartHandshake, GraduationCap, MessageSquare,
  ChartColumn, CalendarDays, Settings, ShieldCheck, LogOut, Menu, Network,
} from '@lucide/vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import SelectorIdioma from '@/components/SelectorIdioma.vue'
import { useAuthStore } from '@/stores/auth'
import { supabase } from '@/lib/supabase'
import { haceHoras } from '@/lib/alertas'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()
const menuAbierto = ref(false)
const { t } = useI18n()

// Cierra el menú móvil al cambiar de página
watch(() => route.fullPath, () => { menuAbierto.value = false })

const nombreCompleto = computed(() => auth.nombreCompleto)
const rol = computed(() => auth.nombreRol)
const inicial = computed(() => auth.perfil?.nombre?.[0]?.toUpperCase() ?? 'U')
const iglesiaName = computed(() => auth.nombreIglesia)
const consolidacionPendientes = ref(0)

// Cada sección se muestra si el rol tiene alguno de sus permisos; label es la clave de traducción
const todosLosItems: { to: string; icon: Component; label: string; badge?: boolean; modulo?: string; plataforma?: boolean; red?: boolean; permisos: string[] }[] = [
  { to: '/',              icon: LayoutDashboard, label: 'menu.dashboard', permisos: [] },
  { to: '/miembros',      icon: Users, label: 'menu.miembros', permisos: ['miembros.ver', 'miembros.ver_asignados'] },
  { to: '/eventos',       icon: CalendarDays, label: 'menu.eventos', modulo: 'eventos', permisos: ['eventos.ver'] },
  { to: '/casas',         icon: House, label: 'menu.casas', permisos: ['casas.ver', 'casas.ver_propia'] },
  { to: '/consolidacion', icon: HeartHandshake, label: 'menu.consolidacion', badge: true, permisos: ['consolidacion.ver', 'consolidacion.ver_asignados', 'consolidacion.ver_casa'] },
  { to: '/formacion',     icon: GraduationCap, label: 'menu.formacion', permisos: ['formacion.ver'] },
  { to: '/comunicacion',  icon: MessageSquare, label: 'menu.comunicacion', modulo: 'comunicacion', permisos: ['miembros.ver'] },
  { to: '/reportes',      icon: ChartColumn, label: 'menu.reportes', permisos: ['reportes.ver'] },
  { to: '/configuracion', icon: Settings, label: 'menu.configuracion', permisos: ['usuarios.gestionar', 'roles.gestionar', 'iglesia.configurar'] },
  { to: '/red',            icon: Network, label: 'menu.red', red: true, permisos: [] },
  { to: '/plataforma',    icon: ShieldCheck, label: 'menu.plataforma', plataforma: true, permisos: [] },
]

const navItems = computed(() =>
  todosLosItems.filter(i =>
    (!i.plataforma || auth.esPlataforma) &&
    (!i.red || auth.tieneSedes) &&
    (!i.modulo || auth.tieneModulo(i.modulo)) &&
    (i.permisos.length === 0 || auth.can(...i.permisos))
  )
)

async function logout() {
  await auth.logout()
  router.push('/login')
}

onMounted(async () => {
  // Contar consolidaciones críticas (naranja + rojo)
  const { count } = await supabase
    .from('consolidaciones')
    .select('*', { count: 'exact', head: true })
    .lt('fecha_conversion', haceHoras(48))
    .eq('completado', false)

  consolidacionPendientes.value = count ?? 0
})
</script>
