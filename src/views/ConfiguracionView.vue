<template>
  <div class="p-4 sm:p-6 space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">{{ t('configuracion.titulo') }}</h1>
      <p class="text-gray-500 text-sm mt-0.5">{{ t('configuracion.subtitulo') }}</p>
    </div>

    <!-- Tabs -->
    <div class="flex gap-1 border-b border-gray-200">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        @click="tabActivo = tab.id"
        :class="['px-4 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px inline-flex items-center gap-2',
          tabActivo === tab.id
            ? 'border-adn-verde text-adn-verde'
            : 'border-transparent text-gray-500 hover:text-gray-700']"
      >
        <component :is="tab.icono" class="w-4 h-4" aria-hidden="true" /> {{ t(`configuracion.tabs.${tab.id}`) }}
      </button>
    </div>

    <!-- Tab: Perfil de la iglesia -->
    <div v-if="tabActivo === 'iglesia'" class="space-y-6">
      <div class="card space-y-4">
        <h2 class="text-lg font-semibold text-gray-900 mb-2 flex items-center gap-2"><Church class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('configuracion.identidad') }}</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('configuracion.nombreIglesia') }}</label>
            <input v-model="iglesia.nombre" type="text" :placeholder="t('configuracion.nombreIglesiaPlaceholder')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('configuracion.paisSede') }}</label>
            <input v-model="iglesia.pais" type="text" :placeholder="t('configuracion.ejemploPais')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('configuracion.ciudadSede') }}</label>
            <input v-model="iglesia.ciudad" type="text" :placeholder="t('configuracion.ejemploCiudad')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('configuracion.emailContacto') }}</label>
            <input v-model="iglesia.email" type="email" :placeholder="t('configuracion.ejemploEmailContacto')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
        </div>
        <p v-if="mensajeIglesia" class="text-sm text-gray-600">{{ t(mensajeIglesia) }}</p>
        <div class="flex justify-end">
          <button v-if="auth.can('iglesia.configurar')" @click="guardarIglesia" :disabled="guardando" class="btn-primary disabled:opacity-60">
            {{ guardando ? t('comun.guardando') : t('configuracion.guardarCambios') }}
          </button>
          <p v-else class="text-xs text-gray-400">{{ t('configuracion.sinPermisoIdentidad') }}</p>
        </div>
      </div>

      <!-- Apariencia -->
      <div class="card space-y-4">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><Palette class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('configuracion.apariencia') }}</h2>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <div v-for="color in paletaColores" :key="color.nombre" class="text-center">
            <div :style="{ backgroundColor: color.valor }" class="w-12 h-12 rounded-xl mx-auto mb-1 shadow-sm border border-gray-100"></div>
            <p class="text-xs font-medium text-gray-700">{{ t(color.nombre) }}</p>
            <p class="text-xs text-gray-400 font-mono">{{ color.valor }}</p>
          </div>
        </div>
        <p class="text-xs text-gray-400">{{ t('configuracion.paletaFutura') }}</p>
      </div>
    </div>

    <!-- Tab: Dar (fondos, apariencia y página pública) -->
    <ConfigDar v-if="tabActivo === 'dar'" />

    <!-- Tab: Usuarios y roles -->
    <div v-if="tabActivo === 'usuarios'" class="space-y-6">
      <div class="card">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><Users class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('configuracion.usuariosSistema') }}</h2>
          <button @click="abrirNuevoUsuario = true" class="btn-secondary text-sm">{{ t('configuracion.invitar') }}</button>
        </div>

        <div v-if="!usuarios.length" class="py-8 text-center text-gray-400 text-sm">
          {{ t('configuracion.cargandoUsuarios') }}
        </div>
        <div v-else class="divide-y divide-gray-50">
          <div v-for="u in usuarios" :key="u.id" class="flex items-center justify-between py-3">
            <div class="flex items-center gap-3">
              <div class="w-9 h-9 bg-adn-verde rounded-full flex items-center justify-center">
                <span class="text-white text-sm font-bold">{{ u.nombre?.[0] ?? '?' }}</span>
              </div>
              <div>
                <p class="text-sm font-medium text-gray-900">{{ u.nombre }} {{ u.apellido }}</p>
                <p class="text-xs text-gray-400">{{ u.email }}</p>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <span :class="['text-xs px-2 py-1 rounded-full font-medium', claseRol(u.rol)]">
                {{ etiquetaRol(u.rol) }}
              </span>
              <select
                v-if="auth.can('usuarios.gestionar') && u.rol !== 'propietario' && u.id !== auth.perfil?.id"
                :value="u.rol"
                @change="cambiarRol(u, ($event.target as HTMLSelectElement).value)"
                class="text-xs border border-gray-200 rounded-lg px-2 py-1 focus:outline-none focus:ring-2 focus:ring-adn-verde"
              >
                <option v-for="r in rolesAsignables" :key="r.clave" :value="r.clave">{{ r.nombre }}</option>
              </select>
            </div>
          </div>
        </div>
      </div>

      <!-- Descripción de roles -->
      <div class="card">
        <h2 class="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2"><ListChecks class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('configuracion.rolesDisponibles') }}</h2>
        <div class="space-y-3">
          <div v-for="rol in roles" :key="rol.id" class="flex items-start gap-3 p-3 bg-gray-50 rounded-xl">
            <span :class="['text-xs px-2 py-1 rounded-full font-medium flex-shrink-0 mt-0.5', claseRol(rol.clave)]">
              {{ rol.nombre }}
            </span>
            <div>
              <p class="text-sm text-gray-600">{{ rol.descripcion }}</p>
              <p class="text-xs text-gray-400 mt-1">
                {{ rol.es_propietario ? t('configuracion.todosPermisos') : t('configuracion.permisos', rol.rol_permisos.length) }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Tab: Integraciones -->
    <div v-if="tabActivo === 'integraciones'" class="space-y-6">
      <div v-for="integ in integraciones" :key="integ.id" class="card">
        <div class="flex items-start justify-between">
          <div class="flex items-start gap-3">
            <div class="w-11 h-11 rounded-lg bg-adn-verde/10 flex items-center justify-center flex-shrink-0">
              <component :is="integ.icono" class="w-6 h-6 text-adn-verde" aria-hidden="true" />
            </div>
            <div>
              <p class="font-semibold text-gray-900">{{ t(integ.nombre) }}</p>
              <p class="text-sm text-gray-500 mt-0.5">{{ t(integ.descripcion) }}</p>
            </div>
          </div>
          <span :class="['text-xs px-3 py-1.5 rounded-full font-medium', integ.activa ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500']">
            {{ integ.activa ? t('comun.activa') : t('configuracion.sinConectar') }}
          </span>
        </div>

        <div v-if="integ.configuracion" class="mt-4 space-y-3">
          <div v-for="campo in integ.configuracion" :key="campo.clave">
            <label class="block text-xs font-medium text-gray-600 mb-1">{{ t(campo.etiqueta) }}</label>
            <input
              :type="campo.tipo"
              :placeholder="te(campo.placeholder) ? t(campo.placeholder) : campo.placeholder"
              v-model="camposIntegracion[integ.id + '_' + campo.clave]"
              class="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde"
            />
          </div>
          <div class="flex justify-end">
            <button class="btn-secondary text-xs">{{ t('configuracion.guardarConfiguracion') }}</button>
          </div>
        </div>

        <div v-if="integ.nota" class="mt-3 bg-adn-arena rounded-lg px-3 py-2">
          <p class="text-xs text-adn-verde flex items-start gap-1.5"><Lightbulb class="w-3.5 h-3.5 flex-shrink-0 mt-0.5" aria-hidden="true" /> {{ t(integ.nota) }}</p>
        </div>
      </div>
    </div>

    <!-- Tab: Seguridad -->
    <div v-if="tabActivo === 'seguridad'" class="space-y-6">
      <div class="card space-y-4">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><KeyRound class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('configuracion.autenticacion') }}</h2>
        <div class="divide-y divide-gray-50">
          <div class="flex items-center justify-between py-3">
            <div>
              <p class="text-sm font-medium text-gray-900">{{ t('configuracion.dosFactores') }}</p>
              <p class="text-xs text-gray-500 mt-0.5">{{ t('configuracion.dosFactoresAyuda') }}</p>
            </div>
            <span class="text-xs bg-gray-100 text-gray-500 px-2 py-1 rounded-full font-medium">{{ t('configuracion.proximamente') }}</span>
          </div>
          <div class="flex items-center justify-between py-3">
            <div>
              <p class="text-sm font-medium text-gray-900">{{ t('configuracion.sesionesMaximas') }}</p>
              <p class="text-xs text-gray-500 mt-0.5">{{ t('configuracion.sesionesAyuda') }}</p>
            </div>
            <select class="text-sm border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option value="1">1</option>
              <option value="3" selected>3</option>
              <option value="5">5</option>
              <option value="sin_limite">{{ t('configuracion.sinLimite') }}</option>
            </select>
          </div>
          <div class="flex items-center justify-between py-3">
            <div>
              <p class="text-sm font-medium text-gray-900">{{ t('configuracion.tiempoSesion') }}</p>
              <p class="text-xs text-gray-500 mt-0.5">{{ t('configuracion.tiempoAyuda') }}</p>
            </div>
            <select class="text-sm border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option value="1h">{{ t('configuracion.horas', 1) }}</option>
              <option value="8h" selected>{{ t('configuracion.horas', 8) }}</option>
              <option value="24h">{{ t('configuracion.horas', 24) }}</option>
              <option value="7d">{{ t('configuracion.dias', 7) }}</option>
            </select>
          </div>
        </div>
      </div>

      <div class="card space-y-4">
        <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2"><Lock class="w-5 h-5 text-adn-verde" aria-hidden="true" /> {{ t('configuracion.privacidad') }}</h2>
        <div class="divide-y divide-gray-50">
          <div class="flex items-center justify-between py-3">
            <div>
              <p class="text-sm font-medium text-gray-900">{{ t('configuracion.cifrado') }}</p>
              <p class="text-xs text-gray-500 mt-0.5">{{ t('configuracion.cifradoAyuda') }}</p>
            </div>
            <span class="text-xs bg-green-100 text-green-700 px-2 py-1 rounded-full font-medium inline-flex items-center gap-1"><Check class="w-3.5 h-3.5" aria-hidden="true" /> {{ t('comun.activo') }}</span>
          </div>
          <div class="flex items-center justify-between py-3">
            <div>
              <p class="text-sm font-medium text-gray-900">{{ t('configuracion.consentimientos') }}</p>
              <p class="text-xs text-gray-500 mt-0.5">{{ t('configuracion.consentimientosAyuda') }}</p>
            </div>
            <span class="text-xs bg-gray-100 text-gray-500 px-2 py-1 rounded-full font-medium">{{ t('configuracion.proximamente') }}</span>
          </div>
          <div class="flex items-center justify-between py-3">
            <div>
              <p class="text-sm font-medium text-gray-900">{{ t('configuracion.copias') }}</p>
              <p class="text-xs text-gray-500 mt-0.5">{{ t('configuracion.copiasAyuda') }}</p>
            </div>
            <span class="text-xs bg-gray-100 text-gray-500 px-2 py-1 rounded-full font-medium">{{ t('configuracion.porConfigurar') }}</span>
          </div>
        </div>
      </div>

      <div class="card border border-red-100 bg-red-50/50">
        <h2 class="text-lg font-semibold text-red-700 mb-3 flex items-center gap-2"><TriangleAlert class="w-5 h-5" aria-hidden="true" /> {{ t('configuracion.zonaPeligrosa') }}</h2>
        <p class="text-sm text-red-600 mb-4">{{ t('configuracion.zonaPeligrosaTexto') }}</p>
        <div class="flex flex-wrap gap-3">
          <button class="text-sm px-4 py-2 border border-red-200 text-red-600 rounded-lg hover:bg-red-50 transition-colors">
            {{ t('configuracion.exportar') }}
          </button>
          <button class="text-sm px-4 py-2 border border-red-300 text-red-700 rounded-lg hover:bg-red-100 transition-colors font-medium">
            {{ t('configuracion.eliminarCuenta') }}
          </button>
        </div>
      </div>
    </div>

    <div v-if="tabActivo === 'usuarios' && invitaciones.length" class="card -mt-2">
      <h3 class="text-sm font-semibold text-gray-900 mb-3">{{ t('configuracion.invitacionesPendientes') }}</h3>
      <div class="divide-y divide-gray-50">
        <div v-for="i in invitaciones" :key="i.id" class="flex items-center justify-between gap-3 py-2 flex-wrap">
          <div class="min-w-0">
            <p class="text-sm font-medium text-gray-900 truncate">{{ i.nombre }} {{ i.apellido }} · {{ i.email }}</p>
            <p class="text-xs" :class="new Date(i.caduca_en) < new Date() ? 'text-red-600' : 'text-gray-400'">
              {{ new Date(i.caduca_en) < new Date() ? t('configuracion.caducada') : t('configuracion.caduca', { fecha: new Date(i.caduca_en).toLocaleDateString() }) }}
            </p>
          </div>
          <div class="flex gap-2">
            <button type="button" class="btn-secondary text-xs" @click="reenviarInvitacion(i.id)">{{ t('configuracion.nuevoEnlace') }}</button>
            <button type="button" class="btn-secondary text-xs" @click="revocarInvitacion(i.id)">{{ t('configuracion.revocar') }}</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal: enlace de invitación creado (se muestra una sola vez) -->
    <div v-if="enlaceCreado" class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50" @click.self="enlaceCreado = null">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-3">
        <h2 class="text-lg font-bold text-gray-900">{{ t('configuracion.enlaceListo') }}</h2>
        <p v-if="enlaceCreado.enviado" class="text-sm text-green-700">{{ t('configuracion.correoEnviado', { email: enlaceCreado.email }) }}</p>
        <p v-else class="text-sm text-amber-700">{{ t('configuracion.correoNoEnviado', { email: enlaceCreado.email }) }}</p>
        <p class="text-sm text-gray-600">{{ t('configuracion.enlaceAyuda', { email: enlaceCreado.email, dias: 15 }) }}</p>
        <input readonly :value="enlaceCreado.enlace" @focus="($event.target as HTMLInputElement).select()"
          class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-xs font-mono bg-gray-50" :aria-label="t('configuracion.enlaceListo')" />
        <p class="text-xs text-amber-700">{{ t('configuracion.enlaceUnaVez') }}</p>
        <div class="flex gap-3 pt-1">
          <button type="button" @click="copiarEnlace" class="btn-primary flex-1">{{ copiado ? t('configuracion.copiado') : t('configuracion.copiar') }}</button>
          <button type="button" @click="enlaceCreado = null" class="btn-secondary flex-1">{{ t('comun.cerrar') }}</button>
        </div>
      </div>
    </div>

    <!-- Modal: Invitar usuario -->
    <div
      v-if="abrirNuevoUsuario"
      class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center p-4 z-50"
      @click.self="abrirNuevoUsuario = false"
    >
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6">
        <h2 class="text-lg font-bold text-gray-900 mb-4">{{ t('configuracion.invitarTitulo') }}</h2>
        <form @submit.prevent="invitarUsuario" class="space-y-4">
          <div class="grid grid-cols-2 gap-3">
            <input v-model="nuevoUsuario.nombre" required maxlength="60" :placeholder="t('configuracion.nombre')" :aria-label="t('configuracion.nombre')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
            <input v-model="nuevoUsuario.apellido" required maxlength="60" :placeholder="t('configuracion.apellido')" :aria-label="t('configuracion.apellido')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('configuracion.email') }}</label>
            <input v-model="nuevoUsuario.email" type="email" required :placeholder="t('configuracion.ejemploEmail')"
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">{{ t('configuracion.rolAsignado') }}</label>
            <select v-model="nuevoUsuario.rol" required
              class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde">
              <option value="">{{ t('comun.seleccionar') }}</option>
              <option v-for="r in rolesInvitables" :key="r.clave" :value="r.clave">{{ r.nombre }}</option>
            </select>
          </div>
          <p v-if="errorInvitacion" role="alert" class="text-sm text-red-700">{{ errorInvitacion }}</p>
          <div class="flex gap-3 pt-2">
            <button type="button" @click="abrirNuevoUsuario = false" class="btn-secondary flex-1">{{ t('comun.cancelar') }}</button>
            <button type="submit" :disabled="enviandoInvitacion" class="btn-primary flex-1 disabled:opacity-60">
              {{ enviandoInvitacion ? t('comun.enviando') : t('configuracion.crearEnlace') }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Check, Church, Database, ExternalLink, HandHeart, KeyRound, Lightbulb, ListChecks, Lock, Mail, MessageCircle, Palette, Plug, ShieldCheck, TriangleAlert, Users } from '@lucide/vue'
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import ConfigDar from '@/components/ConfigDar.vue'
import { useAuthStore } from '@/stores/auth'
import { useI18n } from 'vue-i18n'

