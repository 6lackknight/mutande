<template>
  <div class="slidev-layout statement-layout">
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
  padding-bottom: 0.5rem;
}

.inner :deep(h1) {
  max-width: 20ch;
  font-size: clamp(2.8rem, 6.4vw, 4.4rem);
}

.inner :deep(.kicker) {
  margin-bottom: 0.85rem;
}
</style>
