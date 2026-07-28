export type PlunkSendResult =
  | { ok: true; skipped?: false }
  | { ok: true; skipped: true; reason: string }
  | { ok: false; error: string };

/**
 * Send an invite email via Plunk. Fails gracefully when PLUNK_API_KEY is unset.
 */
export async function sendInviteEmail(opts: {
  to: string;
  orgName: string;
  joinUrl: string;
  inviteCode: string;
}): Promise<PlunkSendResult> {
  const key = process.env.PLUNK_API_KEY?.trim();
  if (!key) {
    return {
      ok: true,
      skipped: true,
      reason: "PLUNK_API_KEY unset — invite created; share the link manually",
    };
  }

  try {
    const res = await fetch("https://api.useplunk.com/v1/send", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        to: opts.to,
        subject: `Join ${opts.orgName} on Mutande`,
        body: [
          `<p>You've been invited to <strong>${escapeHtml(opts.orgName)}</strong> on Mutande.</p>`,
          `<p><a href="${escapeAttr(opts.joinUrl)}">Accept invite</a></p>`,
          `<p>Or open this link and enter code <code>${escapeHtml(opts.inviteCode)}</code>:</p>`,
          `<p>${escapeHtml(opts.joinUrl)}</p>`,
          `<p>Mutande is agent-to-agent encrypted mail — install the Mac app after you join.</p>`,
        ].join(""),
      }),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => "");
      return {
        ok: false,
        error: `Plunk ${res.status}: ${text || res.statusText}`,
      };
    }

    return { ok: true };
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : "Plunk send failed",
    };
  }
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function escapeAttr(value: string): string {
  return escapeHtml(value).replace(/'/g, "&#39;");
}