const auth = useAuthStore()
const { t, te, locale } = useI18n()
const roles = ref<any[]>([])
// Clave de traducción del aviso visible ('' = sin aviso)
const mensajeIglesia = ref('')
// El rol de superadministrador no se cambia desde la lista; solo se puede invitar a otro superadministrador
const rolesAsignables = computed(() => roles.value.filter(r => !r.es_propietario))
const rolesInvitables = computed(() => roles.value.filter(r => !r.es_propietario || auth.rolInfo?.es_propietario))

const tabActivo = ref('iglesia')
const guardando = ref(false)
const abrirNuevoUsuario = ref(false)
const enviandoInvitacion = ref(false)
const errorInvitacion = ref('')
const invitaciones = ref<any[]>([])
const enlaceCreado = ref<{ enlace: string; email: string; enviado: boolean } | null>(null)
const copiado = ref(false)
const usuarios = ref<any[]>([])
const camposIntegracion = ref<Record<string, string>>({})

// Nombre de cada pestaña: configuracion.tabs.<id> en src/i18n
const tabs = [
  { id: 'iglesia', icono: Church },
  { id: 'usuarios', icono: Users },
  { id: 'dar', icono: HandHeart },
  { id: 'integraciones', icono: Plug },
  { id: 'seguridad', icono: ShieldCheck },
]

