<template>
  <div class="slidev-layout paste-layout">
    <div class="inner">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.inner {
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  min-height: 100%;
  padding-bottom: var(--space-xs);
  gap: var(--space-xl);
}

.inner :deep(h1) {
  max-width: none;
  font-size: clamp(2.8rem, 6.4vw, 4.4rem);
  order: 2;
}

.inner :deep(.chain) {
  order: 1;
  margin-top: 0;
}
</style>
