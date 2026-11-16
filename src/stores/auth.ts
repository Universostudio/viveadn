import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import type { Perfil, Iglesia } from '@/lib/supabase'
import { aterrizajeDe } from '@/lib/acceso'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<any>(null)
  const perfil = ref<Perfil | null>(null)
  const iglesia = ref<Iglesia | null>(null)
  const loading = ref(true)
  const permisos = ref<Set<string>>(new Set())
  const rolInfo = ref<{ nombre: string; es_propietario: boolean } | null>(null)

  const esPlataforma = ref(false)
  // Contexto de un administrador de plataforma que ademas pertenece a una iglesia: dura lo que dura la pestaña, nunca se guarda en la base
  const CLAVE_CONTEXTO = 'adn_contexto'
  const leerContexto = (): 'plataforma' | 'iglesia' => {
    try { return sessionStorage.getItem(CLAVE_CONTEXTO) === 'iglesia' ? 'iglesia' : 'plataforma' } catch { return 'plataforma' }
  }
  const contexto = ref<'plataforma' | 'iglesia'>(leerContexto())
  function fijarContexto(c: 'plataforma' | 'iglesia') {
    contexto.value = c
    try { sessionStorage.setItem(CLAVE_CONTEXTO, c) } catch { /* sin almacenamiento: el contexto vale hasta recargar */ }
  }
  const tieneSedes = ref(false)
  const modulosActivos = ref<Set<string>>(new Set())
  const moduloDePermiso = ref<Record<string, string>>({})

  // Vista previa de la interfaz con los permisos de otro rol. Solo la usa el superadministrador.
  // Cambia lo que muestra la interfaz, NO lo que permite la base de datos: los datos siguen siendo los reales.
  const verComo = ref<{ clave: string; nombre: string; es_propietario: boolean; permisos: Set<string> } | null>(null)
  const rolesDisponibles = ref<{ clave: string; nombre: string }[]>([])

  // Solo el superadministrador ve el panel de red, y solo si su iglesia tiene sedes
  async function comprobarSedes() {
    tieneSedes.value = false
    if (rolInfo.value?.es_propietario !== true) return
    try {
      const { data } = await supabase.functions.invoke('red-resumen', { body: { solo_contar: true } })
      tieneSedes.value = (data?.total ?? 0) > 0
    } catch { /* sin red no hay menu: no es un error para quien entra */ }
  }

  async function cargarRolesParaVerComo() {
    if (rolInfo.value?.es_propietario !== true) return
    const { data } = await supabase.from('roles').select('clave, nombre').order('created_at')
    rolesDisponibles.value = data ?? []
  }

  async function simularRol(clave: string | null) {
    if (!clave || rolInfo.value?.es_propietario !== true || !perfil.value?.iglesia_id) { verComo.value = null; return }
    const { data: r } = await supabase.from('roles').select('clave, nombre, es_propietario, rol_permisos(permiso)')
      .eq('iglesia_id', perfil.value.iglesia_id).eq('clave', clave).maybeSingle()
    verComo.value = r ? { clave: r.clave, nombre: r.nombre, es_propietario: r.es_propietario, permisos: new Set((r.rol_permisos ?? []).map((x: any) => x.permiso)) } : null
  }

  function tieneModulo(clave: string) {
    return modulosActivos.value.has(clave)
  }

  // true si el rol incluye alguno de los permisos y el plan de la iglesia tiene su módulo
  function can(...claves: string[]) {
    return claves.some(c => {
      const modulo = moduloDePermiso.value[c]
      if (!modulo || !modulosActivos.value.has(modulo)) return false
      const sim = verComo.value
      if (sim) return sim.es_propietario || sim.permisos.has(c)
      return rolInfo.value?.es_propietario === true || permisos.value.has(c)
    })
  }

  const nombreRol = computed(() => rolInfo.value?.nombre ?? perfil.value?.rol ?? '')
  const isLoggedIn = computed(() => !!user.value)
  const iglesiaId = computed(() => perfil.value?.iglesia_id)
  const tieneIglesia = computed(() => !!perfil.value?.iglesia_id)
  // Un administrador de plataforma sin iglesia no tiene permisos de iglesia que comprobar
  const esPlataformaSinIglesia = computed(() => esPlataforma.value && !perfil.value?.iglesia_id)
  // A dónde llega al iniciar sesión según su rol: el líder de casa, a «Mi panel»; el resto, al panel de inicio
  const aterrizaje = computed<'mi-panel' | 'dashboard'>(() => aterrizajeDe({ can }))
  // Un administrador de plataforma trabaja en el Panel Maestro salvo que elija entrar a su iglesia (y solo si tiene una)
  const enPanelMaestro = computed(() => esPlataforma.value && !(tieneIglesia.value && contexto.value === 'iglesia'))
  const rol = computed(() => perfil.value?.rol)
  const nombreIglesia = computed(() => iglesia.value?.nombre ?? '')
  // Iglesia que registra a las personas con un alias, sin apellido ni correo
  const modoAlias = computed(() => iglesia.value?.modo_alias === true)
  const nombreCompleto = computed(() =>
    perfil.value ? `${perfil.value.nombre} ${perfil.value.apellido}` : ''
  )

  async function init() {
    loading.value = true
    const { data: { session } } = await supabase.auth.getSession()
    user.value = session?.user ?? null
    if (user.value) await cargarPerfil()
    loading.value = false

    supabase.auth.onAuthStateChange(async (_event, session) => {
      user.value = session?.user ?? null
      if (user.value) await cargarPerfil()
      else limpiar()
    })
  }

  async function cargarPerfil() {
    if (!user.value) return
    const { data } = await supabase
      .from('perfiles')
      .select('*')
      .eq('id', user.value.id)
      .single()
    perfil.value = data
    const { data: pa } = await supabase.from('plataforma_admins').select('user_id').maybeSingle()
    esPlataforma.value = !!pa
    if (data?.iglesia_id) {
      const { data: ig } = await supabase
        .from('iglesias')
        .select('*')
        .eq('id', data.iglesia_id)
        .single()
      iglesia.value = ig

      const { data: r } = await supabase
        .from('roles')
        .select('nombre, es_propietario, rol_permisos(permiso)')
        .eq('iglesia_id', data.iglesia_id)
        .eq('clave', data.rol)
        .maybeSingle()
      rolInfo.value = r ? { nombre: r.nombre, es_propietario: r.es_propietario } : null
      permisos.value = new Set((r?.rol_permisos ?? []).map((x: any) => x.permiso))

      // Módulos activos: los del plan más los contratados aparte
      const [{ data: delPlan }, { data: extra }, { data: catalogo }] = await Promise.all([
        supabase.from('plan_modulos').select('modulo').eq('plan', ig?.plan ?? ''),
        supabase.from('iglesia_modulos').select('modulo, activo, desde, hasta').eq('iglesia_id', data.iglesia_id),
        supabase.from('permisos').select('clave, modulo'),
      ])
      const ahora = Date.now()
      const activos = new Set<string>((delPlan ?? []).map((x: any) => x.modulo))
      for (const e of extra ?? []) {
        const vigente = e.activo && new Date(e.desde).getTime() <= ahora && (!e.hasta || new Date(e.hasta).getTime() > ahora)
        if (vigente) activos.add(e.modulo)
      }
      modulosActivos.value = activos
      await cargarRolesParaVerComo()
      await comprobarSedes()
      moduloDePermiso.value = Object.fromEntries((catalogo ?? []).map((p: any) => [p.clave, p.modulo]))
    }
  }

  function limpiar() {
    perfil.value = null
    iglesia.value = null
    rolInfo.value = null
    verComo.value = null
    rolesDisponibles.value = []
    esPlataforma.value = false
    try { sessionStorage.removeItem(CLAVE_CONTEXTO) } catch { /* nada que limpiar */ }
    contexto.value = 'plataforma'
    tieneSedes.value = false
    permisos.value = new Set()
    modulosActivos.value = new Set()
    moduloDePermiso.value = {}
  }

  async function login(email: string, password: string) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    // Se carga el perfil antes de volver: el guard de rutas necesita saber ya si es administrador de plataforma
    user.value = data.user
    await cargarPerfil()
  }

  async function logout() {
    await supabase.auth.signOut()
    user.value = null
    limpiar()
  }

  return { user, perfil, iglesia, nombreIglesia, modoAlias, loading, isLoggedIn, iglesiaId, rol, rolInfo, verComo, rolesDisponibles, simularRol, nombreRol, nombreCompleto, esPlataforma, tieneIglesia, esPlataformaSinIglesia, aterrizaje, enPanelMaestro, contexto, fijarContexto, tieneSedes, can, tieneModulo, init, login, logout }
})
