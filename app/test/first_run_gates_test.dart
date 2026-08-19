import 'package:app/models/agent_transport.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/first_run_gates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('destination needs a second own agent or a live teammate', () {
    expect(firstRunDestinationReady(ownAgents: 0, liveTeammate: true), isFalse);
    expect(
      firstRunDestinationReady(ownAgents: 1, liveTeammate: false),
      isFalse,
    );
    expect(firstRunDestinationReady(ownAgents: 2, liveTeammate: false), isTrue);
    expect(firstRunDestinationReady(ownAgents: 1, liveTeammate: true), isTrue);
  });

  test('handoff target prefers the other own agent, else the teammate', () {
    const agents = [
      AgentInfo(id: '1', slug: 'cursor'),
      AgentInfo(id: '2', slug: 'claude'),
    ];
    expect(
      firstRunHandoffTarget(ownAgents: agents, sendingSlug: 'cursor'),
      '@claude',
    );
    expect(
      firstRunHandoffTarget(
        ownAgents: [const AgentInfo(id: '1', slug: 'cursor')],
        liveTeammateHandle: 'orinea@tbhco',
      ),
      'orinea@tbhco',
    );
    expect(
      firstRunHandoffTarget(
        ownAgents: [const AgentInfo(id: '1', slug: 'cursor')],
      ),
      isNull,
    );
  });

  test('handoff choices list every other host and teammate', () {
    const agents = [
      AgentInfo(id: '1', slug: 'cursor'),
      AgentInfo(id: '2', slug: 'claude'),
      AgentInfo(id: '3', slug: 'chatgpt'),
      AgentInfo(id: '4', slug: 'chatgpt', transport: AgentTransport.mcp),
    ];
    expect(
      firstRunHandoffChoices(
        ownAgents: agents,
        sendingSlug: 'cursor',
        liveTeammateHandles: ['orinea@tbhco'],
      ),
      ['@claude', '@chatgpt', 'orinea@tbhco'],
    );
    expect(firstRunHandoffChoiceLabel('@chatgpt'), 'ChatGPT');
    expect(firstRunHandoffChoiceIconSlug('orinea@tbhco'), isNull);
  });

  test('dual chatgpt slots prefer web for the first-run target', () {
    const agents = [
      AgentInfo(id: '1', slug: 'cursor', transport: AgentTransport.sidecar),
      AgentInfo(id: '2', slug: 'chatgpt', transport: AgentTransport.sidecar),
      AgentInfo(id: '3', slug: 'chatgpt', transport: AgentTransport.mcp),
    ];
    expect(
      firstRunHandoffTarget(ownAgents: agents, sendingSlug: 'cursor'),
      '@chatgpt',
    );
    expect(
      firstRunHandoffTransport(ownAgents: agents, target: '@chatgpt'),
      AgentTransport.mcp,
    );
    expect(
      firstRunComposerId(slug: 'chatgpt', transport: AgentTransport.mcp),
      'chatgpt-web',
    );
    expect(
      firstRunSendingTransport(ownAgents: agents, sendingSlug: 'chatgpt'),
      AgentTransport.sidecar,
    );
  });

  test('ping threads never complete the first-run handshake', () {
    const ping = ThreadDetailResult(
      id: 't1',
      kind: 'direct',
      status: 'open',
      from: 'alice@acme/cursor',
      messages: [
        ThreadMessageView(
          id: 'm1',
          fromHandle: 'alice@acme/cursor',
          createdAt: '2026-08-19T10:00:00Z',
          pingKind: 'thread',
        ),
        ThreadMessageView(
          id: 'm2',
          fromHandle: 'alice@acme/claude',
          createdAt: '2026-08-19T10:00:05Z',
          parentMessageId: 'm1',
          hasHandshake: true,
        ),
      ],
    );
    expect(isFirstRunHandshakeReply(ping), isFalse);
  });

  test('first-run watch skips threads with no reply yet', () {
    const summary = ThreadSummary(
      id: 't1',
      kind: 'direct',
      status: 'open',
      from: 'alice@acme/cursor',
      audience: 'alice@acme/chatgpt',
      replyCount: 0,
      updatedAt: '2026-08-19T16:00:00Z',
    );
    expect(
      isFirstRunHandoffCandidate(
        summary: summary,
        waitStarted: DateTime.parse('2026-08-19T16:00:01Z'),
        target: '@chatgpt',
      ),
      isFalse,
    );
    expect(
      isFirstRunOutboundCandidate(
        summary: summary,
        waitStarted: DateTime.parse('2026-08-19T16:00:01Z'),
        target: '@chatgpt',
      ),
      isTrue,
    );
  });

  test('first-run watch opens a recently replied thread', () {
    const summary = ThreadSummary(
      id: 't1',
      kind: 'direct',
      status: 'open',
      from: 'alice@acme/cursor',
      audience: 'alice@acme/chatgpt',
      replyCount: 1,
      updatedAt: '2026-08-19T16:00:08Z',
    );
    expect(
      isFirstRunHandoffCandidate(
        summary: summary,
        waitStarted: DateTime.parse('2026-08-19T16:00:01Z'),
        target: '@chatgpt',
      ),
      isTrue,
    );
  });

  test('first-run watch ignores collab threads', () {
    const summary = ThreadSummary(
      id: 'c1',
      kind: 'collab',
      status: 'open',
      from: 'alice@acme/cursor',
      audience: 'alice@acme/chatgpt',
      replyCount: 1,
      updatedAt: '2026-08-19T16:00:08Z',
      collabId: 'collab-1',
    );
    expect(
      isFirstRunOutboundCandidate(
        summary: summary,
        waitStarted: DateTime.parse('2026-08-19T16:00:01Z'),
        target: '@chatgpt',
      ),
      isFalse,
    );
  });

  test('a handshake reply from a different agent completes first-run', () {
    const handshake = ThreadDetailResult(
      id: 't2',
      kind: 'direct',
      status: 'open',
      from: 'alice@acme/cursor',
      messages: [
        ThreadMessageView(
          id: 'm1',
          fromHandle: 'alice@acme/cursor',
          createdAt: '2026-08-19T10:00:00Z',
        ),
        ThreadMessageView(
          id: 'm2',
          fromHandle: 'alice@acme/claude',
          createdAt: '2026-08-19T10:00:08Z',
          parentMessageId: 'm1',
          hasHandshake: true,
        ),
      ],
    );
    expect(isFirstRunHandshakeReply(handshake), isTrue);
  });

  test('a plain reply without a handshake does not complete first-run', () {
    const gotIt = ThreadDetailResult(
      id: 't3',
      kind: 'direct',
      status: 'open',
      from: 'alice@acme/cursor',
      messages: [
        ThreadMessageView(
          id: 'm1',
          fromHandle: 'alice@acme/cursor',
          createdAt: '2026-08-19T10:00:00Z',
        ),
        ThreadMessageView(
          id: 'm2',
          fromHandle: 'alice@acme/claude',
          createdAt: '2026-08-19T10:00:08Z',
          parentMessageId: 'm1',
        ),
      ],
    );
    expect(isFirstRunHandshakeReply(gotIt), isFalse);
  });

  test('first-run prompt asks for a handshake, not a work dump', () {
    expect(firstRunHandshakePrompt('@claude'), contains('/handshake'));
    expect(firstRunHandshakePrompt('@claude'), contains('@claude'));
    expect(firstRunHandshakeReplyPrompt(), contains('/handshake'));
  });

  test('next-step recipient is @all once two own hosts exist', () {
    const two = [
      AgentInfo(id: '1', slug: 'cursor'),
      AgentInfo(id: '2', slug: 'claude'),
    ];
    expect(
      firstRunNextStepRecipient(ownAgents: two, target: '@claude'),
      '@all',
    );
    expect(
      firstRunNextStepRecipient(
        ownAgents: [const AgentInfo(id: '1', slug: 'cursor')],
        target: 'orinea@tbhco',
      ),
      'orinea@tbhco',
    );
  });

  test('next-step pair names the hosts that are actually connected', () {
    const two = [
      AgentInfo(id: '1', slug: 'cursor'),
      AgentInfo(id: '2', slug: 'claude'),
    ];
    final pair = firstRunNextStepPairLabels(
      ownAgents: two,
      sendingSlug: 'cursor',
      target: '@claude',
    );
    expect(pair.first, 'Cursor');
    expect(pair.second, 'Claude');
    expect(
      firstRunNextStepWorkNotes(pair.first, pair.second),
      contains('Cursor and Claude'),
    );
    expect(
      firstRunNextStepPhysicsNotes(pair.first, pair.second),
      contains('Foucault'),
    );

    final teammate = firstRunNextStepPairLabels(
      ownAgents: [const AgentInfo(id: '1', slug: 'cursor')],
      sendingSlug: 'cursor',
      target: 'orinea@tbhco',
      contacts: const [
        ContactView(handle: 'orinea@tbhco', displayName: 'Orinea'),
      ],
    );
    expect(teammate.second, 'Orinea');
  });

  test('invite shows only when the org roster is still solo', () {
    expect(
      firstRunShowInvite(
        contacts: const [ContactView(handle: 'alice@acme')],
        myHandle: 'alice@acme',
      ),
      isTrue,
    );
    expect(
      firstRunShowInvite(
        contacts: const [
          ContactView(handle: 'alice@acme'),
          ContactView(handle: 'orinea@tbhco', displayName: 'Orinea'),
        ],
        myHandle: 'alice@acme',
      ),
      isFalse,
    );
  });
}
