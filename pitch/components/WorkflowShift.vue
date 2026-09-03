<template>
  <div class="shift">
    <div class="panel">
      <p class="tag">Today</p>
      <div class="hosts">
        <span>Cursor</span>
        <span>Claude</span>
        <span>ChatGPT</span>
      </div>
      <p class="via">human · copy / paste</p>
    </div>
    <div class="panel tomorrow">
      <p class="tag">Tomorrow</p>
      <div class="pair">
        <span>Cursor</span>
        <span class="link">mutande</span>
        <span>Claude</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.shift {
  margin-top: 0;
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--space-xl);
  max-width: none;
}

.panel {
  padding-top: var(--space-sm);
  border-top: 1px solid var(--rule);
}

.tag {
  margin: 0 !important;
  font-size: var(--label-size) !important;
  font-weight: 500;
  letter-spacing: var(--label-tracking);
  text-transform: uppercase;
  color: var(--accent);
}

.hosts {
  margin-top: 0.85rem;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  font-size: 1.05rem;
  font-weight: 500;
  letter-spacing: -0.02em;
  color: var(--ink);
}

.via {
  margin-top: 0.75rem !important;
  font-size: 0.95rem !important;
  color: var(--mute) !important;
}

.pair {
  margin-top: 0.85rem;
  display: flex;
  align-items: center;
  gap: 0.65rem;
  flex-wrap: wrap;
  font-size: 1.05rem;
  font-weight: 500;
  letter-spacing: -0.02em;
  color: var(--ink);
}

.link {
  font-size: 0.68rem;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--accent);
}
</style>
