# Mutande Design Principles

> This document is not a marketing document.
> It exists to define the product philosophy that should influence every design, animation, interaction and piece of copy across Mutande.

---

# The Question

Every successful internet primitive answered a simple question.

DNS answered:

> Where is it?

Email answered:

> Who do I send this to?

HTTP answered:

> How do I retrieve it?

Git answered:

> How do I share code?

Mutande answers:

> **Who—or what—am I talking to?**

---

# The Primitive

Mutande is not email.

Mutande is not an AI platform.

Mutande is not an orchestration engine.

Mutande introduces a new primitive:

**An addressable intelligence.**

Every person has an address.

Every assistant has an address.

Every workflow has an address.

Every team has an address.

Everything capable of receiving work should have an address.

---

# The Address

```text
tawanda@snakenationco
```

Represents a person.

```text
tawanda@snakenationco/jarvis
```

Represents one of Tawanda's assistants.

Not a Claude instance.

Not GPT.

Not OpenClaw.

Simply **Jarvis**.

A stable identity.

The implementation behind that identity is irrelevant.

---

# Handles Describe Identity

Handles never describe implementation.

Good

```text
/research
/design
/travel
/jarvis
/reviewer
```

Bad

```text
/claude
/gpt
/openai
/llama
```

Those may be implementations today.

Tomorrow they may change.

The address must not.

---

# Stable Identity

Today

```text
tawanda@snakenationco/jarvis
```

might execute using Claude.

Tomorrow

the same address might execute using:

- GPT
- OpenClaw
- a local model
- multiple models
- a human

Nobody messaging that address should care.

Identity is stable.

Implementation evolves.

---

# Ownership

Today's AI belongs to vendors.

```
Claude Account
Cursor Account
ChatGPT Account
Gemini Account
```

Mutande changes ownership.

```
Tawanda

├── Jarvis
├── Research
├── Design
└── Travel
```

The assistants belong to their owner.

Not the AI provider.

---

# Namespace

Users reserve an organisation handle.

```
snakenationco
```

Everything lives underneath it.

```
tawanda@snakenationco

alice@snakenationco

finance@snakenationco

support@snakenationco
```

Every organisation becomes its own trusted namespace.

---

# Delegation

Mutande is fundamentally about delegation.

Not chatting.

Not prompting.

Not AI conversations.

Work moves.

```text
Human

↓

Assistant

↓

Another Assistant

↓

Human Approval

↓

Completion
```

Messaging is simply how work travels.

---

# The Web

The name Mutande means spider's web.

The web is not decoration.

It is the architecture.

Every identity is a node.

Every message is a thread.

Every organisation becomes its own intelligent web.

---

# The Mental Model

Do not compare Mutande to:

- Slack
- Discord
- Email

Compare it to:

- Addresses
- DNS
- URLs
- Git repositories
- Unix paths

These systems succeeded because they introduced intuitive naming.

Mutande should feel equally inevitable.

---

# Show The Primitive

The homepage should not explain Mutande.

It should expose the primitive.

Seeing this should create curiosity.

```text
tawanda@snakenationco

├── /jarvis
├── /research
├── /travel
└── /weekend
```

People naturally ask:

"What is /weekend?"

Perfect.

That curiosity is stronger than paragraphs of explanation.

---

# Don't Sell Encryption

Encryption is expected.

Nobody buys a road because of the asphalt.

They buy it because it connects places.

Encryption should quietly establish trust.

It should not be the headline.

---

# Don't Sell AI

AI changes.

Models change.

Providers change.

Mutande is about identity.

AI is simply one possible implementation.

---

# Every Intelligence Deserves An Address

Not just people.

Not just models.

Everything capable of receiving work.

```
finance@company

legal@company

alice@company/review

tawanda@company/jarvis
```

---

# Visual Language

Avoid dashboards.

Avoid floating windows.

Avoid AI sparkles.

Avoid glowing brains.

Avoid robots.

Instead show:

- addresses
- identity trees
- threads
- delegation
- routing
- encrypted packets
- approvals
- graphs
- connected nodes

The product should feel infrastructural.

Like Git.

Like SSH.

Like email.

Like DNS.

---

# Hero Principle

The hero should make people think:

"I've never seen addresses used like that before."

Not:

"This looks like another AI startup."

---

# Copy Principles

Avoid:

- AI-powered
- AI platform
- orchestration
- identity layer
- infrastructure
- enterprise
- next-generation
- revolutionary

Prefer:

- address
- send
- receive
- delegate
- route
- identity
- namespace
- handle
- organisation
- assistant

Use concrete language.

Never abstract language.

---

# Design North Star

Mutande should feel less like software.

More like discovering a missing internet primitive.

The same feeling developers get when they first understand:

- URLs
- Git
- SSH
- Docker images
- Unix paths

The reaction we're aiming for isn't:

"That's a nice SaaS."

It's:

> "Of course AI should have addresses."