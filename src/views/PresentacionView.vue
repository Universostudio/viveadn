<template>
  <div class="min-h-screen bg-adn-arena text-adn-profundo">
    <header class="bg-adn-verde text-white">
      <div class="max-w-5xl mx-auto px-5 py-4 flex items-center justify-between gap-3">
        <RouterLink :to="{ name: 'bienvenida' }" class="flex items-center gap-3" :aria-label="t('presentacion.inicio')">
          <LogoAdn class="w-8 h-auto text-white" />
          <span class="font-display font-extrabold text-lg"><span class="text-adn-oro">VIVE</span> ADN</span>
        </RouterLink>
        <div class="flex items-center gap-3">
          <SelectorIdioma ocultar-etiqueta />
          <RouterLink :to="{ name: 'login' }" class="bg-adn-oro text-[#0d1b3e] font-display font-bold text-sm px-5 py-2 rounded-lg hover:brightness-110 transition">{{ t('bienvenida.entrar') }}</RouterLink>
        </div>
      </div>
    </header>

    <section class="bg-gradient-to-b from-adn-verde to-adn-oscuro text-white">
      <div class="max-w-3xl mx-auto px-5 py-16 sm:py-24 text-center">
        <h1 class="font-display font-extrabold text-3xl sm:text-5xl leading-tight">{{ t('presentacion.titulo') }}</h1>
        <p class="mt-5 text-lg text-white/80">{{ t('presentacion.subtitulo') }}</p>
        <div class="mt-8 flex flex-col sm:flex-row items-center justify-center gap-3">
          <RouterLink :to="{ name: 'registro' }" class="inline-flex items-center gap-2 bg-adn-oro text-[#0d1b3e] font-display font-bold px-8 py-3 rounded-lg hover:brightness-110 transition">
            {{ t('registro.enlaceBienvenida') }} <ArrowRight class="w-4 h-4" aria-hidden="true" />
          </RouterLink>
          <RouterLink :to="{ name: 'login' }" class="inline-flex items-center border border-white/30 text-white/90 hover:border-adn-oro hover:text-adn-oro font-display font-medium px-8 py-3 rounded-lg transition">
            {{ t('bienvenida.entrar') }}
          </RouterLink>
        </div>
      </div>
    </section>

    <section class="max-w-5xl mx-auto px-5 py-14">
      <h2 class="font-display font-bold text-2xl text-adn-verde text-center">{{ t('presentacion.queHaceTitulo') }}</h2>
      <p class="text-center text-gray-600 mt-2 max-w-2xl mx-auto">{{ t('presentacion.queHaceTexto') }}</p>
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 mt-8">
        <article v-for="m in MODULOS" :key="m.clave" class="bg-white rounded-2xl p-5 shadow-sm border border-black/5">
          <div class="w-10 h-10 rounded-xl bg-adn-verde/10 text-adn-verde flex items-center justify-center mb-3"><component :is="m.icono" class="w-5 h-5" aria-hidden="true" /></div>
          <h3 class="font-display font-bold text-adn-verde">{{ t(`presentacion.modulos.${m.clave}.titulo`) }}</h3>
          <p class="text-sm text-gray-600 mt-1">{{ t(`presentacion.modulos.${m.clave}.texto`) }}</p>
        </article>
      </div>
    </section>

    <section class="bg-white">
      <div class="max-w-5xl mx-auto px-5 py-14 grid gap-8 md:grid-cols-2">
        <div>
          <h2 class="font-display font-bold text-2xl text-adn-verde">{{ t('presentacion.nivelesTitulo') }}</h2>
          <p class="text-gray-600 mt-2">{{ t('presentacion.nivelesTexto') }}</p>
        </div>
        <ul class="space-y-3">
          <li v-for="n in NIVELES" :key="n" class="rounded-xl border border-adn-verde/15 p-4">
            <p class="font-display font-bold text-adn-verde">{{ t(`presentacion.niveles.${n}.titulo`) }}</p>
            <p class="text-sm text-gray-600 mt-0.5">{{ t(`presentacion.niveles.${n}.texto`) }}</p>
          </li>
        </ul>
      </div>
    </section>

    <section class="max-w-3xl mx-auto px-5 py-14 text-center">
      <h2 class="font-display font-bold text-2xl text-adn-verde">{{ t('presentacion.dar.titulo') }}</h2>
      <p class="text-gray-600 mt-2">{{ t('presentacion.dar.texto') }}</p>
    </section>

    <footer class="bg-adn-oscuro text-white/60 text-xs text-center py-6">
      ViveADN · viveadn.com · {{ t('bienvenida.lema1') }} {{ t('bienvenida.lema2') }} · 2026
    </footer>
  </div>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { ArrowRight, BookOpen, CalendarCheck, HandHeart, HeartHandshake, House, Users } from '@lucide/vue'
import LogoAdn from '@/components/LogoAdn.vue'
import SelectorIdioma from '@/components/SelectorIdioma.vue'

const { t } = useI18n()

const MODULOS = [
  { clave: 'miembros', icono: Users },
  { clave: 'op72', icono: HeartHandshake },
  { clave: 'casas', icono: House },
  { clave: 'formacion', icono: BookOpen },
  { clave: 'eventos', icono: CalendarCheck },
  { clave: 'dar', icono: HandHeart },
] as const
const NIVELES = ['plataforma', 'red', 'iglesia'] as const
</script>
