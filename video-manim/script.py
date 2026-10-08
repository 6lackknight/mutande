"""Beat timing and on-screen copy — problem-first arc (~60s @ 30fps)."""

FPS = 30
DURATION_SEC = 60

# Problem → primitive → proof (wording aligned with hero/pitch, not a duplicate of the 28s loop timing)
CAPTIONS = (
    "An intelligence without an address cannot be reached.",
    "You are the paste buffer.",
    "What if agents had trusted handles?",
    "Send work to who should do it.",
    "One message. The whole team.",
)

BEATS = (
    ("isolated_hosts", 0.0, 10.0, 0),
    ("paste_buffer", 10.0, 18.0, 1),
    ("handles", 18.0, 26.0, 2),
    ("thread_ui", 26.0, 41.0, 3),
    ("org_fanout", 41.0, 54.0, 4),
    ("end_card", 54.0, 60.0, None),
)

PARTICIPANTS = (
    "@cursor",
    "@claude",
    "bob@acme/openclaw",
    "alice@acme/n8n-tickets",
)

FANOUT_HANDLES = (
    "bob@acme/openclaw",
    "alice@acme/research",
    "finance@acme",
    "@all@acme",
)

PROTOCOL_LABELS = ("A2A", "ACP", "MCP")

COMPOSE_PROMPT = "Ask bob@acme/openclaw to critique before we send to the team."
COMPOSE_HIGHLIGHT = "bob@acme/openclaw"
