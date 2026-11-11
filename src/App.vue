<script setup lang="ts">
import { RouterView } from 'vue-router'
import ErrorView from '@/views/ErrorView.vue'
import { errorApp } from '@/lib/errorApp'
</script>

<template>
  <ErrorView v-if="errorApp" :tipo="errorApp" />
  <RouterView v-else />
</template>
