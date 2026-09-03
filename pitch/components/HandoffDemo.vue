<template>
  <div class="demo">
    <p class="prompt">“What did Cursor find about the auth bug?”</p>
    <div class="flow">
      <div class="row">
        <span class="who">you</span>
        <span class="arrow" aria-hidden="true">→</span>
        <Handle>@cursor</Handle>
      </div>
      <div class="row muted">
        <span class="who">cursor</span>
        <span class="arrow" aria-hidden="true">→</span>
        <span>responds on the thread</span>
      </div>
      <div class="row">
        <span class="who">claude</span>
        <span class="arrow" aria-hidden="true">→</span>
        <span>opens the same context</span>
      </div>
    </div>
    <p class="foot">Same thread. Same context. You stay out of the middle.</p>
  </div>
</template>

<style scoped>
.demo {
  margin-top: 0;
  max-width: 34rem;
  display: flex;
  flex-direction: column;
  gap: var(--space-md);
}

.prompt {
  margin: 0 !important;
  font-size: 1.35rem !important;
  font-weight: 500;
  letter-spacing: -0.025em;
  color: var(--ink) !important;
  font-style: italic;
}

.flow {
  margin-top: 0;
  display: flex;
  flex-direction: column;
  border-top: 1px solid var(--rule);
}

.row {
  display: grid;
  grid-template-columns: 4.5rem 1.5rem 1fr;
  align-items: baseline;
  gap: 0.5rem;
  padding: 0.72rem 0;
  border-bottom: 1px solid var(--rule);
  font-size: 1.05rem;
  letter-spacing: -0.02em;
  color: var(--ink);
}

.row.muted {
  color: var(--mute);
}

.who {
  font-size: var(--label-size);
  font-weight: 500;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--accent);
}

.row.muted .who {
  color: var(--mute);
}

.arrow {
  text-align: center;
  color: var(--faint);
}

code {
  font-family: ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace;
  font-size: 1.02em;
  font-weight: 500;
}

.foot {
  margin-top: 0 !important;
  font-size: 0.95rem !important;
  color: var(--mute) !important;
}
</style>
