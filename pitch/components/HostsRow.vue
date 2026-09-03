<template>
  <ul class="hosts">
    <li v-for="h in hosts" :key="h.slug">
      <img :src="h.src" alt="" width="28" height="28" />
      <span>{{ h.slug }}</span>
    </li>
  </ul>
</template>

<script setup lang="ts">
const base = import.meta.env.BASE_URL
const hosts = [
  { slug: 'cursor', src: `${base}hosts/cursor.png` },
  { slug: 'claude', src: `${base}hosts/claude.png` },
  { slug: 'chatgpt', src: `${base}hosts/chatgpt.png` },
]
</script>

<style scoped>
.hosts {
  display: flex;
  gap: var(--space-xl);
  list-style: none;
  margin: 0;
  padding: 0;
}

li {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  margin: 0 !important;
  font-size: 1.05rem;
  letter-spacing: -0.02em;
  color: var(--ink);
}

img {
  width: 28px;
  height: 28px;
  border-radius: 6px;
}
</style>
