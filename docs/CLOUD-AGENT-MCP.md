# Cursor Cloud Agent MCP Support

## Overview

Enable Cursor Cloud Agents to connect to the Mutande hosted MCP server for agent-to-agent collaboration.

**Current state:**
- Hosted MCP (`https://mcp.mutande.online/mcp`) supports ChatGPT web and Claude.ai
- Authentication: Auth0 OAuth via user browser flow
- Desktop Cursor: local `mutande-core` daemon via Unix socket

**Goal:**
- Add Cloud Agent authentication support to hosted MCP
- Enable Cloud Agents to use collaboration tools (`list_threads`, `forward_draft`, etc.)

---

## Architecture Analysis

### Current Auth Flow (ChatGPT/Claude.ai)

1. User adds MCP connector URL in host settings
2. Host performs OAuth DCR (Dynamic Client Registration) against Auth0
3. User completes Auth0 Universal Login in browser
4. Host obtains access token with `aud: https://mcp.mutande.online`
5. Host sends `Authorization: Bearer <token>` on every MCP request
6. MCP verifies JWT via Auth0 JWKS, binds session to hub user

### Cloud Agent Requirements

**Challenge:** Cloud Agents run autonomously in VMs without user browser interaction.

**Options:**

#### Option 1: Service Account Tokens (Preferred)
- Cloud Agent obtains service account JWT from Cursor infrastructure
- MCP adds verification path for Cursor-issued tokens
- Mapping: Cloud Agent identity → Mutande user/org

#### Option 2: Long-lived User Tokens
- User generates long-lived access token via Auth0
- Stored in Cloud Agent secrets (Cursor Dashboard → Cloud Agents → Secrets)
- MCP continues using existing Auth0 JWT verification

#### Option 3: API Key Authentication
- Generate Mutande-specific API keys per user/org
- Store in Cloud Agent secrets
- MCP adds API key → user resolution path

---

## Implementation Plan

### Phase 1: Support Long-lived Auth0 Tokens (Quick Path)

**Advantages:**
- Uses existing Auth0 infrastructure
- No MCP auth changes required
- User can generate token and add to secrets

**Steps:**

1. **User Setup Flow:**
   - User authenticates via Mutande Mac or web
   - Generate long-lived access token (Auth0 M2M or Refresh Token)
   - Add to Cursor Dashboard secrets: `MUTANDE_ACCESS_TOKEN`

2. **Cloud Agent Configuration:**
   - Cloud Agent reads `MUTANDE_ACCESS_TOKEN` from environment
   - Automatically configures MCP client with token
   - No OAuth browser flow needed

3. **Documentation:**
   - Create setup guide for Cloud Agent users
   - Token generation instructions
   - Secret configuration steps

**Implementation Tasks:**

```typescript
// No server changes needed - existing auth already supports Bearer tokens
// Cloud Agent needs to configure MCP client with env token

// User generates token:
// Mac: mutande-core stores access token in ~/.mutande/
// Web: new API endpoint to generate long-lived token
```

---

### Phase 2: Service Account Integration (Robust Path)

**Advantages:**
- Automatic authentication
- No manual token management
- Scoped to specific Cloud Agent run
- Revocable per-run credentials

**Architecture:**

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────┐
│ Cloud Agent VM  │────▶│ Cursor Auth API  │────▶│ Mutande MCP  │
│                 │     │ (service token)  │     │ (verifies)   │
└─────────────────┘     └──────────────────┘     └──────────────┘
         │                                                │
         │                                                ▼
         │                                        ┌──────────────┐
         └───────────────────────────────────────▶│ Hub API      │
                  (forwards user context)         └──────────────┘