const iglesia = ref({ nombre: '', pais: '', ciudad: '', email: '' })

const nuevoUsuario = ref({ email: '', nombre: '', apellido: '', rol: '' })

// nombre: clave de traducción
const paletaColores = [
  { nombre: 'configuracion.colores.verdeBase', valor: '#00523c' },
  { nombre: 'configuracion.colores.oroVivo', valor: '#f5a623' },
  { nombre: 'configuracion.colores.verdeOscuro', valor: '#003828' },
  { nombre: 'configuracion.colores.arenaSuave', valor: '#f4f0e6' },
]

// Textos como claves de traducción; los placeholders sin clave (SG.xxx) se muestran tal cual
const integraciones = [
  {
    id: 'whatsapp',
    icono: MessageCircle,
    nombre: 'configuracion.integraciones.whatsapp.nombre',
    descripcion: 'configuracion.integraciones.whatsapp.descripcion',
    activa: false,
    configuracion: [
      { clave: 'token', etiqueta: 'configuracion.integraciones.whatsapp.token', tipo: 'password', placeholder: 'configuracion.integraciones.whatsapp.tokenPlaceholder' },
      { clave: 'phone_id', etiqueta: 'configuracion.integraciones.whatsapp.phoneId', tipo: 'text', placeholder: 'configuracion.integraciones.whatsapp.phoneIdPlaceholder' },
    ],
    nota: 'configuracion.integraciones.whatsapp.nota',
  },
  {
    id: 'sendgrid',
    icono: Mail,
    nombre: 'configuracion.integraciones.sendgrid.nombre',
    descripcion: 'configuracion.integraciones.sendgrid.descripcion',
    activa: false,
    configuracion: [
      { clave: 'api_key', etiqueta: 'configuracion.integraciones.sendgrid.apiKey', tipo: 'password', placeholder: 'SG.xxxxxxxxxxxxxxxx' },
      { clave: 'from_email', etiqueta: 'configuracion.integraciones.sendgrid.remitente', tipo: 'email', placeholder: 'configuracion.integraciones.sendgrid.remitentePlaceholder' },
    ],
    nota: 'configuracion.integraciones.sendgrid.nota',
  },
  {
    id: 'supabase',
    icono: Database,
    nombre: 'configuracion.integraciones.supabase.nombre',
    descripcion: 'configuracion.integraciones.supabase.descripcion',
    activa: true,
    configuracion: null,
    nota: 'configuracion.integraciones.supabase.nota',
  },
]

