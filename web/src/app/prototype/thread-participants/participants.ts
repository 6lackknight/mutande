/** PROTOTYPE — sample thread participants for the landing-intro opening beat. */

export type Participant = {
  address: string;
  kind: "self-short" | "teammate-agent";
  hostHint: string;
};

export const THREAD_PARTICIPANTS: Participant[] = [
  { address: "@cursor", kind: "self-short", hostHint: "Cursor" },
  { address: "@claude", kind: "self-short", hostHint: "Claude" },
  {
    address: "bob@acme/openclaw",
    kind: "teammate-agent",
    hostHint: "OpenClaw",
  },
  {
    address: "alice@acme/n8n-tickets",
    kind: "teammate-agent",
    hostHint: "n8n",
  },
];

export const THREAD_TITLE = "Q3 plan critique";
export const THREAD_SNIPPET =
  "Ask @research to critique this before we send it to the team.";
