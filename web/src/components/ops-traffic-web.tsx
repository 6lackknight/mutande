"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { OpsGraph, OpsGraphEdgeKind, OpsGraphNodeKind } from "@/lib/types";

const WORLD = 1600;

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

type View = { x: number; y: number; k: number };

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
  const cx = WORLD / 2;
  const cy = WORLD / 2;
  const placed = new Map<string, SimNode>();

  orgs.forEach((org, i) => {
    const angle = (i / Math.max(orgs.length, 1)) * Math.PI * 2 - Math.PI / 2;
    const r = orgs.length <= 1 ? 0 : 180;
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
      const r = 90;
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
      const r = 42;
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
  })).filter((s) => s.from && s.to);

  for (let tick = 0; tick < 64; tick++) {
    for (let i = 0; i < nodes.length; i++) {
      for (let j = i + 1; j < nodes.length; j++) {
        const a = nodes[i]!;
        const b = nodes[j]!;
        let dx = b.x - a.x;
        let dy = b.y - a.y;
        const dist = Math.hypot(dx, dy) || 0.01;
        const min = nodeRadius(a.kind) + nodeRadius(b.kind) + 28;
        if (dist < min) {
          const push = (min - dist) / dist * 0.16;
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
      const rest = spring.kind === "slot" ? 48 : 110;
      const k = spring.kind === "self" ? 0.04 : spring.kind === "slot" ? 0.05 : 0.018;
      const f = (dist - rest) * k;
      const fx = (dx / dist) * f;
      const fy = (dy / dist) * f;
      a.vx += fx;
      a.vy += fy;
      b.vx -= fx;
      b.vy -= fy;
    }
    for (const node of nodes) {
      node.vx += (WORLD / 2 - node.x) * 0.002;
      node.vy += (WORLD / 2 - node.y) * 0.002;
      node.vx *= 0.78;
      node.vy *= 0.78;
      node.x += node.vx;
      node.y += node.vy;
    }
  }
  return nodes;
}

function fitView(nodes: SimNode[], width: number, height: number): View {
  if (nodes.length === 0) return { x: 0, y: 0, k: 1 };
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const n of nodes) {
    minX = Math.min(minX, n.x);
    minY = Math.min(minY, n.y);
    maxX = Math.max(maxX, n.x);
    maxY = Math.max(maxY, n.y);
  }
  const pad = 80;
  const bw = Math.max(maxX - minX, 120) + pad * 2;
  const bh = Math.max(maxY - minY, 120) + pad * 2;
  const k = Math.min(width / bw, height / bh, 1.4);
  return {
    x: width / 2 - (minX + maxX) / 2 * k,
    y: height / 2 - (minY + maxY) / 2 * k,
    k,
  };
}

function kindLabel(kind: OpsGraphEdgeKind): string {
  switch (kind) {
    case "self":
      return "own agents";
    case "org":
      return "teammates";
    case "external":
      return "external contact";
    case "broadcast":
      return "broadcast";
    default:
      return "link";
  }
}

