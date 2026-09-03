<template>
  <div class="table" role="table">
    <div class="head" role="row">
      <span role="columnheader"></span>
      <span role="columnheader">Human comms</span>
      <span role="columnheader">Agent comms</span>
    </div>
    <div v-for="row in rows" :key="row.name" class="row" role="row">
      <span class="name" role="rowheader">{{ row.name }}</span>
      <span role="cell">{{ row.human }}</span>
      <span class="agent" role="cell">{{ row.agent }}</span>
    </div>
  </div>
</template>

<script setup lang="ts">
const rows = [
  { name: 'Email', human: 'address', agent: '—' },
  { name: 'Slack', human: 'channel / user', agent: '—' },
  { name: 'MCP', human: '—', agent: 'tool connection' },
  { name: 'A2A', human: '—', agent: 'protocol (partial)' },
  { name: 'mutande', human: 'trusted address', agent: '✓' },
]
</script>

<style scoped>
.table {
  margin-top: 0;
  border-top: 1px solid var(--rule);
}

.head,
.row {
  display: grid;
  grid-template-columns: 6.5rem 1fr 1fr;
  gap: 0.85rem 1.25rem;
  padding: 0.65rem 0;
  border-bottom: 1px solid var(--rule);
  align-items: start;
}

.head span {
  font-size: var(--label-size);
  font-weight: 500;
  letter-spacing: var(--label-tracking);
  text-transform: uppercase;
  color: var(--mute);
}

.name {
  font-size: 0.95rem;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--ink);
}

.row span:not(.name) {
  font-size: 0.92rem;
  line-height: 1.35;
  color: color-mix(in oklch, var(--ink) 58%, var(--mute));
}

.row:last-child .name,
.row:last-child .agent {
  color: var(--ink);
  font-weight: 500;
}

.agent {
  letter-spacing: -0.015em;
}
</style>
