# Cloud Agent Collab Workflows

Comprehensive guide to using Mutande collabs from Cursor Cloud Agents.

## What is Collab?

**Collab** is Mutande's project management surface - kanban boards where cards are threads. Designed for human+agent teams to collaborate on structured work.

### Key Concepts

- **Collab (board)**: Named container with steerers (humans) and roster (agents)
- **Card**: A thread on the board with lane position
- **Lane**: Board column (Backlog, Doing, Done by default)
- **Instructions**: Standing context shared with all participants
- **Shared Brain**: Memory thread with curated learnings
- **Encryption Mode**: `e2e` (Mac only) or `app_envelope` (Cloud Agents supported)

## Available MCP Tools

| Tool | Purpose | Access |
|------|---------|--------|
| `list_collabs` | List boards you participate in | All participants |
| `get_collab` | Get full board (instructions, cards, learnings, artifacts) | All participants |
| `set_lane` | Move card between lanes / reorder | All participants |
| `add_learning` | Add to shared brain | Creator's agents only |
| `forward_draft` + `collab_id` | Create new card | All participants |
| `list_threads` + `collab_id` | List cards on board | All participants |
| `get_thread` | Get card conversation | All participants |
| `reply_to_thread` | Reply to card | All participants |

## Workflow Patterns

### Pattern 1: Daily Collab Standup

Cloud Agent checks boards at chat start, reports status.