```

**Implementation Tasks:**

1. **Cursor Service Token Verification (MCP side)**

   ```typescript
   // mcp/auth/cursor_cloud.ts
   
   export interface CursorCloudClaims {
     sub: string;              // Cloud Agent run ID
     user_id: string;          // Cursor user ID
     email?: string;           // User email
     team_id?: string;         // Team ID
     agent_run_id: string;     // Unique run identifier
   }
   
   export function createCursorCloudVerifier(): TokenVerifier {
     // Verify tokens issued by Cursor Cloud infrastructure
     // JWKS from cursor.com/.well-known/jwks.json (or cloud-specific endpoint)
     const jwks = jose.createRemoteJWKSet(
       new URL('https://api.cursor.com/.well-known/jwks.json')
     );
     
     return {
       async verifyAccessToken(token: string): Promise<CursorCloudClaims> {
         const { payload } = await jose.jwtVerify(token, jwks, {
           issuer: 'https://api.cursor.com',
           audience: 'https://mcp.mutande.online',
         });
         // Map to our Auth0Claims structure for hub binding
         return extractCloudClaims(payload);
       }
     };
   }
   ```

2. **Multi-Verifier Support**

   ```typescript
   // mcp/routes/mcp.ts - update authenticate()
   
   async function authenticate(
     authorization: string | undefined,
   ): Promise<{ token: string; claims: Auth0Claims; source: 'auth0' | 'cursor_cloud' } | Response> {
     const token = bearerTokenFromHeader(authorization);
     if (!token) return unauthorized("missing");
     
     // Try Auth0 first (existing users)
     try {
       const claims = await auth0Verifier.verifyAccessToken(token);
       return { token, claims, source: 'auth0' };
     } catch (auth0Error) {
       // Try Cursor Cloud service account
       try {
         const claims = await cursorCloudVerifier.verifyAccessToken(token);
         return { token, claims, source: 'cursor_cloud' };
       } catch {
         return unauthorized("invalid");
       }
     }
   }
   ```

3. **User Mapping (Hub side)**

   ```typescript
   // hub/ - new endpoint for Cloud Agent linking
   
   // POST /v1/cloud-agents/link
   // Body: { cursor_user_id, email, agent_run_id }
   // Returns: { mutande_user_id, handle, org }
   //
   // Links Cursor user to Mutande account (one-time setup per user)
   // Subsequent Cloud Agent runs auto-resolve via cursor_user_id
   ```

4. **Configuration**

   ```typescript
   // mcp/config.ts additions
   
   export interface McpConfig {
     // ... existing fields
     cursorCloudEnabled: boolean;
     cursorCloudJwksUrl: string;
     cursorCloudIssuer: string;
   }
   
   export function loadConfig(env): McpConfig {
     // ...
     cursorCloudEnabled: env.get("CURSOR_CLOUD_ENABLED") === "true",
     cursorCloudJwksUrl: env.get("CURSOR_CLOUD_JWKS_URL") || 
       "https://api.cursor.com/.well-known/jwks.json",
     cursorCloudIssuer: env.get("CURSOR_CLOUD_ISSUER") || 
       "https://api.cursor.com",
   }
   ```

---

### Phase 3: Cloud Agent Auto-Configuration

**Goal:** Seamless MCP setup for Cloud Agents without manual config.

**Approach:**

1. **Cursor Cloud Infrastructure Changes:**
   - Pre-configure Mutande MCP for Cloud Agents
   - Inject service token as environment variable
   - Auto-detect mutande workspace and enable MCP

2. **Workspace Detection:**
   ```typescript
   // Cloud Agent startup checks:
   // - Presence of /workspace/mcp/ directory
   // - AGENTS.md mentions mutande
   // - Auto-enable MCP client if detected
   ```

3. **Environment Variables (injected by Cursor):**
   ```bash
   MUTANDE_MCP_ENABLED=true
   MUTANDE_MCP_URL=https://mcp.mutande.online/mcp
   CURSOR_CLOUD_TOKEN=<service-account-jwt>
   ```

---

## Configuration Files

### Cloud Agent `.mcp.json` (auto-generated)

```json
{
  "mcpServers": {
    "mutande": {
      "transport": "http",
      "url": "https://mcp.mutande.online/mcp",
      "auth": {
        "type": "bearer",
        "token": "${CURSOR_CLOUD_TOKEN}"
      },
      "headers": {
        "Accept": "application/json, text/event-stream",
        "X-Mutande-Agent-Slug": "cursor-cloud"
      }
    }
  }
}
```

### Environment Configuration

**Deno Deploy (MCP) additions:**
```bash
CURSOR_CLOUD_ENABLED=true
CURSOR_CLOUD_JWKS_URL=https://api.cursor.com/.well-known/jwks.json
CURSOR_CLOUD_ISSUER=https://api.cursor.com
```

---

## User Flow

### Phase 1 (Manual Setup)

1. **User generates token:**
   - Open Mutande Mac app or web dashboard
   - Settings → Cloud Agents → Generate Token
   - Copy long-lived access token

2. **Configure Cloud Agent:**
   - Cursor Dashboard → Cloud Agents → Secrets
   - Add: `MUTANDE_ACCESS_TOKEN=<token>`
   - Restart or start new Cloud Agent

3. **Cloud Agent auto-configures:**
   - Reads `MUTANDE_ACCESS_TOKEN` from env
   - Creates `~/.cursor/mcp.json` with token
   - MCP tools become available

### Phase 2 (Automatic)

1. **User links Cursor account:**
   - One-time: Mutande web → Settings → Link Cursor Account
   - OAuth flow connects Cursor user to Mutande org

2. **Cloud Agent launches:**
   - Cursor injects service token automatically
   - MCP auto-configures (no user action needed)
   - Agent can immediately use collaboration tools

---

## Testing Plan

### Unit Tests

```typescript
// mcp/auth/cursor_cloud_test.ts
Deno.test("CursorCloudVerifier - valid token", async () => {
  const verifier = createTestCursorCloudVerifier();
  const token = await signCloudAgentToken({
    sub: "run_abc123",
    user_id: "usr_xyz",
    email: "alice@example.com",
  });
  const claims = await verifier.verifyAccessToken(token);
  assertEquals(claims.user_id, "usr_xyz");
});

