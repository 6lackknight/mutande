"use client";

import { useMemo } from "react";
import type { OpsGraph, OpsGraphEdgeKind, OpsGraphNodeKind } from "@/lib/types";

const W = 800;
const H = 400;

type SimNode = {
  id: string;
  kind: OpsGraphNodeKind;
  label: string;
  parent_id?: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
};

function kindColor(kind: OpsGraphEdgeKind): string {
  switch (kind) {
    case "self":
      return "#b45309";
    case "org":
      return "#44403c";
    case "external":
      return "#78716c";
    case "broadcast":
      return "#a8a29e";
    default:
      return "#d6d3d1";
  }
}

function nodeRadius(kind: OpsGraphNodeKind): number {
  if (kind === "org") return 16;
  if (kind === "user") return 10;
  return 5;
}

function seedNodes(graph: OpsGraph): SimNode[] {
  const orgs = graph.nodes.filter((n) => n.kind === "org");
  const users = graph.nodes.filter((n) => n.kind === "user");
  const agents = graph.nodes.filter((n) => n.kind === "agent");
  const cx = W / 2;
  const cy = H / 2;
  const placed = new Map<string, SimNode>();

  orgs.forEach((org, i) => {
    const angle = (i / Math.max(orgs.length, 1)) * Math.PI * 2 - Math.PI / 2;
    const r = orgs.length <= 1 ? 0 : 70;
    placed.set(org.id, {
      ...org,
      x: cx + Math.cos(angle) * r,
      y: cy + Math.sin(angle) * r,
      vx: 0,
      vy: 0,
    });
  });

  const usersByOrg = new Map<string, typeof users>();
  for (const user of users) {
    const key = user.parent_id ?? "_";
    const list = usersByOrg.get(key) ?? [];
    list.push(user);
    usersByOrg.set(key, list);
  }
  for (const [orgId, list] of usersByOrg) {
    const parent = placed.get(orgId);
    list.forEach((user, i) => {
      const angle = (i / Math.max(list.length, 1)) * Math.PI * 2;
      const r = 56;
      placed.set(user.id, {
        ...user,
        x: (parent?.x ?? cx) + Math.cos(angle) * r,
        y: (parent?.y ?? cy) + Math.sin(angle) * r,
        vx: 0,
        vy: 0,
      });
    });
  }

  const agentsByUser = new Map<string, typeof agents>();
  for (const agent of agents) {
    const key = agent.parent_id ?? "_";
    const list = agentsByUser.get(key) ?? [];
    list.push(agent);
    agentsByUser.set(key, list);
  }
  for (const [userId, list] of agentsByUser) {
    const parent = placed.get(userId);
    list.forEach((agent, i) => {
      const angle = (i / Math.max(list.length, 1)) * Math.PI * 2 - Math.PI / 4;
      const r = 28;
      placed.set(agent.id, {
        ...agent,
        x: (parent?.x ?? cx) + Math.cos(angle) * r,
        y: (parent?.y ?? cy) + Math.sin(angle) * r,
        vx: 0,
        vy: 0,
      });
    });
  }

  return [...placed.values()];
}

function relax(graph: OpsGraph): SimNode[] {
  const nodes = seedNodes(graph);
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const springs = graph.edges.map((e) => ({
    from: byId.get(e.from),
    to: byId.get(e.to),
    kind: e.kind,
    weight: Math.max(e.weight, 0.2),
  })).filter((s) => s.from && s.to);

  for (let tick = 0; tick < 48; tick++) {
    for (let i = 0; i < nodes.length; i++) {
      for (let j = i + 1; j < nodes.length; j++) {
        const a = nodes[i]!;
        const b = nodes[j]!;
        let dx = b.x - a.x;
        let dy = b.y - a.y;
        let dist = Math.hypot(dx, dy) || 0.01;
        const min = nodeRadius(a.kind) + nodeRadius(b.kind) + 18;
        if (dist < min) {
          const push = (min - dist) / dist * 0.12;
          dx *= push;
          dy *= push;
          a.vx -= dx;
          a.vy -= dy;
          b.vx += dx;
          b.vy += dy;
        }
      }
    }
    for (const spring of springs) {
      const a = spring.from!;
      const b = spring.to!;
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const dist = Math.hypot(dx, dy) || 0.01;
      const rest = spring.kind === "slot" ? 36 : 72;
      const k = spring.kind === "self" ? 0.045 : spring.kind === "slot" ? 0.06 : 0.02;
      const f = (dist - rest) * k;
      const fx = (dx / dist) * f;
      const fy = (dy / dist) * f;
      a.vx += fx;
      a.vy += fy;
      b.vx -= fx;
      b.vy -= fy;
    }
    for (const node of nodes) {
      node.vx += (W / 2 - node.x) * 0.004;
      node.vy += (H / 2 - node.y) * 0.004;
      node.vx *= 0.72;
      node.vy *= 0.72;
      node.x = Math.min(W - 24, Math.max(24, node.x + node.vx));
      node.y = Math.min(H - 24, Math.max(24, node.y + node.vy));
    }
  }
  return nodes;
}

