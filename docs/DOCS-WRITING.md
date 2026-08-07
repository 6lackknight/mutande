# mutande docs writing guide

A reference for tone, structure, and voice across all mutande documentation.
Use the rewritten Architecture page as a worked example.

---

## The core principle

Every page should feel like a knowledgeable colleague wrote it — not a precise engineer, not a marketing team. Accurate and warm at the same time.

The test: after reading a page, does the reader feel more confident, or just more informed? Both matter. Confidence comes from understanding *why*, not just *what*.

---

## Tone rules

**1. State the fact, then earn the trust — in the same sentence.**

Don't: "The hub stores only ciphertext."
Do: "The hub stores only ciphertext — so even if it were compromised, your work stays private."

The clause after the dash is what turns a spec into a reassurance. Use it for any statement that touches trust, privacy, or security.

**2. Open every page with an orienting sentence.**

Before the first heading or table, give the reader one sentence that answers: *what is this page, and why should I care?* Don't make them infer it from the title.

Don't: jump straight to a table or numbered list.
Do: "This page explains how the five pieces of mutande fit together — useful mental model before you dig into security or agents."

**3. Write the "who this is for" bullet last in spirit, not first.**

The most cautious or hedged statement should never open a section. Lead with the most inviting framing, end with the precise one.

**4. Explain constraints as features, not warnings.**

Don't: "There is no background poll in the skill."
Do: "Agents don't poll on a timer — cold delivery is the Mac app's job, which keeps agent sessions focused on the user's work."

The constraint is real. The framing is what changes the reader's reaction.

**5. Use bold for concepts, not for emphasis.**

Bold is for terms — **thread**, **bundle**, **envelope** — not for making sentences feel more important. If a sentence needs bold to land, rewrite the sentence.

---

## Structure rules

**Pages have three parts:**

1. One-sentence orienting opener (no heading needed)
2. The content (tables, steps, lists)
3. A closing pointer to what's next or where to go deeper

Don't end a page cold. Even one line — "Details: [security] · [handles]" — closes the loop.

**Tables are for reference, prose is for understanding.**

Use tables for lookups (glossary, address formats, piece roles). Use prose when you're explaining a relationship or a reason. Don't put explanatory content in table cells — if a cell needs more than one clause, it belongs in a paragraph.

**Numbered steps imply sequence — only use them when order matters.**

If the steps can be done in any order, use bullets. If skipping step 2 breaks step 3, use numbers and say so.

---

## Voice

- Write in second person ("you", "your agent") for how-to content
- Write in third person for reference content ("the hub", "the Mac app")
- Never use "simply", "just", "easily" — they make hard things feel dismissive
- Contractions are fine: "it's", "you're", "don't"
- Lowercase product name always: **mutande**, not Mutande