// mcp/routes/mcp_test.ts
Deno.test("POST /mcp - Cursor Cloud auth", async () => {
  const token = await signCloudAgentToken({ /* ... */ });
  const response = await app.request("/mcp", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "initialize",
      id: 1,
      params: { protocolVersion: "2024-11-05", capabilities: {} },
    }),
  });
  assertEquals(response.status, 200);
});
```

### Integration Tests

1. **Local Cloud Agent Simulation:**
   ```bash
   # Terminal 1: Start MCP with Cloud Agent support
   cd mcp
   export CURSOR_CLOUD_ENABLED=true
   deno task dev
   
   # Terminal 2: Test with mock Cloud Agent token
   ./scripts/test-cloud-agent-auth.sh
   ```

2. **Real Cloud Agent Test:**
   - Create test Cloud Agent in Cursor
   - Configure `MUTANDE_ACCESS_TOKEN` secret
   - Run collaboration test prompt:
     ```
     Use the mutande MCP to check your inbox and send a test message to @alice@test
     ```

---

## Rollout Strategy

### Stage 1: Beta Testing (Phase 1)
- Document manual token setup
- Invite pilot users to test
- Gather feedback on auth flow
- Monitor token expiry issues

### Stage 2: Service Account Integration (Phase 2)
- Partner with Cursor team for service token implementation
- Deploy multi-verifier MCP update
- Beta test with automated auth
- Iterate on user mapping

### Stage 3: General Availability (Phase 3)
- Auto-configuration for all mutande workspaces
- Documentation in hosted MCP docs
- Announce Cloud Agent support

---

## Security Considerations

1. **Token Storage:**
   - Cloud Agent secrets are encrypted at rest
   - Tokens never logged or exposed in UI
   - Short-lived service tokens preferred (Phase 2)

2. **Token Scope:**
   - Tokens scoped to specific user/org
   - Cannot access other orgs' threads
   - Rate limiting per agent run

3. **Revocation:**
   - User can revoke tokens from Mutande dashboard
   - Service account tokens auto-expire after run
   - Audit log of Cloud Agent access

4. **Multi-tenancy:**
   - Each Cloud Agent maps to one Mutande user
   - Org boundaries enforced by hub
   - No cross-org data leakage

---

## Documentation Needs

1. **User Guide:**
   - `docs/CLOUD-AGENT-SETUP.md` - Step-by-step token generation
   - Update `docs/HOSTED-MCP.md` - Add Cloud Agent section
   
2. **Developer Guide:**
   - `docs/CLOUD-AGENT-AUTH.md` - Technical auth flow
   - API documentation for service account integration

3. **Troubleshooting:**
   - Common auth errors
   - Token expiry handling
   - Secret configuration issues

---

## Timeline Estimate

**Phase 1 (Manual Setup):**
- MCP changes: minimal (just documentation)
- Token generation UI: 1-2 days
- Documentation: 1 day
- Testing: 1 day
- **Total: ~3-5 days**

**Phase 2 (Service Account):**
- Cursor team coordination: variable
- Multi-verifier implementation: 2-3 days
- Hub user mapping: 2 days
- Testing & integration: 2-3 days
- **Total: ~6-8 days (excluding Cursor partnership timeline)**

**Phase 3 (Auto-config):**
- Cursor infrastructure integration: coordinated with Cursor
- Workspace detection: 1 day
- End-to-end testing: 2 days
- **Total: ~3-5 days + Cursor coordination**

---

## Open Questions

1. **Cursor service token format:**
   - What claims does Cursor include in service account JWTs?
   - Where is the JWKS endpoint?
   - What audience should MCP expect?

2. **User mapping:**
   - How to link Cursor user_id to Mutande account?
   - OAuth connector or manual invite-based linking?
   - Handle multiple Cursor accounts per Mutande org?

3. **Rate limits:**
   - Should Cloud Agents have different rate limits than web users?
   - Quota per run vs per user vs per org?

4. **Agent slug:**
   - Default to `cursor-cloud` or detect run metadata?
   - Support custom slugs per Cloud Agent run?

---

## Next Steps

**Immediate (Phase 1):**

1. Create token generation endpoint in hub:
   ```typescript
   // hub/ POST /v1/cloud-agents/tokens
   // Returns: { access_token, expires_in, created_at }
   ```

2. Add token management UI:
   - Web dashboard: Settings → Cloud Agents → Generate Token
   - Display token once, copy to clipboard
   - List active tokens with revoke button

3. Document setup flow:
   - `docs/CLOUD-AGENT-SETUP.md`
   - Update `docs/HOSTED-MCP.md`
   - Add troubleshooting section

4. Test with real Cloud Agent:
   - Generate token
   - Configure secret
   - Verify MCP tools available
   - Test collaboration workflow

**Next (Phase 2):**

5. Reach out to Cursor team:
   - Discuss service account token format
   - Coordinate JWKS endpoint access
   - Plan integration timeline

6. Implement multi-verifier support:
   - Add Cursor Cloud verifier
   - Update authenticate() logic
   - Add configuration flags

7. Build user linking:
   - OAuth connector or invite flow
   - cursor_user_id → mutande mapping
   - Link management UI

---

## Collab Integration

**Collab** is Mutande's project management surface - kanban boards where cards are threads. Cloud Agents can fully participate in collabs.

### Collab Concepts

- **Collab (board)**: Named container of threads with steerers (humans) and roster (agents)
- **Card**: A thread on a kanban board with lane position
- **Lane**: Board column (Backlog, Doing, Done by default)
- **Instructions**: Standing context for the collab (goals, conventions, credentials)
- **Shared Brain**: Memory thread with learnings that persist across agent sessions
- **Encryption Mode**: `e2e` (Mac sidecar only) or `app_envelope` (Cloud Agents supported)

### Available Collab Tools (Cloud Agent MCP)

**1. `list_collabs`**
```json
{
  "collabs": [
    {
      "id": "uuid",
      "name": "Q4 Website Redesign",
      "encryption_mode": "app_envelope",
      "people": [{"handle": "alice@acme"}, {"handle": "bob@acme"}],
      "agents": [
        {"address": "alice@acme/cursor", "transport": "sidecar"},
        {"address": "bob@acme/chatgpt", "transport": "mcp"}
      ],
      "card_count": 12,
      "needs_you": 3,
      "last_card_updated_at": "2026-08-16T20:00:00Z"
    }
  ],
  "portfolio": {
    "totals": {"collabs": 5, "open": 42, "doing": 8, "needs_you": 7},
    "lane_totals": {"backlog": 20, "doing": 8, "done": 14},
    "activity": [...]  // 84-day calendar
  }
}
```

**2. `get_collab`**
```json
{
  "id": "uuid",
  "name": "Q4 Website Redesign",
  "instructions": "Use Tailwind CSS. API docs at https://api.example.com. DB creds in 1Password.",
  "encryption_mode": "app_envelope",
  "people": [...],
  "agents": [...],
  "lists": [
    {"id": "uuid-1", "name": "Backlog", "position": 0},
    {"id": "uuid-2", "name": "Doing", "position": 1},
    {"id": "uuid-3", "name": "Done", "position": 2}
  ],
  "cards": [
    {
      "thread_id": "card-uuid",
      "subject": "Add dark mode toggle",
      "lane_id": "uuid-2",
      "lane_position": 1024,
      "status": "open",
      "assigned_to": "alice@acme",
      "from": "alice@acme/cursor",
      "your_status": "pending",
      "updated_at": "2026-08-16T19:30:00Z"
    }
  ],
  "learnings": [
    {
      "id": "learning-uuid",
      "created_at": "2026-08-15T10:00:00Z",
      "from_handle": "alice@acme/claude",
      "notes": "User prefers system dark mode detection over manual toggle"
    }
  ],
  "artifacts": [
    {
      "kind": "link",
      "label": "Design mockups",
      "url": "https://figma.com/...",
      "created_at": "2026-08-10T12:00:00Z",
      "from_handle": "bob@acme"
    },
    {
      "kind": "file",
      "label": "API spec",
      "name": "openapi.yaml",
      "mime": "text/yaml",
      "content": "openapi: 3.0.0\n...",
      "size": 2048,
      "created_at": "2026-08-12T09:00:00Z",
      "from_handle": "alice@acme"
    }
  ],
  "memory_thread_id": "uuid"
}
```

**3. `set_lane`**
```json
// Move card to different lane / reorder within lane
{
  "collab_id": "uuid",
  "thread_id": "card-uuid",
  "lane_id": "uuid-2",  // Doing lane
  "after_thread_id": "other-card-uuid"  // Position after this card
}
```

**4. `add_learning`**
```json
// Contribute to the shared brain (creator's side only)
{
  "collab_id": "uuid",
  "notes": "User wants real-time preview on all form fields"
}
// Non-creators propose via reply on the memory thread
```

**5. `forward_draft` with collab**
```json
// Create a new card on a board
{
  "collab_id": "uuid",
  "subject": "Fix mobile nav overflow",
  "notes": "Nav menu breaks on iOS Safari < 375px width",
  "resources": [
    {"name": "screenshot.png", "content_base64": "...", "mime": "image/png"}
  ]
}
// Returns thread_id (the card id)
```

**6. `list_threads` with collab filter**
```json
{
  "collab_id": "uuid",
  "filter": "needs_action"
}
// Returns only threads (cards) from this board that need your action
```

### Cloud Agent Collab Workflows

**Workflow 1: Check collab boards on startup**

```typescript
// Agent checks for active collabs when chat begins
const { collabs } = await callMcpTool('list_collabs', {});
if (collabs.length > 0) {
  console.log(`You're working on ${collabs.length} project(s)`);
  const needsYou = collabs.reduce((sum, c) => sum + c.needs_you, 0);
  if (needsYou > 0) {
    console.log(`${needsYou} card(s) need your attention`);
  }
}
```

**Workflow 2: Work a collab card**

```typescript
// User: "Work on the dark mode task in the website project"

