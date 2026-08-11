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
const pending: Array<{
  event: string;
  props?: Record<string, string | number | boolean>;
}> = [];

type TrackProps = Record<string, string | number | boolean | undefined>;

function cleanProps(
  props?: TrackProps,
): Record<string, string | number | boolean> | undefined {
  if (!props) return undefined;
  const clean: Record<string, string | number | boolean> = {};
  for (const [k, v] of Object.entries(props)) {
    if (v === undefined) continue;
    if (/email|handle|password|token/i.test(k)) continue;
    clean[k] = v;
  }
  return clean;
}

export function initMixpanel(): void {
  if (ready || typeof window === "undefined") return;
  mixpanel.init(TOKEN, {
    autocapture: true,
    // Full session replay on every visit hammers TBT; sample instead.
    record_sessions_percent: 10,
  });
  ready = true;
  for (const item of pending.splice(0)) {
    mixpanel.track(item.event, item.props);
  }
}

export function track(event: string, props?: TrackProps): void {
  const clean = cleanProps(props);
  if (!ready) {
    pending.push({ event, props: clean });
    return;
  }
  mixpanel.track(event, clean);
}

/** Stable Auth0 subject only — do not pass email. */
export function identifyAuth0Sub(sub: string): void {
  if (!ready || !sub) return;
  mixpanel.identify(sub);
}

export { AnalyticsEvent } from "@/lib/analytics-events";