function claseRol(rol: string) {
  const m: Record<string, string> = {
    propietario: 'bg-purple-100 text-purple-700',
    administrador: 'bg-blue-100 text-blue-700',
    coadministrador: 'bg-indigo-100 text-indigo-700',
    lider_zona: 'bg-teal-100 text-teal-700',
    colaborador: 'bg-pink-100 text-pink-700',
    lider_casa: 'bg-green-100 text-green-700',
    lider_escuela: 'bg-yellow-100 text-yellow-700',
    consolidador: 'bg-orange-100 text-orange-700',
    miembro: 'bg-gray-100 text-gray-600',
  }
  return m[rol] ?? 'bg-gray-100 text-gray-600'
}

function etiquetaRol(clave: string) {
  return roles.value.find(r => r.clave === clave)?.nombre ?? clave
}

async function cambiarRol(usuario: any, nuevoRol: string) {
  const { data, error } = await supabase
    .from('perfiles')
    .update({ rol: nuevoRol })
    .eq('id', usuario.id)
    .select('id')
  if (error || !data?.length) {
    alert(t('configuracion.errorRol'))
    await cargarUsuarios()
  if (auth.can('usuarios.gestionar')) await cargarInvitaciones()
    return
  }
  usuario.rol = nuevoRol
}

async function guardarIglesia() {
  if (!auth.iglesiaId) return
  guardando.value = true
  mensajeIglesia.value = ''
  const { data, error } = await supabase
    .from('iglesias')
    .update({
      nombre: iglesia.value.nombre,
      pais: iglesia.value.pais,
      ciudad: iglesia.value.ciudad,
      email_contacto: iglesia.value.email,
    })
    .eq('id', auth.iglesiaId)
    .select('*')
  guardando.value = false
  if (error || !data?.length) {
    mensajeIglesia.value = 'configuracion.errorGuardar'
    return
  }
  auth.iglesia = data[0]
  mensajeIglesia.value = 'configuracion.guardado'
}

