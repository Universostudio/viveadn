import './assets/main.css'

import { createApp } from 'vue'
import { createPinia } from 'pinia'

import App from './App.vue'
import router from './router'
import i18n from './i18n'
import { useAuthStore } from './stores/auth'
import { marcarError, esErrorDeCarga } from './lib/errorApp'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)
app.use(i18n)

// Inicializar auth antes de montar para que el guard tenga sesión disponible
const auth = useAuthStore()
// Si la sesión no se puede iniciar, la página no se queda en blanco: se monta con la pantalla de error
auth.init().catch((e) => {
  console.error('inicio de sesión', e)
  marcarError('inicio')
}).finally(() => {
  app.mount('#app')
})

// Un fallo al pintar un componente se anota, pero no tapa la pantalla: seguir usándola suele ser posible
app.config.errorHandler = (e) => { console.error(e) }
// Tras una publicación nueva, la página abierta pide archivos que ya no existen: la pantalla propone recargar
router.onError((e) => { if (esErrorDeCarga(e)) marcarError('carga'); else console.error(e) })
window.addEventListener('vite:preloadError', (ev) => { ev.preventDefault(); marcarError('carga') })
