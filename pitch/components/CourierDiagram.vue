<template>
  <div class="diagram">
    <div class="agent">Agent A</div>
    <div class="line">
      <span class="cap">encrypt locally</span>
      <span class="stem" aria-hidden="true">│</span>
    </div>
    <div class="hub">
      <span class="hub-title">Hub</span>
      <span class="hub-sub">ciphertext only</span>
    </div>
    <div class="line">
      <span class="stem" aria-hidden="true">│</span>
    </div>
    <div class="agent">Agent B</div>
    <div class="line last">
      <span class="cap">decrypt locally</span>
      <span class="stem" aria-hidden="true">│</span>
    </div>
  </div>
  <p class="one">Mutande knows where the message goes — not what it says.</p>
</template>

<script setup lang="ts">
defineOptions({ inheritAttrs: false })
</script>

<style scoped>
.diagram {
  margin-top: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0;
  max-width: 12rem;
}

.agent {
  font-size: 1.05rem;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--ink);
}

.line {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.15rem;
  padding: 0.35rem 0 0.35rem 0.5rem;
}

.line.last {
  padding-bottom: 0;
}

.stem {
  font-size: 0.9rem;
  color: color-mix(in oklch, var(--accent) 50%, var(--faint));
  line-height: 1;
}

.cap {
  font-size: 0.68rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--mute);
}

.hub {
  margin: 0.15rem 0 0.15rem 0;
  padding: 0.65rem 1rem;
  border: 1px solid var(--rule);
  border-radius: 4px;
  background: color-mix(in oklch, var(--stone-100) 70%, white);
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.hub-title {
  font-size: 0.72rem;
  font-weight: 600;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--ink);
}

.hub-sub {
  font-size: 0.85rem;
  color: var(--mute);
}

.one {
  margin-top: var(--space-md) !important;
  max-width: 26rem;
  font-size: 1.15rem !important;
  font-weight: 500;
  letter-spacing: -0.02em;
  color: var(--ink) !important;
}
</style>
