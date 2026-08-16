# Quick Start: Phase 1 Implementation

This document outlines the immediate steps to enable Cursor Cloud Agent MCP support using long-lived Auth0 tokens.

## What We're Building

A simple token-based authentication flow that lets Cloud Agents use the Mutande MCP server without OAuth browser flows.

## Architecture

```
User → Mutande Web/Mac → Generate Token → Cursor Secrets → Cloud Agent → MCP
```

## Implementation Tasks

### 1. Hub: Token Generation API

**File:** `hub/routes/cloud_agents.ts` (new)

```typescript
import { Hono } from "hono";
import { requireAuth } from "../middleware/auth.ts";

const routes = new Hono();

// POST /v1/cloud-agents/tokens - Generate long-lived access token
routes.post("/tokens", requireAuth, async (c) => {
  const user = c.get("user");
  
  // Generate token (Auth0 M2M or custom JWT)
  const token = await generateCloudAgentToken(user);
  
  return c.json({
    access_token: token,
    token_type: "Bearer",
    expires_in: 31536000, // 1 year
    created_at: Date.now(),
    usage: "Add to Cursor Dashboard → Cloud Agents → Secrets as MUTANDE_ACCESS_TOKEN",
  });
});

// GET /v1/cloud-agents/tokens - List active tokens
routes.get("/tokens", requireAuth, async (c) => {
  const user = c.get("user");
  const tokens = await listUserTokens(user.id);
  
  return c.json({
    tokens: tokens.map(t => ({
      id: t.id,
      created_at: t.created_at,
      last_used: t.last_used,
      // Never return the actual token
    })),
  });
});

// DELETE /v1/cloud-agents/tokens/:id - Revoke token
routes.delete("/tokens/:id", requireAuth, async (c) => {
  const user = c.get("user");
  const tokenId = c.req.param("id");
  
  await revokeToken(user.id, tokenId);
  
  return c.json({ success: true });
});

export { routes as cloudAgentRoutes };
```

### 2. Hub: Token Storage

**File:** `hub/store/cloud_agent_tokens.ts` (new)

```typescript
export interface CloudAgentToken {
  id: string;
  user_id: string;
  token_hash: string; // bcrypt hash of the token
  created_at: number;
  last_used?: number;
  revoked: boolean;
}

export async function storeToken(
  userId: string,
  tokenHash: string,
): Promise<CloudAgentToken> {
  const id = crypto.randomUUID();
  const token: CloudAgentToken = {
    id,
    user_id: userId,
    token_hash: tokenHash,
    created_at: Date.now(),
    revoked: false,
  };
  
  await kv.set(["cloud_agent_tokens", id], token);
  await kv.set(["cloud_agent_tokens_by_user", userId, id], token);
  
  return token;
}

export async function verifyToken(token: string): Promise<CloudAgentToken | null> {
  // In practice, we'd just use Auth0 tokens
  // This is for reference if we issue custom tokens
  const hash = await bcrypt.hash(token);
  
  // Lookup by hash (requires index or linear scan)
  // Better: use Auth0 tokens and verify via JWKS
  
  return null; // Stub
}
```

### 3. Web: Token Management UI

**File:** `web/src/app/(authenticated)/settings/cloud-agents/page.tsx` (new)