// 1. Find the collab
const { collabs } = await callMcpTool('list_collabs', {});
const collab = collabs.find(c => c.name.includes('website'));

// 2. Get full collab context
const board = await callMcpTool('get_collab', { collab_id: collab.id });

// 3. Read instructions & learnings
console.log('Instructions:', board.instructions);
console.log('Learnings:', board.learnings.map(l => l.notes).join('\n'));

// 4. Find the card
const card = board.cards.find(c => c.subject.includes('dark mode'));

// 5. Get card conversation
const thread = await callMcpTool('get_thread', { thread_id: card.thread_id });

// 6. Move to Doing
await callMcpTool('set_lane', {
  collab_id: collab.id,
  thread_id: card.thread_id,
  lane_id: board.lists.find(l => l.name === 'Doing').id
});

// 7. Work on the task, then reply with progress
await callMcpTool('reply_to_thread', {
  thread_id: card.thread_id,
  notes: "Added dark mode toggle component. Testing on Safari..."
});

// 8. Move to Done when complete
await callMcpTool('set_lane', {
  collab_id: collab.id,
  thread_id: card.thread_id,
  lane_id: board.lists.find(l => l.name === 'Done').id
});
```

**Workflow 3: Create a new card**

```typescript
// User: "Create a card to refactor the auth module"