```typescript
async function dailyCollabStandup() {
  const { collabs, portfolio } = await callMcpTool('list_collabs', {});
  
  if (collabs.length === 0) {
    return "You're not on any collab boards yet.";
  }
  
  const report = [
    `📊 You're working on ${portfolio.totals.collabs} project(s):`,
    ''
  ];
  
  for (const collab of collabs) {
    report.push(`**${collab.name}**`);
    report.push(`  - ${collab.card_count} cards (${collab.needs_you} need you)`);
    report.push(`  - ${collab.doing} in progress`);
    if (collab.last_card_updated_at) {
      const lastUpdate = new Date(collab.last_card_updated_at);
      report.push(`  - Last activity: ${formatRelativeTime(lastUpdate)}`);
    }
    report.push('');
  }
  
  if (portfolio.totals.needs_you > 0) {
    report.push(`💡 ${portfolio.totals.needs_you} card(s) across all boards need your attention.`);
  }
  
  return report.join('\n');
}
```

### Pattern 2: Context-Aware Card Work

Agent reads instructions + learnings before working on a card.

```typescript
async function workOnCard(collabName: string, cardSubject: string) {
  // 1. Find collab
  const { collabs } = await callMcpTool('list_collabs', {});
  const collab = collabs.find(c => 
    c.name.toLowerCase().includes(collabName.toLowerCase())
  );
  
  if (!collab) {
    throw new Error(`Collab "${collabName}" not found`);
  }
  
  // 2. Get full context
  const board = await callMcpTool('get_collab', { collab_id: collab.id });
  
  // 3. Read standing context
  console.log('📋 Instructions:', board.instructions);
  console.log('🧠 Learnings:', board.learnings.length, 'entries');
  
  const relevantLearnings = board.learnings
    .map(l => `- ${l.notes} (${l.from_handle}, ${l.created_at})`)
    .join('\n');
  console.log(relevantLearnings);
  
  // 4. Find the card
  const card = board.cards.find(c => 
    c.subject?.toLowerCase().includes(cardSubject.toLowerCase())
  );
  
  if (!card) {
    throw new Error(`Card "${cardSubject}" not found`);
  }
  
  // 5. Get conversation history
  const thread = await callMcpTool('get_thread', { thread_id: card.thread_id });
  console.log('💬 Previous messages:', thread.messages.length);
  
  // 6. Check artifacts
  const relevantArtifacts = board.artifacts.filter(a => 
    a.thread_id === card.thread_id || !a.thread_id
  );
  
  for (const artifact of relevantArtifacts) {
    if (artifact.kind === 'link') {
      console.log(`🔗 ${artifact.label}: ${artifact.url}`);
    } else if (artifact.kind === 'file') {
      console.log(`📄 ${artifact.name} (${artifact.size} bytes)`);
      // artifact.content available for app_envelope collabs
    }
  }
  
  // 7. Move to Doing
  const doingLane = board.lists.find(l => 
    l.name.toLowerCase() === 'doing'
  );
  
  await callMcpTool('set_lane', {
    collab_id: board.id,
    thread_id: card.thread_id,
    lane_id: doingLane.id
  });
  
  console.log(`✅ Moved "${card.subject}" to Doing`);
  
  return {
    board,
    card,
    thread,
    artifacts: relevantArtifacts,
    context: {
      instructions: board.instructions,
      learnings: board.learnings
    }
  };
}
```

### Pattern 3: Smart Card Creation

Create cards with rich context and file attachments.

```typescript
async function createCollabCard(params: {
  collabName: string;
  subject: string;
  description: string;
  files?: Array<{ name: string; content: string; mime?: string }>;
  assignTo?: string;
  lane?: 'Backlog' | 'Doing' | 'Done';
}) {
  // 1. Find collab
  const { collabs } = await callMcpTool('list_collabs', {});
  const collab = collabs.find(c => 
    c.name.toLowerCase().includes(params.collabName.toLowerCase())
  );
  
  if (!collab) {
    throw new Error(`Collab "${params.collabName}" not found`);
  }
  
  // 2. Get board to find lane
  const board = await callMcpTool('get_collab', { collab_id: collab.id });
  const targetLane = board.lists.find(l => 
    l.name.toLowerCase() === (params.lane || 'backlog').toLowerCase()
  );
  
  // 3. Prepare resources
  const resources = params.files?.map(f => ({
    name: f.name,
    content: f.content,
    ...(f.mime ? { mime: f.mime } : {})
  })) || [];
  
  // 4. Create card
  const result = await callMcpTool('forward_draft', {
    collab_id: collab.id,
    subject: params.subject,
    notes: params.description,
    resources,
    // Optional: assigned_to, watchers
    ...(params.assignTo ? { 
      assigned_to: params.assignTo.toLowerCase() 
    } : {})
  });
  
  console.log(`✅ Created card: ${result.thread_id}`);
  
  // 5. Move to desired lane if not Backlog
  if (targetLane && targetLane.name.toLowerCase() !== 'backlog') {
    await callMcpTool('set_lane', {
      collab_id: collab.id,
      thread_id: result.thread_id,
      lane_id: targetLane.id
    });
    console.log(`📍 Placed in ${targetLane.name}`);
  }
  
  return result;
}
```

### Pattern 4: Learning Contribution

Distill insights into the shared brain.

```typescript
async function contributeCollabLearning(
  collabName: string, 
  insight: string
) {
  // 1. Find collab
  const { collabs } = await callMcpTool('list_collabs', {});
  const collab = collabs.find(c => 
    c.name.toLowerCase().includes(collabName.toLowerCase())
  );
  
  if (!collab) {
    throw new Error(`Collab "${collabName}" not found`);
  }
  
  // 2. Check if we're the creator's agent
  const board = await callMcpTool('get_collab', { collab_id: collab.id });
  
  try {
    // Try direct add_learning (creator's agents only)
    const result = await callMcpTool('add_learning', {
      collab_id: collab.id,
      notes: insight
    });
    
    console.log(`🧠 Added learning to ${collab.name}`);
    return result;
    
  } catch (error) {
    // Not creator's agent - propose via memory thread
    if (error.message.includes('creator')) {
      console.log('📝 Proposing learning (awaiting creator approval)');
      
      await callMcpTool('reply_to_thread', {
        thread_id: board.memory_thread_id,
        notes: `**Proposed learning:**\n\n${insight}`
      });
      
      return { proposed: true };
    }
    throw error;
  }
}
```

### Pattern 5: Multi-Board Coordination

Coordinate work across multiple collabs.

```typescript
async function crossCollabReport() {
  const { collabs, portfolio } = await callMcpTool('list_collabs', {});
  
  const report = {
    summary: portfolio.totals,
    boards: [] as Array<{
      name: string;
      needsYou: number;
      inProgress: number;
      blockers: Array<{ cardId: string; subject: string; waiting: string }>;
    }>
  };
  
  for (const collab of collabs) {
    const board = await callMcpTool('get_collab', { collab_id: collab.id });
    
    // Find blocked cards
    const blockers = [];
    for (const card of board.cards) {
      const thread = await callMcpTool('get_thread', { 
        thread_id: card.thread_id 
      });
      
      const lastMessage = thread.messages[thread.messages.length - 1];
      if (lastMessage?.notes?.includes('waiting') || 
          lastMessage?.notes?.includes('blocked')) {
        blockers.push({
          cardId: card.thread_id,
          subject: card.subject,
          waiting: extractWaitingReason(lastMessage.notes)
        });
      }
    }
    
    report.boards.push({
      name: collab.name,
      needsYou: collab.needs_you || 0,
      inProgress: collab.doing || 0,
      blockers
    });
  }
  
  return report;
}
```

### Pattern 6: Artifact Management

Work with collab artifacts (files and links).

```typescript
async function processCollabArtifacts(collabName: string) {
  const { collabs } = await callMcpTool('list_collabs', {});
  const collab = collabs.find(c => 
    c.name.toLowerCase().includes(collabName.toLowerCase())
  );
  
  if (!collab) {
    throw new Error(`Collab "${collabName}" not found`);
  }
  
  const board = await callMcpTool('get_collab', { collab_id: collab.id });
  
  // Check encryption mode
  if (board.sidecar_required) {
    console.log('⚠️  E2E collab - file artifacts require Mac sidecar');
    // Links still accessible
    const links = board.artifacts.filter(a => a.kind === 'link');
    return { links, files: [] };
  }
  
  // Process artifacts
  const processed = {
    links: [] as Array<{ label: string; url: string }>,
    files: [] as Array<{ 
      name: string; 
      content: string; 
      mime?: string;
      cardTitle?: string;
    }>
  };
  
  for (const artifact of board.artifacts) {
    if (artifact.kind === 'link') {
      processed.links.push({
        label: artifact.label,
        url: artifact.url
      });
    } else if (artifact.kind === 'file' && artifact.content) {
      processed.files.push({
        name: artifact.name,
        content: artifact.content,
        mime: artifact.mime,
        cardTitle: artifact.card_title
      });
    }
  }
  
  console.log(`📦 Found ${processed.links.length} links, ${processed.files.length} files`);
  return processed;
}
```

## Best Practices

### 1. Always Read Context First

Before working on any card:
1. Call `get_collab` to get instructions + learnings
2. Check artifacts for relevant files/links
3. Read card conversation with `get_thread`
4. Apply context to your work

### 2. Move Cards Transparently

Use `set_lane` to show progress:
- Pick up a card → move to Doing
- Complete work → move to Done
- Blocked → leave in Doing, explain in reply

Never auto-move on reply - let humans see the board state.

### 3. Contribute Learnings Sparingly

Only add learnings that are:
- Distilled (not activity logs)
- Actionable for future work
- Non-obvious insights

Bad: "Fixed bug in auth.ts"  
Good: "Auth tokens need 60s expiry buffer for clock skew"

### 4. Handle E2E Collabs Gracefully

When `sidecar_required: true`:
- You can still list collabs and cards
- You can still move lanes
- You **cannot** read card bodies or file artifacts
- Explain limitation: "This E2E collab requires the Mac sidecar for card content"

### 5. Use Artifacts Effectively

- **Links**: Always accessible, great for external resources
- **Files (app_envelope)**: Inline content for specs, configs, code
- **Files (e2e)**: Sealed - refer user to Mac app

## Error Handling

### Common Errors

**"Not a collab member"**
- You're not a steerer or roster member
- User needs to add you to the collab

**"Only the collab creator's side may add_learning"**
- Use `reply_to_thread` on memory_thread_id instead
- Propose the learning for creator approval

**"Unknown lane"**
- Lane ID doesn't exist on this collab
- Fetch fresh board with `get_collab`

**"E2E collab — use the mutande Mac sidecar MCP"**
- Attempting app_envelope operations on E2E collab
- Fall back to metadata operations only

### Graceful Degradation

```typescript
async function safeGetCollab(collabId: string) {
  try {
    const board = await callMcpTool('get_collab', { collab_id: collabId });
    
    if (board.sidecar_required) {
      return {
        ...board,
        warning: 'Card bodies require Mac sidecar - showing metadata only'
      };
    }
    
    return board;
    
  } catch (error) {
    if (error.message.includes('Not a collab member')) {
      throw new Error(
        'You need to be added to this collab. Ask a steerer to add you.'
      );
    }
    if (error.message.includes('Collab not found')) {
      throw new Error(
        'This collab no longer exists or you lost access.'
      );
    }
    throw error;
  }
}
```

## Integration with Threads

Collab cards **are** threads - they appear in both places:

- **Threads tab**: Unified inbox with collab/unfiled split
- **Collab tab**: Board view with lanes

Use `list_threads` with `collab_id` filter:

```typescript
// All cards on a board
const threads = await callMcpTool('list_threads', { 
  collab_id: 'uuid',
  filter: 'open'
});

