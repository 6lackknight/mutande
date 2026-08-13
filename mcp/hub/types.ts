/** Hub wire types for L2 app_envelope inbox (matches hub/store/types.ts). */

export type ThreadEncryptionMode = "e2e" | "app_envelope";
export type ThreadFilter = "needs_action" | "open" | "closed";

export interface AppEnvelopePayload {
  version: number;
  subject?: string;
  context?: string;
  notes?: string;
  ping_kind?: "health" | "thread";
  questions?: unknown[];
  answers?: unknown[];
  resources?: unknown[];
  resource_requests?: unknown[];
  in_reply_to?: string;
  [key: string]: unknown;
}

export interface ThreadMeta {
  id: string;
  kind: "direct" | "broadcast";
  status: "open" | "closed";
  from: string;
  from_user_id: string;
  from_agent_id?: string;
  audience: string;
  audience_agent_id?: string;
  audience_wire_path?: string;
  org_id: string;
  participant_count: number;
  reply_count: number;
  your_status?: "pending" | "replied";
  created_at: string;
  updated_at: string;
  /** Legacy rows may omit — treat as e2e. */
  encryption_mode?: ThreadEncryptionMode;
  last_from?: string;
  last_subject?: string;
  last_preview?: string;
}

export interface ThreadMessage {
  id: string;
  thread_id: string;
  from_user_id: string;
  from_handle: string;
  from_agent_id?: string;
  envelope?: unknown;
  app_envelope?: AppEnvelopePayload;
  content_store?: "e2e" | "app_envelope";
  created_at: string;
  sender_only?: boolean;
  parent_message_id?: string;
}

export interface ThreadDetail {
  thread: ThreadMeta;
  messages: ThreadMessage[];
}

export interface CreateThreadResponse {
  thread: ThreadMeta;
  message_id: string;
}

export interface ReplyResponse {
  message_id: string;
}

export type AgentTransport = "sidecar" | "mcp";

export interface HubAgentRow {
  id: string;
  user_id: string;
  slug: string;
  created_at: string;
  transport?: AgentTransport | string;
  mcp_endpoint?: string | null;
  [key: string]: unknown;
}

export interface Contact {
  handle: string;
  pubkey: string | null;
  devices: Array<{ pubkey: string; platform: string }>;
  kind?: "org" | "external" | "broadcast";
  avatar_url?: string;
  display_name?: string;
  external_link_id?: string;
  linked_at?: string;
  thread_id?: string;
}

export interface MessageUpvote {
  agent_id: string;
  from_handle: string;
  created_at: string;
}

export interface MessageUpvoteSummary {
  count: number;
  upvotes: MessageUpvote[];
  your_upvotes?: string[];
}

export interface ToggleUpvoteResponse {
  upvoted: boolean;
  upvotes: MessageUpvoteSummary;
}

export interface CloseThreadResponse {
  thread: ThreadMeta;
}

export interface DeleteThreadResponse {
  ok: true;
}

export interface AgentsListResponse {
  agents: HubAgentRow[];
  default_agent_id: string | null;
  transport_defaults?: Record<string, AgentTransport>;
}