const { collabs } = await callMcpTool('list_collabs', {});
const collab = collabs[0];  // or user selects

const board = await callMcpTool('get_collab', { collab_id: collab.id });

const result = await callMcpTool('forward_draft', {
  collab_id: collab.id,
  subject: "Refactor auth module to use OIDC",
  notes: `Current auth uses custom JWT. Migrate to OIDC:
  
  - Replace JWT middleware with OIDC
  - Add Auth0 config
  - Update tests
  - Document breaking changes`,
  resources: [
    {
      name: "current-auth.ts",
      content: readFileSync('src/auth.ts', 'utf8')
    }
  ]
});

console.log(`Created card: ${result.thread_id}`);
```

**Workflow 4: Contribute a learning**

```typescript
// After discovering a useful insight during work

const { collabs } = await callMcpTool('list_collabs', {});
const collab = collabs.find(c => c.name.includes('website'));

// If you're the creator's agent
await callMcpTool('add_learning', {
  collab_id: collab.id,
  notes: "Use Vercel Edge Functions for API routes - 30% faster than serverless"
});

// If you're not the creator's agent, propose via memory thread
const board = await callMcpTool('get_collab', { collab_id: collab.id });
await callMcpTool('reply_to_thread', {
  thread_id: board.memory_thread_id,
  notes: "Proposed learning: Use Vercel Edge Functions for API routes - 30% faster"
});
```

**Workflow 5: Read artifacts**

```typescript
const board = await callMcpTool('get_collab', { collab_id: 'uuid' });

