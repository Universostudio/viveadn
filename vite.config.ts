import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    vueDevTools(),
  ],
  // Opciones de vue-i18n: solo la API de composición, sin herramientas de depuración en producción
  define: {
    __VUE_I18N_FULL_INSTALL__: true,
    __VUE_I18N_LEGACY_API__: false,
    __INTLIFY_PROD_DEVTOOLS__: false,
    // Qué versión se está viendo: en Vercel, el commit que se construyó; en local, «local»
    __ADN_VERSION__: JSON.stringify((process.env.VERCEL_GIT_COMMIT_SHA ?? 'local').slice(0, 7)),
    // Entorno: «produccion» solo si se pide con VITE_ENTORNO o si Vercel construye el entorno de producción; todo lo demás (vista previa, local) es «pruebas»
    __ADN_ENTORNO__: JSON.stringify(process.env.VITE_ENTORNO ?? (process.env.VERCEL_ENV === 'production' ? 'produccion' : 'pruebas')),
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