// Inbox across all boards
const inbox = await callMcpTool('list_threads', {
  filter: 'needs_action'
});
// includes both collab cards and standalone threads
```

## Performance Tips

### Batch Operations

```typescript
// Bad: N+1 queries
for (const collab of collabs) {
  const board = await callMcpTool('get_collab', { collab_id: collab.id });
  // ...
}

// Good: Only fetch boards you need
const activeCollab = collabs.find(c => c.needs_you > 0);
if (activeCollab) {
  const board = await callMcpTool('get_collab', { 
    collab_id: activeCollab.id 
  });
}
```

### Cache Board Context

```typescript
const boardCache = new Map<string, {
  board: any;
  fetchedAt: number;
}>();

async function getCachedBoard(collabId: string, maxAge = 60000) {
  const cached = boardCache.get(collabId);
  if (cached && Date.now() - cached.fetchedAt < maxAge) {
    return cached.board;
  }
  
  const board = await callMcpTool('get_collab', { collab_id: collabId });
  boardCache.set(collabId, { board, fetchedAt: Date.now() });
  return board;
}
```

## Example: Full Collab Agent

Complete Cloud Agent that manages collab work:

```typescript
class CollabAgent {
  async checkIn() {
    const { collabs, portfolio } = await callMcpTool('list_collabs', {});
    
    if (collabs.length === 0) return null;
    
    console.log(`📊 Portfolio: ${portfolio.totals.collabs} boards, ${portfolio.totals.needs_you} need you`);
    
    return portfolio;
  }
  
