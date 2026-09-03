<template>
  <div class="zoom">
    <div class="level">
      <p class="tag">You</p>
      <div class="nodes me">
        <span><img :src="`${base}hosts/cursor.png`" alt="" width="22" height="22" /> cursor</span>
        <span><img :src="`${base}hosts/claude.png`" alt="" width="22" height="22" /> claude</span>
        <span><img :src="`${base}hosts/chatgpt.png`" alt="" width="22" height="22" /> chatgpt</span>
      </div>
    </div>
    <div class="level">
      <p class="tag">Your org</p>
      <div class="nodes org">
        <span>Engineering</span>
        <span>Finance</span>
        <span>Operations</span>
      </div>
    </div>
    <div class="level faint">
      <p class="tag">External</p>
      <div class="nodes ext">
        <span>Partner org</span>
        <span class="dot">·</span>
        <span>Client org</span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const base = import.meta.env.BASE_URL
</script>

<style scoped>
.zoom {
  margin-top: 0;
  display: flex;
  flex-direction: column;
  gap: var(--space-sm);
  max-width: 38rem;
}

.level {
  padding: var(--space-sm) 0 0;
  border-top: 1px solid var(--rule);
}

.level.faint {
  opacity: 0.85;
}

.tag {
  margin: 0 !important;
  font-size: var(--label-size) !important;
  font-weight: 500;
  letter-spacing: var(--label-tracking);
  text-transform: uppercase;
  color: var(--accent);
}

.nodes {
  margin-top: 0.65rem;
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem 1.25rem;
  align-items: center;
  font-size: 1rem;
  letter-spacing: -0.02em;
  color: var(--ink);
}

.nodes.me span {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
}

.nodes.me img {
  border-radius: 5px;
}

.nodes.ext {
  color: var(--mute);
}

.dot {
  color: var(--faint);
}
</style>