export function OpsTrafficWeb({ graph }: { graph: OpsGraph }) {
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const nodes = useMemo(() => relax(graph), [graph]);
  const byId = useMemo(() => new Map(nodes.map((n) => [n.id, n])), [nodes]);
  const [view, setView] = useState<View>({ x: 0, y: 0, k: 1 });
  const viewRef = useRef(view);
  viewRef.current = view;
  const drag = useRef<{
    x: number;
    y: number;
    vx: number;
    vy: number;
    moved: boolean;
  } | null>(null);
  const [panning, setPanning] = useState(false);
  const [hoverId, setHoverId] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const focusId = selectedId ?? hoverId;

  const hubId = graph.bias.hub_user_id
    ? `user:${graph.bias.hub_user_id}`
    : null;
  const traffic = graph.edges.filter((e) => e.kind !== "slot");
  const slots = graph.edges.filter((e) => e.kind === "slot");
  const maxW = Math.max(1, ...traffic.map((e) => e.weight));
  const starPct = Math.round(graph.bias.star_share * 100);

  const neighborIds = useMemo(() => {
    if (!focusId) return null;
    const ids = new Set<string>([focusId]);
    for (const e of graph.edges) {
      if (e.from === focusId) ids.add(e.to);
      if (e.to === focusId) ids.add(e.from);
    }
    return ids;
  }, [focusId, graph.edges]);

  const focusNode = focusId ? byId.get(focusId) : null;
  const focusEdges = focusId
    ? traffic.filter((e) => e.from === focusId || e.to === focusId)
    : [];

  const applyZoom = useCallback((factor: number, cx: number, cy: number) => {
    setView((v) => {
      const nextK = Math.min(8, Math.max(0.25, v.k * factor));
      const ratio = nextK / v.k;
      return {
        k: nextK,
        x: cx - (cx - v.x) * ratio,
        y: cy - (cy - v.y) * ratio,
      };
    });
  }, []);

  const resetView = useCallback(() => {
    const box = wrapRef.current?.getBoundingClientRect();
    setView(fitView(nodes, box?.width ?? 800, box?.height ?? 420));
    setSelectedId(null);
  }, [nodes]);

  useEffect(() => {
    resetView();
  }, [resetView]);

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const onNativeWheel = (event: WheelEvent) => {
      event.preventDefault();
      const box = el.getBoundingClientRect();
      const px = event.clientX - box.left;
      const py = event.clientY - box.top;
      if (event.ctrlKey || event.metaKey) {
        applyZoom(event.deltaY > 0 ? 0.9 : 1.1, px, py);
        return;
      }
      if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) {
        setView((v) => ({ ...v, x: v.x - event.deltaX }));
        return;
      }
      applyZoom(event.deltaY > 0 ? 0.92 : 1.08, px, py);
    };
    el.addEventListener("wheel", onNativeWheel, { passive: false });
    return () => el.removeEventListener("wheel", onNativeWheel);
  }, [applyZoom]);

  const onPointerDown = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return;
    (event.currentTarget as HTMLDivElement).setPointerCapture(event.pointerId);
    drag.current = {
      x: event.clientX,
      y: event.clientY,
      vx: viewRef.current.x,
      vy: viewRef.current.y,
      moved: false,
    };
  }, []);

  const onPointerMove = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    if (!drag.current) return;
    const dx = event.clientX - drag.current.x;
    const dy = event.clientY - drag.current.y;
    if (!drag.current.moved && Math.hypot(dx, dy) < 4) return;
    drag.current.moved = true;
    setPanning(true);
    setView({
      k: viewRef.current.k,
      x: drag.current.vx + dx,
      y: drag.current.vy + dy,
    });
  }, []);

  const onPointerUp = useCallback(() => {
    drag.current = null;
    setPanning(false);
  }, []);

  if (graph.nodes.length === 0) {
    return (
      <p className="text-sm text-muted">No orgs yet — the web fills as pilots onboard.</p>
    );
  }

  const testerCount = graph.bias.independent_self_users;
  const dim = (id: string) =>
    neighborIds ? (neighborIds.has(id) ? 1 : 0.12) : 1;

  return (
    <article className="rounded-md border border-stone-300/70 bg-white/60 p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-[13px] font-semibold tracking-wide text-muted">
            Pilot web
          </h2>
          <p className="mt-1 max-w-2xl text-[13px] text-stone-800">
            Amber is a person talking to their own agents. Grey is people-to-people.
            {testerCount > 0
              ? ` ${testerCount} tester${testerCount === 1 ? " has" : "s have"} own-agent mail.`
              : " No tester has own-agent traffic yet."}
            {starPct >= 70 && graph.bias.hub_label
              ? ` Star: ${starPct}% of teammate mail touches ${graph.bias.hub_label}.`
              : starPct === 0
                ? " No founder-to-tester star yet."
                : ` Star share ${starPct}%${graph.bias.hub_label ? ` (${graph.bias.hub_label})` : ""}.`}
          </p>
        </div>
        <div className="flex gap-1">
          <button
            type="button"
            className="rounded border border-stone-300/80 px-2 py-1 text-[12px] text-stone-700 hover:bg-white"
            onClick={() => {
              const box = wrapRef.current?.getBoundingClientRect();
              applyZoom(1.2, (box?.width ?? 800) / 2, (box?.height ?? 420) / 2);
            }}
          >
            +
          </button>
          <button
            type="button"
            className="rounded border border-stone-300/80 px-2 py-1 text-[12px] text-stone-700 hover:bg-white"
            onClick={() => {
              const box = wrapRef.current?.getBoundingClientRect();
              applyZoom(1 / 1.2, (box?.width ?? 800) / 2, (box?.height ?? 420) / 2);
            }}
          >
            −
          </button>
          <button
            type="button"
            className="rounded border border-stone-300/80 px-2 py-1 text-[12px] text-stone-700 hover:bg-white"
            onClick={resetView}
          >
            Reset
          </button>
        </div>
      </div>

      <div
        ref={wrapRef}
        className="relative mt-3 h-[28rem] overflow-hidden rounded border border-stone-200/80 bg-stone-50/80"
        style={{ touchAction: "none", cursor: panning ? "grabbing" : "grab" }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onDoubleClick={resetView}
      >
        <svg
          width="100%"
          height="100%"
          className="block h-full w-full"
          role="img"
          aria-label="Pilot traffic web"
        >
          <g transform={`translate(${view.x} ${view.y}) scale(${view.k})`}>
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
                  strokeWidth={1 / view.k}
                  opacity={Math.min(dim(e.from), dim(e.to))}
                />
              );
            })}
            {traffic.map((e) => {
              const a = byId.get(e.from);
              const b = byId.get(e.to);
              if (!a || !b) return null;
              const dashed = e.kind === "external" || e.kind === "broadcast";
              const hot = focusId && (e.from === focusId || e.to === focusId);
              return (
                <line
                  key={`${e.kind}-${e.from}-${e.to}`}
                  x1={a.x}
                  y1={a.y}
                  x2={b.x}
                  y2={b.y}
                  stroke={kindColor(e.kind)}
                  strokeWidth={(hot ? 2 : 1.2) + (e.weight / maxW) * 4}
                  strokeOpacity={
                    neighborIds
                      ? hot
                        ? 0.95
                        : 0.08
                      : e.kind === "self"
                        ? 0.9
                        : 0.55
                  }
                  strokeDasharray={dashed ? "4 3" : undefined}
                  vectorEffect="non-scaling-stroke"
                />
              );
            })}
            {nodes.map((n) => {
              const showLabel = view.k >= (n.kind === "agent" ? 1.15 : 0.7) ||
                n.id === focusId;
              return (
                <g
                  key={n.id}
                  transform={`translate(${n.x} ${n.y})`}
                  opacity={dim(n.id)}
                  style={{ cursor: "pointer" }}
                  onPointerDown={(event) => event.stopPropagation()}
                  onPointerEnter={() => setHoverId(n.id)}
                  onPointerLeave={() =>
                    setHoverId((id) => (id === n.id ? null : id))
                  }
                  onClick={(event) => {
                    event.stopPropagation();
                    setSelectedId((id) => (id === n.id ? null : n.id));
                  }}
                >
                  {n.id === hubId ? (
                    <circle
                      r={nodeRadius(n.kind) + 5}
                      fill="none"
                      stroke="#b45309"
                      strokeWidth={1.2}
                    />
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
                    stroke={n.id === focusId ? "#b45309" : "none"}
                    strokeWidth={n.id === focusId ? 2 : 0}
                  />
                  {showLabel ? (
                    <text
                      y={n.kind === "agent" ? 16 : n.kind === "org" ? -22 : 22}
                      textAnchor="middle"
                      fill="#44403c"
                      fontSize={n.kind === "agent" ? 10 : 12}
                      fontWeight={n.kind === "org" ? 600 : 500}
                    >
                      {n.label}
                    </text>
                  ) : null}
                </g>
              );
            })}
          </g>
        </svg>
        <p className="pointer-events-none absolute bottom-2 left-3 text-[11px] text-muted">
          Scroll to zoom · drag to pan · click a node · double-click reset
        </p>
      </div>

      {focusNode ? (
        <p className="mt-2 text-[13px] text-stone-800">
          <span className="font-medium">{focusNode.label}</span>
          <span className="text-muted">
            {" "}
            · {focusNode.kind}
            {focusEdges.length
              ? ` · ${focusEdges.map((e) => {
                const otherId = e.from === focusNode.id ? e.to : e.from;
                const other = byId.get(otherId);
                return `${kindLabel(e.kind)} → ${other?.label ?? "—"} (${e.threads})`;
              }).join(" · ")}`
              : " · no traffic edges"}
          </span>
        </p>
      ) : (
        <p className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-muted">
          <span>Black · org</span>
          <span>Brown · person</span>
          <span>Grey · agent</span>
          <span className="text-amber-800">Amber · own agents</span>
          <span>Grey line · teammates / contacts</span>
        </p>
      )}
    </article>
  );
}
