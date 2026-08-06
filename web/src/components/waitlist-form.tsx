"use client";

import { useState, type FormEvent } from "react";
import { WarpBackground } from "@/components/magicui/warp-background";
import { Alert, Button, ButtonLink, Field, Input } from "@/components/ui";

const AI_HOSTS = [
  "Cursor",
  "Claude Desktop",
  "Claude Code",
  "ChatGPT desktop",
  "ChatGPT (web)",
  "Windsurf",
  "GitHub Copilot",
  "Gemini",
  "Zed",
  "Other",
] as const;

const OS_OPTIONS = [
  "macOS",
  "macOS Intel",
  "Windows",
  "Linux",
  "Other",
] as const;

const SHARE_FREQUENCIES = [
  "Multiple times a day",
  "A few times a week",
  "Occasionally",
  "Rarely / never",
] as const;

const SHARE_METHODS = [
  "Copy / paste",
  "Email",
  "Google Drive / OneDrive / Dropbox",
  "Slack / chat",
  "Local files / notes app",
  "Other",
] as const;

function CheckboxGrid({
  options,
  selected,
  onToggle,
}: {
  options: readonly string[];
  selected: string[];
  onToggle: (value: string) => void;
}) {
  return (
    <div className="grid gap-2 sm:grid-cols-2">
      {options.map((option) => {
        const checked = selected.includes(option);
        return (
          <label
            key={option}
            className={`flex cursor-pointer items-center gap-2.5 rounded-md border px-3 py-2.5 text-[15px] transition ${
              checked
                ? "border-stone-400 bg-white/80 text-stone-900"
                : "border-stone-300/80 bg-white/50 text-stone-700 hover:border-stone-400 hover:bg-white/70"
            }`}
          >
            <input
              type="checkbox"
              checked={checked}
              onChange={() => onToggle(option)}
              className="size-4 rounded border-stone-300 text-stone-900 focus:ring-accent/30"
            />
            <span>{option}</span>
          </label>
        );
      })}
    </div>
  );
}

export function WaitlistForm() {
  const [email, setEmail] = useState("");
  const [aiHosts, setAiHosts] = useState<string[]>([]);
  const [oses, setOses] = useState<string[]>([]);
  const [shareFrequency, setShareFrequency] = useState<string>(
    SHARE_FREQUENCIES[1],
  );
  const [shareMethods, setShareMethods] = useState<string[]>([]);
  const [website, setWebsite] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function toggle(list: string[], value: string, setList: (v: string[]) => void) {
    setList(
      list.includes(value) ? list.filter((v) => v !== value) : [...list, value],
    );
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (aiHosts.length === 0) {
      setError("Pick at least one AI tool.");
      return;
    }
    if (oses.length === 0) {
      setError("Pick at least one OS.");
      return;
    }
    if (shareMethods.length === 0) {
      setError("Pick at least one way you move material between tools.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          ai_hosts: aiHosts,
          oses,
          share_frequency: shareFrequency,
          share_methods: shareMethods,
          website,
        }),
      });
      const data = (await res.json().catch(() => ({}))) as { error?: string };
      if (!res.ok) {
        throw new Error(data.error || "Could not join waitlist");
      }
      setDone(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setBusy(false);
    }
  }

  if (done) {
    return (
      <WarpBackground
        className="overflow-hidden border-stone-300/60 bg-stone-50/40 p-5 sm:p-6"
        gridColor="color-mix(in oklch, var(--stone-300) 55%, transparent)"
        beamsPerSide={2}
        beamDuration={4}
      >
        <div className="rounded-md border border-accent/30 bg-accent-soft/95 px-4 py-3 text-sm leading-relaxed text-stone-800 shadow-sm">
          <p className="font-medium text-stone-900">You’re on the list.</p>
          <p className="mt-1.5 text-stone-700">
            We’ll email when a spot opens — or grab the Mac alpha now if you
            want to poke around.
          </p>
          <ButtonLink
            href="/download"
            variant="secondary"
            className="mt-3 !py-2"
          >
            Try Alpha
          </ButtonLink>
        </div>
      </WarpBackground>
    );
  }

  return (
    <form onSubmit={onSubmit} className="space-y-5">
      <Field label="Email" hint="Where we can reach you.">
        <Input
          type="email"
          required
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@company.com"
        />
      </Field>

      <fieldset className="space-y-2">
        <legend className="text-[13px] font-medium tracking-wide text-stone-700">
          Which AI tools do you use?
        </legend>
        <p className="text-xs text-muted">Select all that apply.</p>
        <CheckboxGrid
          options={AI_HOSTS}
          selected={aiHosts}
          onToggle={(v) => toggle(aiHosts, v, setAiHosts)}
        />
      </fieldset>

      <fieldset className="space-y-2">
        <legend className="text-[13px] font-medium tracking-wide text-stone-700">
          What OS do you use?
        </legend>
        <p className="text-xs text-muted">
          Select all that apply. v1 alpha is macOS-first.
        </p>
        <CheckboxGrid
          options={OS_OPTIONS}
          selected={oses}
          onToggle={(v) => toggle(oses, v, setOses)}
        />
      </fieldset>

      <Field label="How often do you share text, docs, or context between your different AI tools?">
        <select
          required
          value={shareFrequency}
          onChange={(e) => setShareFrequency(e.target.value)}
          className="w-full rounded-md border border-stone-300/80 bg-white/70 px-3 py-2.5 text-[15px] text-foreground outline-none transition focus:border-accent focus:ring-2 focus:ring-accent/20"
        >
          {SHARE_FREQUENCIES.map((opt) => (
            <option key={opt} value={opt}>
              {opt}
            </option>
          ))}
        </select>
      </Field>

      <fieldset className="space-y-2">
        <legend className="text-[13px] font-medium tracking-wide text-stone-700">
          How do you usually move that material?
        </legend>
        <p className="text-xs text-muted">Select all that apply.</p>
        <CheckboxGrid
          options={SHARE_METHODS}
          selected={shareMethods}
          onToggle={(v) => toggle(shareMethods, v, setShareMethods)}
        />
      </fieldset>

      {/* Honeypot — leave empty */}
      <div aria-hidden className="absolute -left-[9999px] h-0 w-0 overflow-hidden">
        <label>
          Website
          <input
            tabIndex={-1}
            autoComplete="off"
            value={website}
            onChange={(e) => setWebsite(e.target.value)}
          />
        </label>
      </div>

      {error ? <Alert tone="danger">{error}</Alert> : null}

      <Button type="submit" disabled={busy} className="w-full sm:w-auto">
        {busy ? "Joining…" : "Join waitlist"}
      </Button>
    </form>
  );
}
