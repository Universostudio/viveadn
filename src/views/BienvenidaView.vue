<template>
  <main class="min-h-screen relative overflow-hidden flex items-center justify-center px-6 py-10 text-white bienvenida">
    <div class="absolute inset-0 rejilla" aria-hidden="true"></div>
    <div class="relative z-10 w-full max-w-2xl text-center">
      <div class="flex flex-col sm:flex-row items-center justify-center gap-6 sm:gap-10 mb-8">
        <LogoAdn class="animar w-24 sm:w-28 h-auto text-white drop-shadow-lg" />
        <div class="font-display font-extrabold leading-[0.92] text-6xl sm:text-7xl text-left sm:text-left">
          <span class="block text-adn-oro palabra" style="animation-delay: 1.35s">VIVE</span>
          <span class="block text-white palabra" style="animation-delay: 1.6s">ADN</span>
        </div>
      </div>
      <div class="w-14 h-px mx-auto mb-5 bg-gradient-to-r from-transparent via-adn-oro to-transparent aparece" style="animation-delay: 1.9s"></div>
      <p class="text-lg sm:text-xl font-light text-white/80 mb-10 sube" style="animation-delay: 2.05s">
        <strong class="font-semibold text-adn-oro">{{ t('bienvenida.lema1') }}</strong> {{ t('bienvenida.lema2') }}
      </p>
      <div class="flex flex-col sm:flex-row items-center justify-center gap-3 sube" style="animation-delay: 2.25s">
        <RouterLink :to="{ name: 'login' }" class="w-full sm:w-auto max-w-xs inline-flex items-center justify-center gap-2 bg-adn-oro text-[#0d1b3e] font-display font-bold text-sm px-8 py-3 rounded-lg shadow-lg hover:brightness-110 transition">
          {{ t('bienvenida.entrar') }} <ArrowRight class="w-4 h-4" aria-hidden="true" />
        </RouterLink>
        <RouterLink :to="{ name: 'presentacion' }" class="w-full sm:w-auto max-w-xs inline-flex items-center justify-center border border-white/25 text-white/80 hover:text-adn-oro hover:border-adn-oro/60 font-display font-medium text-sm px-8 py-3 rounded-lg transition">
          {{ t('bienvenida.conocer') }}
        </RouterLink>
      </div>
      <p class="mt-6 text-sm text-white/70 sube" style="animation-delay: 2.4s">
        <RouterLink :to="{ name: 'registro' }" class="underline underline-offset-4 hover:text-adn-oro">{{ t('registro.enlaceBienvenida') }}</RouterLink>
      </p>
      <div class="mt-10 flex justify-center"><SelectorIdioma ocultar-etiqueta /></div>
    </div>
    <p class="absolute bottom-5 inset-x-0 text-center text-[10px] tracking-widest uppercase text-white/30 aparece" style="animation-delay: 2.5s">
      ViveADN · viveadn.com · {{ t('bienvenida.lema1') }} {{ t('bienvenida.lema2') }} · 2026
    </p>
  </main>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { ArrowRight } from '@lucide/vue'
import LogoAdn from '@/components/LogoAdn.vue'
import SelectorIdioma from '@/components/SelectorIdioma.vue'

const { t } = useI18n()
</script>

<style scoped>
.bienvenida {
  background:
    radial-gradient(ellipse 80% 60% at 50% -5%, rgba(245, 166, 35, 0.13) 0%, transparent 50%),
    radial-gradient(ellipse 50% 40% at 100% 100%, rgba(0, 0, 0, 0.15) 0%, transparent 50%),
    linear-gradient(160deg, #00523c 0%, #003d2c 50%, #002a1e 100%);
}
.rejilla {
  background-image: linear-gradient(rgba(245, 166, 35, 0.04) 1px, transparent 1px), linear-gradient(90deg, rgba(245, 166, 35, 0.04) 1px, transparent 1px);
  background-size: 52px 52px;
}
.palabra { opacity: 0; transform: translateX(-40px); animation: deslizar 0.7s cubic-bezier(0.22, 1, 0.36, 1) forwards; }
.aparece { opacity: 0; animation: aparecer 0.8s ease forwards; }
.sube { opacity: 0; animation: subir 0.7s ease forwards; }
@keyframes deslizar { to { opacity: 1; transform: translateX(0); } }
@keyframes aparecer { to { opacity: 1; } }
@keyframes subir { from { opacity: 0; transform: translateY(18px); } to { opacity: 1; transform: translateY(0); } }
@media (prefers-reduced-motion: reduce) { .palabra, .aparece, .sube { animation: none; opacity: 1; transform: none; } }
</style>
