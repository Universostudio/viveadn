import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    // Portada y presentacion: lo primero que ve quien aun no ha iniciado sesion
    {
      path: '/bienvenida',
      name: 'bienvenida',
      component: () => import('@/views/BienvenidaView.vue'),
      meta: { public: true }
    },
    {
      path: '/presentacion',
      name: 'presentacion',
      component: () => import('@/views/PresentacionView.vue'),
      meta: { public: true, allowLoggedIn: true }
    },
    // Auth
    {
      path: '/login',
      name: 'login',
      component: () => import('@/views/auth/LoginView.vue'),
      meta: { public: true }
    },
    {
      path: '/registro',
      name: 'registro',
      component: () => import('@/views/auth/RegistroView.vue'),
      meta: { public: true }
    },
    {
      path: '/reset-password',
      name: 'reset-password',
      component: () => import('@/views/auth/ResetPasswordView.vue'),
      // El enlace del correo inicia sesion; hay que dejar ver el formulario igualmente
      meta: { public: true, allowLoggedIn: true }
    },
    {
      path: '/aceptar',
      name: 'aceptar-invitacion',
      component: () => import('@/views/auth/AceptarInvitacionView.vue'),
      meta: { public: true, allowLoggedIn: true }
    },
    // Pagina publica para dar: la ve cualquier persona con el enlace de la iglesia
    {
      path: '/dar/:slug',
      name: 'dar-publica',
      component: () => import('@/views/DarPublicaView.vue'),
      meta: { public: true, allowLoggedIn: true }
    },
    // Registro por QR: lo abre cualquier persona con el enlace secreto de un evento
    {
      path: '/checkin/:token',
      name: 'checkin-publico',
      component: () => import('@/views/CheckinPublicoView.vue'),
      meta: { public: true, allowLoggedIn: true }
    },
    // App principal (requiere auth)
    {
      path: '/',
      component: () => import('@/layouts/AppLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        {
          path: '',
          name: 'dashboard',
          component: () => import('@/views/DashboardView.vue')
        },
        {
          path: 'miembros',
          name: 'miembros',
          component: () => import('@/views/miembros/MiembrosView.vue')
        },
        {
          path: 'miembros/:id',
          name: 'miembro-detalle',
          component: () => import('@/views/miembros/MiembroDetalleView.vue')
        },
        {
          path: 'eventos',
          name: 'eventos',
          component: () => import('@/views/eventos/EventosView.vue')
        },
        {
          path: 'eventos/:id',
          name: 'evento-detalle',
          component: () => import('@/views/eventos/EventoDetalleView.vue')
        },
        {
          path: 'casas',
          name: 'casas',
          component: () => import('@/views/casas/CasasView.vue')
        },
        {
          path: 'consolidacion',
          name: 'consolidacion',
          component: () => import('@/views/consolidacion/ConsolidacionView.vue')
        },
        {
          path: 'formacion',
          name: 'formacion',
          component: () => import('@/views/FormacionView.vue')
        },
        {
          path: 'comunicacion',
          name: 'comunicacion',
          component: () => import('@/views/ComunicacionView.vue')
        },
        {
          path: 'reportes',
          name: 'reportes',
          component: () => import('@/views/ReportesView.vue')
        },
        {
          path: 'configuracion',
          name: 'configuracion',
          component: () => import('@/views/ConfiguracionView.vue')
        },
        {
          path: 'red',
          name: 'red',
          component: () => import('@/views/RedView.vue')
        },
        {
          path: 'plataforma',
          name: 'plataforma',
          component: () => import('@/views/plataforma/PlataformaView.vue'),
          meta: { requiresPlataforma: true }
        },
      ]
    },
    // 404
    {
      path: '/:pathMatch(.*)*',
      redirect: '/'
    }
  ]
})

// Guard de autenticación
router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (auth.loading) await auth.init()

  if (to.meta.requiresAuth && !auth.isLoggedIn) {
    // Quien llega a la raiz sin sesion ve la portada; el resto de rutas protegidas lleva directo al acceso
    return { name: to.path === '/' ? 'bienvenida' : 'login' }
  }
  if (to.meta.public && auth.isLoggedIn && !to.meta.allowLoggedIn) {
    return { name: 'dashboard' }
  }
  if (to.meta.requiresPlataforma && !auth.esPlataforma) {
    return { name: 'dashboard' }
  }
})

export default router