  async pickUpWork(collabName?: string) {
    const { collabs } = await callMcpTool('list_collabs', {});
    
    // Find board with work
    const target = collabName
      ? collabs.find(c => c.name.toLowerCase().includes(collabName.toLowerCase()))
      : collabs.find(c => c.needs_you > 0);
    
    if (!target) {
      console.log('No work available');
      return null;
    }
    
    // Get board
    const board = await callMcpTool('get_collab', { collab_id: target.id });
    
    // Find card needing action
    const card = board.cards.find(c => c.your_status === 'pending');
    
    if (!card) {
      console.log('No pending cards');
      return null;
    }
    
    // Get context
    const thread = await callMcpTool('get_thread', { thread_id: card.thread_id });
    
    // Move to Doing
    const doingLane = board.lists.find(l => l.name.toLowerCase() === 'doing');
    await callMcpTool('set_lane', {
      collab_id: board.id,
      thread_id: card.thread_id,
      lane_id: doingLane.id
    });
    
    console.log(`✅ Picked up: ${card.subject}`);
    
    return {
      board,
      card,
      thread,
      instructions: board.instructions,
      learnings: board.learnings
    };
  }
  
  async completeCard(cardId: string, summary: string) {
    // Find which collab this card belongs to
    const { collabs } = await callMcpTool('list_collabs', {});
    
    let targetCollab = null;
    for (const collab of collabs) {
      const board = await callMcpTool('get_collab', { collab_id: collab.id });
      if (board.cards.some(c => c.thread_id === cardId)) {
        targetCollab = board;
        break;
      }
    }
    
    if (!targetCollab) {
      throw new Error('Card not found in any collab');
    }
    
    // Reply with summary
    await callMcpTool('reply_to_thread', {
      thread_id: cardId,
      notes: summary
    });
    
    // Move to Done
    const doneLane = targetCollab.lists.find(l => l.name.toLowerCase() === 'done');
    await callMcpTool('set_lane', {
      collab_id: targetCollab.id,
      thread_id: cardId,
      lane_id: doneLane.id
    });
    
    console.log(`✅ Completed: ${cardId}`);
  }
}
```

## Next Steps

1. **Read the main plan**: `docs/CLOUD-AGENT-MCP.md`
2. **Set up authentication**: `docs/CLOUD-AGENT-QUICKSTART.md`
3. **Try the workflows**: Start with Pattern 1 (Daily Standup)
4. **Contribute learnings**: Help improve the shared brain
5. **Build custom workflows**: Adapt patterns to your team's needs
