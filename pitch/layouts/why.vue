<template>
  <div class="slidev-layout why-layout">
    <slot />
  </div>
</template>

<style scoped>
.why-layout {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  min-height: 100%;
  padding-bottom: 0.5rem;
}

.why-layout :deep(h1) {
  max-width: 22rem;
  font-size: clamp(2.6rem, 5.8vw, 4rem);
  line-height: 1.02;
}
</style>
