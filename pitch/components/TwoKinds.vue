<template>
  <div class="kinds">
    <section>
      <p class="kind-kicker">Everyday</p>
      <div class="path">
        <div class="end">
          <img src="/hosts/chatgpt.png" alt="ChatGPT" width="28" height="28" />
          <div class="meta">
            <Handle>@chatgpt</Handle>
            <span class="where">web</span>
          </div>
        </div>
        <div class="arrow" aria-hidden="true"><span>handoff</span></div>
        <div class="end">
          <img src="/hosts/claude.png" alt="Claude" width="28" height="28" />
          <div class="meta">
            <Handle>@claude</Handle>
            <span class="where">desktop</span>
          </div>
        </div>
      </div>
      <p class="kind-copy">You and your agents, across hosts. The paste buffer retires.</p>
    </section>

    <section>
      <p class="kind-kicker">Enterprise</p>
      <div class="path">
        <div class="end">
          <div class="meta">
            <Handle>alice@acme</Handle>
          </div>
        </div>
        <div class="arrow" aria-hidden="true"><span>handoff</span></div>
        <div class="end">
          <div class="meta">
            <Handle>bob@acme</Handle>
          </div>
        </div>
      </div>
      <p class="kind-copy">
        Private networks. Known identities. The hub routes ciphertext — not the contents.
      </p>
    </section>
  </div>
</template>

<style scoped>
.kinds {
  margin-top: 0;
  display: flex;
  flex-direction: column;
  gap: 0;
  max-width: 40rem;
}

section {
  padding: 1.05rem 0 1.15rem;
  border-top: 1px solid var(--rule);
}

section:last-child {
  border-bottom: 1px solid var(--rule);
  padding-bottom: 1.2rem;
}

.kind-kicker {
  margin: 0 0 0.7rem !important;
  font-size: var(--label-size) !important;
  font-weight: 500;
  letter-spacing: var(--label-tracking);
  text-transform: uppercase;
  color: var(--accent);
}

.path {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  gap: 0.85rem;
}

.end {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  min-width: 0;
}

.end img {
  width: 28px;
  height: 28px;
  border-radius: 6px;
  flex-shrink: 0;
}

.meta {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.2rem;
  min-width: 0;
}

.where {
  font-size: 0.68rem;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--mute);
}

.arrow {
  position: relative;
  width: 5.5rem;
  height: 1px;
  background: color-mix(in oklch, var(--accent) 55%, var(--faint));
}

.arrow span {
  position: absolute;
  left: 50%;
  top: -0.95rem;
  transform: translateX(-50%);
  font-size: 0.62rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--accent);
  white-space: nowrap;
}

.kind-copy {
  margin: 0.75rem 0 0 !important;
  font-size: 1.02rem !important;
  line-height: 1.4;
  color: var(--mute) !important;
  max-width: 32rem;
}
</style>
