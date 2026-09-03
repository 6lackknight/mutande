<template>
  <div class="slidev-layout brand-layout">
    <slot />
  </div>
</template>

<style scoped>
.brand-layout {
  display: flex;
  flex-direction: column;
  justify-content: center;
  min-height: 100%;
  gap: var(--space-sm);
}
</style>
