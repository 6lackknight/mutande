<script setup lang="ts">
defineProps<{
  size?: number
}>()
</script>

<template>
  <img
    class="seal"
    src="/ai-mark.png"
    alt=""
    :width="size ?? 44"
    :height="size ?? 44"
  />
</template>

<style scoped>
.seal {
  display: block;
  border-radius: 22%;
  box-shadow: 0 8px 24px -16px oklch(0.22 0.014 60 / 0.55);
}
</style>