// Links
const designLink = board.artifacts.find(a => a.kind === 'link' && a.label.includes('design'));
console.log('Design mockups:', designLink.url);

// Files (app_envelope collabs return content inline)
const apiSpec = board.artifacts.find(a => a.name === 'openapi.yaml');
console.log('API spec:', apiSpec.content);

// E2E collabs: artifacts are sealed, use Mac sidecar
if (board.encryption_mode === 'e2e' && board.sidecar_required) {
  console.log('This collab requires the Mac sidecar for file artifacts');
}
```

### Cloud Agent Setup for Collab

**Phase 1**: Same token-based setup as threads
- Token grants access to all collabs where user is a steerer/roster member
- `app_envelope` collabs fully supported
- E2E collabs list but card bodies require Mac sidecar

**Phase 2**: Service account with collab permissions
- Automatic collab discovery
- Same access model as user's agents
- Can create cards, move lanes, add learnings

**Phase 3**: Auto-detected collab participation
- Cloud Agent auto-added to org collabs
- Collaborative coding workflows out-of-box
- Zero setup for mutande workspaces

### E2E vs App_Envelope Collabs

| Feature | E2E Collab | App_Envelope Collab |
|---------|------------|---------------------|
| Cloud Agent support | Metadata only (list, card summaries) | Full (read bodies, reply, move, learn) |
| Card bodies | Mac sidecar required | Inline in MCP |
| File artifacts | Sealed (sidecar decrypts) | Inline `content` field |
| Learnings (brain) | Sealed stubs | Full `notes` text |
| Instructions | Sealed | Plaintext |
| Board operations | `set_lane` works | All operations work |

**When Cloud Agents see E2E collabs:**
- `list_collabs` includes them with `sidecar_required: true`
- `get_collab` returns metadata, card ids, and note explaining sidecar requirement
- `set_lane` works (board metadata is hub-visible)
- Card conversation requires Mac sidecar MCP

**Best practice**: Use `app_envelope` collabs for Cloud Agent participation; E2E for human-only sensitive boards.

---

## Success Metrics

- Cloud Agents can authenticate to MCP
- Collaboration tools work end-to-end
- **Collab workflows (list, get, create cards, move lanes) functional**
- **Shared brain (learnings) accessible and writeable**
- **Artifacts (links + app_envelope files) readable**
- Zero manual configuration (Phase 3)
- Sub-second auth latency
- < 0.1% auth failure rate
- Positive user feedback on setup flow
- **Cloud Agents successfully work collab boards in pilot orgs**
