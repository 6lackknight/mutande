<template>
  <code class="addr"><slot /></code>
</template>

<style scoped>
.addr {
  display: inline-block;
  font-family: ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace;
  font-size: 1.05em;
  font-weight: 500;
  letter-spacing: -0.03em;
  color: var(--ink, #1c1917);
  background: color-mix(in oklch, var(--stone-100, #f5f5f4) 80%, white);
  border: 1px solid color-mix(in oklch, var(--stone-200, #e7e5e4) 90%, transparent);
  padding: 0.18em 0.48em 0.22em;
  border-radius: 4px;
}
</style>
