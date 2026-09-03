<template>
  <div class="chain">
    <div class="step">
      <img src="/hosts/cursor.png" alt="Cursor" width="26" height="26" />
      <span class="label">Cursor</span>
      <span class="say">“Here’s what I found…”</span>
    </div>
    <div class="down" aria-hidden="true">↓</div>
    <div class="step you">
      <span class="label">You</span>
      <span class="say">copy · open Claude · paste · “Continue…”</span>
    </div>
    <div class="down" aria-hidden="true">↓</div>
    <div class="step">
      <img src="/hosts/claude.png" alt="Claude" width="26" height="26" />
      <span class="label">Claude</span>
    </div>
  </div>
</template>

<style scoped>
.chain {
  margin-top: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.35rem;
  max-width: 22rem;
}

.step {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.55rem 0.75rem;
  padding: 0.55rem 0;
  width: 100%;
  border-top: 1px solid var(--rule);
}

.step:last-of-type {
  border-bottom: 1px solid var(--rule);
}

.step img {
  width: 26px;
  height: 26px;
  border-radius: 6px;
}

.label {
  font-size: 1.05rem;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--ink);
}

.step.you .label {
  color: var(--accent);
}

.say {
  font-size: 0.95rem;
  color: var(--mute);
  letter-spacing: -0.01em;
}

.down {
  font-size: 0.85rem;
  color: var(--faint);
  line-height: 1;
  padding-left: 0.15rem;
}
</style>