async function llamarInvitaciones(cuerpo: Record<string, unknown>) {
  const { data, error } = await supabase.functions.invoke('invitaciones', { body: cuerpo })
  if (error || data?.error) {
    let motivo = t('invitacion.errorGenerico')
    try { const resp = (error as any)?.context; if (resp?.json) motivo = (await resp.json()).error ?? motivo } catch { /* mensaje por defecto */ }
    return { data: null, motivo }
  }
  return { data, motivo: '' }
}

async function cargarInvitaciones() {
  const { data } = await supabase.from('invitaciones')
    .select('id, email, nombre, apellido, rol, caduca_en')
    .is('usada_en', null).is('revocada_en', null).order('creada_en', { ascending: false })
  invitaciones.value = data ?? []
}

async function invitarUsuario() {
  errorInvitacion.value = ''
  enviandoInvitacion.value = true
  const { data, motivo } = await llamarInvitaciones({ accion: 'crear', idioma: locale.value, ...nuevoUsuario.value })
  enviandoInvitacion.value = false
  if (!data) { errorInvitacion.value = motivo; return }
  abrirNuevoUsuario.value = false
  enlaceCreado.value = { enlace: data.enlace, email: nuevoUsuario.value.email, enviado: !!data.enviado }
  nuevoUsuario.value = { email: '', nombre: '', apellido: '', rol: '' }
  await cargarInvitaciones()
}

