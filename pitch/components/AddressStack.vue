<template>
  <div class="stack address-stack" aria-label="Address to communication">
    <div v-for="(item, i) in items" :key="item" class="item">
      <span class="word">{{ item }}</span>
      <span v-if="i < items.length - 1" class="down" aria-hidden="true">↓</span>
    </div>
  </div>
  <p class="note">The address is the entry point — not the whole product.</p>
</template>

<script setup lang="ts">
defineOptions({ inheritAttrs: false })

const items = ['Address', 'Identity', 'Capabilities', 'Communication']
</script>

<style scoped>
.stack {
  margin-top: 0;
  display: flex;
  flex-direction: column;
  gap: 0;
  max-width: 14rem;
}

.item {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.35rem;
}

.word {
  font-size: 1.15rem;
  font-weight: 600;
  letter-spacing: -0.03em;
  color: var(--ink);
  padding: 0.35rem 0;
  border-top: 1px solid var(--rule);
  width: 100%;
}

.item:first-child .word {
  border-top: 0;
  padding-top: 0;
}

.down {
  font-size: 0.8rem;
  color: var(--accent);
  line-height: 1;
  padding-left: 0.1rem;
}

.note {
  margin-top: var(--space-md) !important;
  max-width: 28rem;
  font-size: 0.98rem !important;
  color: var(--mute) !important;
}
</style>