```tsx
'use client';

import { useState } from 'react';

export default function CloudAgentsPage() {
  const [token, setToken] = useState<string | null>(null);
  const [tokens, setTokens] = useState<Array<{
    id: string;
    created_at: number;
    last_used?: number;
  }>>([]);
  
  const generateToken = async () => {
    const res = await fetch('/api/cloud-agents/tokens', {
      method: 'POST',
    });
    const data = await res.json();
    setToken(data.access_token);
    loadTokens(); // Refresh list
  };
  
  const revokeToken = async (id: string) => {
    await fetch(`/api/cloud-agents/tokens/${id}`, {
      method: 'DELETE',
    });
    loadTokens();
  };
  
  const loadTokens = async () => {
    const res = await fetch('/api/cloud-agents/tokens');
    const data = await res.json();
    setTokens(data.tokens);
  };
  
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Cloud Agent Integration</h1>
        <p className="text-sm text-muted-foreground mt-2">
          Generate access tokens for Cursor Cloud Agents to use Mutande collaboration tools.
        </p>
      </div>
      
      {token && (
        <div className="p-4 bg-amber-50 border border-amber-200 rounded-lg space-y-3">
          <p className="font-medium">Your Cloud Agent Token</p>
          <p className="text-xs text-muted-foreground">
            Copy this token and add it to Cursor Dashboard → Cloud Agents → Secrets as <code>MUTANDE_ACCESS_TOKEN</code>
          </p>
          <div className="flex gap-2">
            <code className="flex-1 p-2 bg-white border rounded text-xs break-all">
              {token}
            </code>
            <button
              onClick={() => navigator.clipboard.writeText(token)}
              className="px-3 py-1 bg-amber-600 text-white rounded text-sm"
            >
              Copy
            </button>
          </div>
          <p className="text-xs text-amber-800">
            ⚠️ This token will only be shown once. Store it securely.
          </p>
        </div>
      )}
      
      <button
        onClick={generateToken}
        className="px-4 py-2 bg-black text-white rounded"
      >
        Generate New Token
      </button>
      
      <div className="space-y-2">
        <h2 className="font-medium">Active Tokens</h2>
        {tokens.length === 0 ? (
          <p className="text-sm text-muted-foreground">No active tokens</p>
        ) : (
          <div className="space-y-2">
            {tokens.map(t => (
              <div key={t.id} className="flex items-center justify-between p-3 border rounded">
                <div>
                  <p className="text-sm">Created: {new Date(t.created_at).toLocaleString()}</p>
                  {t.last_used && (
                    <p className="text-xs text-muted-foreground">
                      Last used: {new Date(t.last_used).toLocaleString()}
                    </p>
                  )}
                </div>
                <button
                  onClick={() => revokeToken(t.id)}
                  className="px-3 py-1 text-sm text-red-600 border border-red-600 rounded"
                >
                  Revoke
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
      
      <div className="p-4 bg-gray-50 border rounded-lg space-y-2">
        <h3 className="font-medium text-sm">Setup Instructions</h3>
        <ol className="text-sm space-y-1 list-decimal list-inside">
          <li>Generate a token above</li>
          <li>Copy the token to your clipboard</li>
          <li>Open Cursor Dashboard → Cloud Agents → Secrets</li>
          <li>Add a new secret: <code>MUTANDE_ACCESS_TOKEN</code></li>
          <li>Paste the token as the value</li>
          <li>Save and restart your Cloud Agent</li>
        </ol>
        <p className="text-xs text-muted-foreground mt-3">
          Once configured, your Cloud Agent will automatically connect to Mutande MCP.
        </p>
      </div>
    </div>
  );
}
```

### 4. Documentation

**File:** `docs/CLOUD-AGENT-SETUP.md` (new)

```markdown
# Cursor Cloud Agent Setup

Enable your Cursor Cloud Agents to use Mutande collaboration tools.

## Prerequisites

- Active Mutande account (Mac or web onboarding complete)
- Cursor Cloud Agent access
- Org membership (handle like `alice@acme`)

## Setup Steps

### 1. Generate Access Token

1. Open [Mutande Dashboard](https://mutande.online)
2. Sign in with your Mutande account
3. Navigate to **Settings → Cloud Agents**
4. Click **Generate New Token**
5. Copy the displayed token (shown only once!)

### 2. Configure Cloud Agent Secret

1. Open [Cursor Dashboard](https://cursor.com/settings)
2. Navigate to **Cloud Agents → Secrets**
3. Click **Add Secret**
4. Name: `MUTANDE_ACCESS_TOKEN`
5. Value: Paste your token
6. Scope: User or Team (your choice)
7. Click **Save**

### 3. Verify Setup

Start a new Cloud Agent session and test:

```
Use the mutande MCP to check your inbox
```

Expected response:
```
I checked your mutande inbox. You have X threads...
```

## Usage Examples

### Check Inbox

```
What threads do I have in mutande?
```

### Send Message

```
Send a message via mutande to @bob@acme saying "Review the PRD when you have a moment"
```

### Collaborate with Other Agents

```
Forward this context to @claude@acme via mutande:
[Your context here]
```

## Troubleshooting

### "MCP server mutande not found"

- Verify secret name is exactly `MUTANDE_ACCESS_TOKEN`
- Restart your Cloud Agent session
- Check token hasn't expired (tokens valid for 1 year)

### "Unauthorized" or "Invalid token"

- Token may have expired - generate a new one
- Verify you copied the complete token
- Check token wasn't revoked in dashboard

### MCP Tools Not Working

- Ensure you completed Mutande onboarding
- Verify your handle is active (check Mutande app)
- Check hub status: https://hub.mutande.online/health

## Security Notes

- Tokens are long-lived (1 year) - treat like passwords
- Store only in Cursor secrets (never commit to code)
- Revoke tokens you're not using
- Generate separate tokens per team if needed

## Support

- Documentation: https://mutande.online/docs
- Issues: GitHub or in-app feedback
```

## Testing Checklist

- [ ] Hub token generation endpoint works
- [ ] Web UI displays token once
- [ ] Token list loads correctly
- [ ] Revoke functionality works
- [ ] Cloud Agent can authenticate with token
- [ ] MCP tools (`list_threads`, `forward_draft`) work
- [ ] Token expiry handled gracefully
- [ ] Documentation is clear and accurate

## Deployment Steps

1. Deploy hub changes (token routes)
2. Deploy web changes (settings UI)
3. Publish documentation
4. Announce in changelog
5. Monitor for auth errors

## Estimated Timeline

- Hub API: 2-3 hours
- Web UI: 3-4 hours
- Documentation: 1-2 hours
- Testing: 2-3 hours
- **Total: 1-2 days**