async function reenviarInvitacion(id: string) {
  const { data, motivo } = await llamarInvitaciones({ accion: 'reenviar', id, idioma: locale.value })
  if (!data) { alert(motivo); return }
  const previa = invitaciones.value.find(i => i.id === id)
  enlaceCreado.value = { enlace: data.enlace, email: previa?.email ?? '', enviado: !!data.enviado }
  await cargarInvitaciones()
}

async function revocarInvitacion(id: string) {
  const { data, motivo } = await llamarInvitaciones({ accion: 'revocar', id })
  if (!data) { alert(motivo); return }
  await cargarInvitaciones()
}

async function copiarEnlace() {
  try { await navigator.clipboard.writeText(enlaceCreado.value?.enlace ?? ''); copiado.value = true; setTimeout(() => (copiado.value = false), 2000) } catch { /* el campo se puede copiar a mano */ }
}

async function cargarUsuarios() {
  const { data } = await supabase
    .from('perfiles')
    .select('id, nombre, apellido, email, rol')
    .order('nombre')
  usuarios.value = data ?? []
}

onMounted(async () => {
  const ig = auth.iglesia
  if (ig) {
    iglesia.value = {
      nombre: ig.nombre ?? '',
      pais: ig.pais ?? '',
      ciudad: ig.ciudad ?? '',
      email: ig.email_contacto ?? '',
    }
  }
  const { data: rs } = await supabase
    .from('roles')
    .select('id, clave, nombre, descripcion, es_propietario, rol_permisos(permiso)')
    .order('created_at')
  roles.value = rs ?? []
  await cargarUsuarios()
  if (auth.can('usuarios.gestionar')) await cargarInvitaciones()
})
</script>