export function OpsTrafficWeb({ graph }: { graph: OpsGraph }) {
  const nodes = useMemo(() => relax(graph), [graph]);
  const byId = useMemo(() => new Map(nodes.map((n) => [n.id, n])), [nodes]);
  const hubId = graph.bias.hub_user_id
    ? `user:${graph.bias.hub_user_id}`
    : null;
  const traffic = graph.edges.filter((e) => e.kind !== "slot");
  const slots = graph.edges.filter((e) => e.kind === "slot");
  const maxW = Math.max(1, ...traffic.map((e) => e.weight));
  const starPct = Math.round(graph.bias.star_share * 100);

  if (graph.nodes.length === 0) {
    return (
      <p className="text-sm text-muted">No orgs yet — the web fills as pilots onboard.</p>
    );
  }

  return (
    <article className="rounded-md border border-stone-300/70 bg-white/60 p-4">
      <h2 className="text-[13px] font-semibold tracking-wide text-muted">
        Pilot web
      </h2>
      <p className="mt-1 text-[13px] text-stone-800">
        Amber is a person talking to their own agents. Grey is people-to-people.
        {graph.bias.independent_self_users > 0
          ? ` ${graph.bias.independent_self_users} tester${graph.bias.independent_self_users === 1 ? "" : "s"} have own-agent mail.`
          : " No tester has own-agent traffic yet."}
        {starPct >= 70 && graph.bias.hub_label
          ? ` Star: ${starPct}% of teammate mail touches ${graph.bias.hub_label}.`
          : starPct === 0
            ? " No founder-to-tester star yet."
            : ` Star share ${starPct}%${graph.bias.hub_label ? ` (${graph.bias.hub_label})` : ""}.`}
      </p>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="mt-3 h-80 w-full"
        role="img"
        aria-label="Pilot traffic web"
      >
        {slots.map((e) => {
          const a = byId.get(e.from);
          const b = byId.get(e.to);
          if (!a || !b) return null;
          return (
            <line
              key={`slot-${e.from}-${e.to}`}
              x1={a.x}
              y1={a.y}
              x2={b.x}
              y2={b.y}
              stroke="#e7e5e4"
              strokeWidth={1}
            />
          );
        })}
        {traffic.map((e) => {
          const a = byId.get(e.from);
          const b = byId.get(e.to);
          if (!a || !b) return null;
          const dashed = e.kind === "external" || e.kind === "broadcast";
          return (
            <line
              key={`${e.kind}-${e.from}-${e.to}`}
              x1={a.x}
              y1={a.y}
              x2={b.x}
              y2={b.y}
              stroke={kindColor(e.kind)}
              strokeWidth={1.2 + (e.weight / maxW) * 4}
              strokeOpacity={e.kind === "self" ? 0.9 : 0.55}
              strokeDasharray={dashed ? "4 3" : undefined}
            >
              <title>
                {e.kind} · {e.threads} thread{e.threads === 1 ? "" : "s"} · weight{" "}
                {e.weight}
              </title>
            </line>
          );
        })}
        {nodes.map((n) => (
          <g key={n.id} transform={`translate(${n.x} ${n.y})`}>
            {n.id === hubId ? (
              <circle r={nodeRadius(n.kind) + 5} fill="none" stroke="#b45309" strokeWidth={1.2} />
            ) : null}
            <circle
              r={nodeRadius(n.kind)}
              fill={
                n.kind === "org"
                  ? "#1c1917"
                  : n.kind === "user"
                    ? "#5c4033"
                    : "#a8a29e"
              }
            />
            <text
              y={n.kind === "agent" ? 14 : n.kind === "org" ? -22 : 20}
              textAnchor="middle"
              fill="#57534e"
              fontSize={n.kind === "agent" ? 9 : 11}
              fontWeight={n.kind === "org" ? 600 : 500}
            >
              {n.label}
            </text>
            <title>{n.label}</title>
          </g>
        ))}
      </svg>
      <p className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-muted">
        <span>Black · org</span>
        <span>Brown · person</span>
        <span>Grey · agent</span>
        <span className="text-amber-800">Amber · own agents</span>
        <span>Grey line · teammates / contacts</span>
      </p>
    </article>
  );
}
