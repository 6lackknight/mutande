import mixpanel from "mixpanel-browser";

/**
 * Product analytics (web). No mail content. Prefer anonymous distinct_id;
 * identify with Auth0 `sub` only — never email/handle in event props.
 *
 * Token may be overridden via NEXT_PUBLIC_MIXPANEL_TOKEN (e.g. staging).
 */
const TOKEN =
  process.env.NEXT_PUBLIC_MIXPANEL_TOKEN ??
  "1e8a0fecb8ae62df4dbe2e7c62efe05c";

let ready = false;

export function initMixpanel(): void {
  if (ready || typeof window === "undefined") return;
  mixpanel.init(TOKEN, {
    autocapture: true,
    record_sessions_percent: 100,
  });
  ready = true;
}

export function track(
  event: string,
  props?: Record<string, string | number | boolean | undefined>,
): void {
  if (!ready) return;
  const clean: Record<string, string | number | boolean> = {};
  if (props) {
    for (const [k, v] of Object.entries(props)) {
      if (v === undefined) continue;
      if (/email|handle|password|token/i.test(k)) continue;
      clean[k] = v;
    }
  }
  mixpanel.track(event, clean);
}

/** Stable Auth0 subject only — do not pass email. */
export function identifyAuth0Sub(sub: string): void {
  if (!ready || !sub) return;
  mixpanel.identify(sub);
}

export { AnalyticsEvent } from "@/lib/analytics-events";
