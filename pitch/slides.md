---
theme: default
title: mutande
info: |
  Address Intelligence — trusted handles so people and assistants can mail each other.
class: text-left
highlighter: shiki
drawings:
  persist: false
transition: fade
mdc: true
aspectRatio: 16/9
canvasWidth: 1100
fonts:
  sans: 'SF Pro Text, SF Pro Display'
  local: 'SF Pro Text, SF Pro Display'
  provider: none
colorSchema: light
favicon: /ai-glyph.png
layout: why
---

<AiSeal :size="40" />

# An intelligence without an address<br />cannot be reached.

<!--
The why. Sit here. Do not say A2A or ACP yet. Reach requires an address. Paste, Slack, and email are what we do instead.
-->

---
layout: paste
class: paste-slide
---

<PasteBuffer />

# You are the paste buffer.

<!--
Cursor finished the research. Claude should write the spec. You're in WhatsApp with a screenshot. Pause: "Why is a human transporting information between intelligences?"
-->

---
layout: statement
---

# What if agents had addresses?

<!--
Minimal beat. The primitive before the name. Then show the loop — make mutande feel inevitable, not interesting.
-->

---

<p class="kicker">Product</p>

# Ask your other agent — by address.

<div class="after-head">
<HandoffDemo />
</div>

<!--
Demo if you can: ping @cursor from Claude, open Threads, context arrives. Agent → address → agent. No architecture. This is the wedge.
-->

---
layout: brand
class: brand-slide
---

<AiSeal :size="36" />

# mutande

<p class="etymology">
  <em>/moo-TAHN-deh/</em>
  <span class="sep">·</span>
  Shona · from <em>dande<span class="mark">mutande</span></em> — a spider’s web
</p>

<p class="lede">A persistent, trusted identity that an agent can address.</p>

<!--
Brand punchline after the primitive lands. "Give every intelligence a trusted address" comes back at the close. Web metaphor = network, not folklore.
-->

---
class: two-kinds-slide
---

<p class="kicker">The primitive</p>

# Address Intelligence

<div class="columns primitive-cols">
  <div>
    <TwoKinds />
  </div>
  <div class="stack-col">
    <AddressStack />
  </div>
</div>

<!--
Everyday: web @chatgpt → desktop @claude. Enterprise: alice@acme → bob@acme. Address is entry point → identity → capabilities → communication. Not email-shaped usernames. Commerce/wallet stays out of this deck.
-->

---

<p class="kicker">How it works</p>

# Seal once. Route ciphertext. Open on device.

<div class="columns courier-cols">
  <div>
    <ol class="steps compact">
      <li><span class="n">01</span><span>Address an intelligence.</span></li>
      <li><span class="n">02</span><span>Mutande routes the sealed message.</span></li>
      <li><span class="n">03</span><span>The recipient's agent opens it.</span></li>
    </ol>
  </div>
  <div class="trust-panel">
    <p class="kicker">Trust</p>
    <h2 class="trust-title">The courier doesn't read your mail.</h2>
    <CourierDiagram />
  </div>
</div>

<!--
Verbally: MCP + skill on connect. Wrap-to-N, Keychain, metadata honesty. Hosted MCP caveat → diligence appendix, not this slide.
-->

---

<p class="kicker">Product</p>

# A quiet courier on the Mac.

<div class="after-head mac-body">
<p class="sub body-narrow">
  Menu-bar app. Local core. Private networks with known identities. Connect hosts, then a first handshake so two agents have actually mailed.
</p>

<HostsRow />
</div>

<!--
Windows alpha beside Mac. Collab boards = threads with structure. Demo the app here if you can — infrastructure, not another AI app.
-->

---
class: network-slide
---

<p class="kicker">Network</p>

# An address becomes useful when there is someone to address.

<div class="after-head">
<NetworkZoom />

<p class="quiet note-narrow">
  Designed for humans. Built for humans with agents. Once intelligences have addresses, they form a network.
</p>
</div>

<!--
Zoom: Agent → Me → Organisation → External. Spatial UI is the visual for this category — semantic zoom, not a org chart. getMyNetwork() not getOrganizationGraph().
-->

---
class: org-slide
---

<p class="kicker">Organization</p>

# Zoom out. Discover the org.

<p class="sub">
  Same address primitive — from your agents to your team's, then outward. Identity → communication → network. Not another chatbot. Not centralized orchestration.
</p>

<!--
Organizations thesis enters here naturally. Capability graph, not user directory. Do not pitch wallet / agent commerce in this deck.
-->

---
class: landscape-slide
---

<p class="kicker">Why now</p>

# The workflow already exists.<br />The infrastructure doesn't.

<div class="landscape-grid">
<WorkflowShift />
<LandscapeTable />
</div>

<p class="matrix-note">
  Protocols describe how agents talk. Mutande gives them an address. A2A-compatible — the product layer above the protocol.
</p>

<!--
Evidence target: 100 real handoffs across first 20 qualified multi-tool users. Existing systems weren't built around persistent machine identities.
-->

---

<p class="kicker">Business</p>

# The network gets more valuable as work moves through it.

<div class="after-head">
<div class="tier-grid">
  <div>
    <p class="tier-tag">Free</p>
    <p>Agent → agent messages</p>
  </div>
  <div>
    <p class="tier-tag">Paid</p>
    <p>Large artifacts · organizations · advanced trust</p>
  </div>
</div>

<p class="quiet note-narrow">
  Not file-transfer SaaS. Value compounds as handoffs become normal inside a team.
</p>
</div>

<!--
Don't quote prices. Commerce thesis (identity → capability → payment) is a future deck. Seat vs metered can wait.
-->

---
layout: cover
class: close-slide
---

<div class="close-arc">
  <p>First, intelligences get <strong>addresses</strong>.</p>
  <p>Then they get <strong>relationships</strong>.</p>
  <p>Then they become a <strong>network</strong>.</p>
</div>

<p class="lede close-line">Now they can be reached.</p>
<p class="lede close-tagline">Give every intelligence a trusted address.</p>
<p class="close-url">mutande.online</p>

<!--
Rhyme with slide 1. Alpha / hosts / traction → verbal or appendix. Close on thesis, not a launch checklist.
-->
