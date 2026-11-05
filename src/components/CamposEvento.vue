<template>
  <div class="space-y-4">
    <div>
      <label :for="`${idBase}-titulo`" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoTitulo') }}</label>
      <input :id="`${idBase}-titulo`" v-model="form.titulo" required maxlength="150" :placeholder="t('eventos.ejemploTitulo')" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div>
        <label :for="`${idBase}-tipo`" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoTipo') }}</label>
        <select :id="`${idBase}-tipo`" v-model="form.tipo" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm bg-white">
          <option v-for="tp in TIPOS_EVENTO" :key="tp" :value="tp">{{ t(`eventos.tipo.${tp}`) }}</option>
        </select>
      </div>
      <div>
        <label :for="`${idBase}-casa`" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoCasa') }}</label>
        <select :id="`${idBase}-casa`" v-model="form.casa_id" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm bg-white">
          <option value="">{{ t('eventos.sinCasa') }}</option>
          <option v-for="c in casas" :key="c.id" :value="c.id">{{ c.nombre || c.codigo_zona }}</option>
        </select>
      </div>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div>
        <label :for="`${idBase}-inicio`" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoInicio') }}</label>
        <input :id="`${idBase}-inicio`" v-model="form.inicio" type="datetime-local" required class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm" />
      </div>
      <div>
        <label :for="`${idBase}-fin`" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoFin') }}</label>
        <input :id="`${idBase}-fin`" v-model="form.fin" type="datetime-local" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm" />
      </div>
    </div>
    <div>
      <label :for="`${idBase}-lugar`" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoLugar') }}</label>
      <input :id="`${idBase}-lugar`" v-model="form.lugar" maxlength="200" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-adn-verde" />
    </div>
    <div>
      <label :for="`${idBase}-desc`" class="block text-sm font-medium text-gray-700 mb-1">{{ t('eventos.campoDescripcion') }}</label>
      <textarea :id="`${idBase}-desc`" v-model="form.descripcion" rows="2" maxlength="2000" class="w-full px-3 py-2.5 border border-gray-200 rounded-lg text-sm"></textarea>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { TIPOS_EVENTO } from '@/lib/eventos'
import type { FormEvento } from '@/lib/eventos'

// Campos comunes de un evento, para crear y para editar. Edita el objeto que recibe por v-model.
defineProps<{ casas: { id: string; nombre?: string | null; codigo_zona?: string | null }[]; idBase: string }>()
const form = defineModel<FormEvento>({ required: true })
const { t } = useI18n()
</script>
