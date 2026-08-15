"use client";

import {
  ArcElement,
  BarController,
  BarElement,
  CategoryScale,
  Chart,
  DoughnutController,
  Filler,
  Legend,
  LinearScale,
  LineController,
  LineElement,
  PointElement,
  Tooltip,
  type ChartConfiguration,
  type Plugin,
} from "chart.js";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  opsPublishListingAction,
  opsSuspendListingAction,
  opsTopUpCreditsAction,
  opsVerifyListingAction,
  refreshOpsAction,
} from "@/app/actions";
import { Alert, Button, Input } from "@/components/ui";
import type {
  EnterpriseDeliveryMetric,
  Feedback,
  RegistryListing,
  WaitlistEntry,
} from "@/lib/types";

Chart.register(
  CategoryScale,
  LinearScale,
  BarController,
  BarElement,
  DoughnutController,
  ArcElement,
  LineController,
  PointElement,
  LineElement,
  Filler,
  Legend,
  Tooltip,
);

const PALETTE = [
  "#5c4033",
  "#78716c",
  "#a8a29e",
  "#44403c",
  "#292524",
  "#b45309",
  "#57534e",
  "#d6d3d1",
];

type Tab = "overview" | "feedback" | "waitlist" | "enterprise";

type Series = { labels: string[]; data: number[] };

function daysAgoIso(n: number): string {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString();
}

function countLastDays(
  items: { created_at?: string }[],
  n: number,
): number {
  const cut = daysAgoIso(n);
  return items.filter((x) => (x.created_at || "") >= cut).length;
}

function tally(values: (string | undefined | null)[]): Series {
  const map = new Map<string, number>();
  for (const v of values) {
    const key = v && String(v).trim() ? String(v).trim() : "—";
    map.set(key, (map.get(key) || 0) + 1);
  }
  const entries = [...map.entries()].sort(
    (a, b) => b[1] - a[1] || a[0].localeCompare(b[0]),
  );
  return {
    labels: entries.map(([k]) => k),
    data: entries.map(([, n]) => n),
  };
}

function tallyMulti(lists: (string[] | undefined)[]): Series {
  const flat: string[] = [];
  for (const list of lists) {
    if (Array.isArray(list)) flat.push(...list);
  }
  return tally(flat);
}

function tallyByDay(items: { created_at?: string }[]): Series {
  const map = new Map<string, number>();
  for (const item of items) {
    const day = (item.created_at || "").slice(0, 10) || "—";
    map.set(day, (map.get(day) || 0) + 1);
  }
  const labels = [...map.keys()].sort();
  return { labels, data: labels.map((l) => map.get(l) ?? 0) };
}

function emptyDataset(series: Series): boolean {
  return !series.labels.length || series.data.every((n) => n === 0);
}

function hexLuminance(hex: string): number {
  const h = hex.replace("#", "");
  if (h.length !== 6) return 0;
  const r = Number.parseInt(h.slice(0, 2), 16);
  const g = Number.parseInt(h.slice(2, 4), 16);
  const b = Number.parseInt(h.slice(4, 6), 16);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

const inBarLabelsPlugin: Plugin<"bar"> = {
  id: "inBarLabels",
  afterDatasetsDraw(chart) {
    if (chart.options.indexAxis !== "y") return;
    const meta = chart.getDatasetMeta(0);
    if (!meta?.data.length) return;
    const labels = (chart.data.labels ?? []).map(String);
    const colors = chart.data.datasets[0]?.backgroundColor;
    const ctx = chart.ctx;
    ctx.save();
    ctx.font =
      '600 12px -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif';
    ctx.textBaseline = "middle";
    meta.data.forEach((el, i) => {
      const label = labels[i] ?? "";
      if (!label) return;
      const bar = el as BarElement & { base: number };
      const left = Math.min(bar.base, bar.x);
      const right = Math.max(bar.base, bar.x);
      const barW = right - left;
      const pad = 10;
      const textW = ctx.measureText(label).width;
      const color = Array.isArray(colors)
        ? String(colors[i] ?? "")
        : String(colors ?? "");
      const light = hexLuminance(color) > 0.62;
      ctx.textAlign = "left";
      if (barW >= textW + pad * 2) {
        ctx.fillStyle = light ? "#1c1917" : "#fafaf9";
        ctx.fillText(label, left + pad, bar.y);
      } else {
        ctx.fillStyle = "#44403c";
        ctx.fillText(label, right + 8, bar.y);
      }
    });
    ctx.restore();
  },
};

function barOpts(horizontal = false): ChartConfiguration["options"] {
  return {
    indexAxis: horizontal ? "y" : "x",
    responsive: true,
    maintainAspectRatio: false,
    plugins: { legend: { display: false } },
    datasets: horizontal
      ? { bar: { barPercentage: 0.78, categoryPercentage: 0.92 } }
      : undefined,
    scales: {
      x: {
        beginAtZero: true,
        ticks: { precision: 0, color: "#78716c" },
        grid: { color: "rgba(168,162,158,0.25)" },
        border: { display: !horizontal },
      },
      y: {
        ticks: horizontal ? { display: false } : { color: "#78716c" },
        grid: {
          display: !horizontal,
          color: "rgba(168,162,158,0.15)",
        },
        border: { display: !horizontal },
      },
    },
  };
}

function doughnutOpts(): ChartConfiguration["options"] {
  return {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: "bottom",
        labels: { color: "#57534e", boxWidth: 12 },
      },
    },
  };
}

function fmtWhen(iso?: string): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
}

function matchesQuery(row: unknown, q: string): boolean {
  if (!q) return true;
  return JSON.stringify(row).toLowerCase().includes(q);
}

function OpsChart({
  chartId,
  config,
}: {
  chartId: string;
  config: ChartConfiguration | null;
}) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const chartRef = useRef<Chart | null>(null);

  useEffect(() => {
    if (!canvasRef.current || !config) return;
    chartRef.current?.destroy();
    chartRef.current = new Chart(canvasRef.current, config);
    return () => {
      chartRef.current?.destroy();
      chartRef.current = null;
    };
  }, [chartId, config]);

  return (
    <div className="relative h-full w-full">
      <canvas ref={canvasRef} />
    </div>
  );
}

function chartConfig(
  kind: "bar" | "doughnut" | "line",
  series: Series,
  horizontal = true,
): ChartConfiguration {
  if (kind === "line") {
    return {
      type: "line",
      data: {
        labels: series.labels.length ? series.labels : ["—"],
        datasets: [
          {
            data: series.labels.length ? series.data : [0],
            borderColor: "#5c4033",
            backgroundColor: "rgba(92,64,51,0.12)",
            fill: true,
            tension: 0.25,
            pointRadius: 3,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: {
          x: { ticks: { color: "#78716c" }, grid: { display: false } },
          y: {
            beginAtZero: true,
            ticks: { precision: 0, color: "#78716c" },
            grid: { color: "rgba(168,162,158,0.25)" },
          },
        },
      },
    };
  }

  if (emptyDataset(series)) {
    if (kind === "doughnut") {
      return {
        type: "doughnut",
        data: {
          labels: ["No data"],
          datasets: [{ data: [1], backgroundColor: ["#d6d3d1"] }],
        },
        options: doughnutOpts(),
      };
    }
    return {
      type: "bar",
      data: {
        labels: ["No data"],
        datasets: [{ data: [0], backgroundColor: "#d6d3d1" }],
      },
      options: barOpts(horizontal),
      plugins: horizontal ? [inBarLabelsPlugin] : [],
    };
  }

  const colors = series.labels.map((_, i) => PALETTE[i % PALETTE.length]);
  if (kind === "doughnut") {
    return {
      type: "doughnut",
      data: {
        labels: series.labels,
        datasets: [{ data: series.data, backgroundColor: colors, borderWidth: 0 }],
      },
      options: doughnutOpts(),
    };
  }
  return {
    type: "bar",
    data: {
      labels: series.labels,
      datasets: [
        {
          data: series.data,
          backgroundColor: colors,
          borderWidth: 0,
          borderRadius: 4,
        },
      ],
    },
    options: barOpts(horizontal),
    plugins: horizontal ? [inBarLabelsPlugin] : [],
  };
}

export function OpsDashboard({
  initialFeedback,
  initialWaitlist,
  initialListings = [],
  initialMetrics = [],
  loadError,
}: {
  initialFeedback: Feedback[];
  initialWaitlist: WaitlistEntry[];
  initialListings?: RegistryListing[];
  initialMetrics?: EnterpriseDeliveryMetric[];
  loadError?: string | null;
}) {
  const [feedback, setFeedback] = useState(initialFeedback);
  const [waitlist, setWaitlist] = useState(initialWaitlist);
  const [listings, setListings] = useState(initialListings);
  const [metrics, setMetrics] = useState(initialMetrics);
  const [error, setError] = useState(loadError ?? "");
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<Tab>("overview");
  const [filterFeedback, setFilterFeedback] = useState("");
  const [filterWaitlist, setFilterWaitlist] = useState("");
  const [creditOrgId, setCreditOrgId] = useState("");
  const [creditAmount, setCreditAmount] = useState("25.00");
  const [creditNote, setCreditNote] = useState("");

  const kpis = useMemo(
    () => [
      { label: "Feedback", value: feedback.length },
      { label: "Waitlist", value: waitlist.length },
      { label: "Feedback 7d", value: countLastDays(feedback, 7) },
      { label: "Waitlist 7d", value: countLastDays(waitlist, 7) },
      { label: "Listings", value: listings.length },
    ],
    [feedback, waitlist, listings],
  );

  const charts = useMemo(() => {
    const hosts = tallyMulti(waitlist.map((w) => w.ai_hosts));
    const oses = tallyMulti(waitlist.map((w) => w.oses));
    const freq = tally(waitlist.map((w) => w.share_frequency));
    const methods = tallyMulti(waitlist.map((w) => w.share_methods));
    const waitTime = tallyByDay(waitlist);
    const platform = tally(feedback.map((f) => f.platform));
    const category = tally(feedback.map((f) => f.category));
    const fbTime = tallyByDay(feedback);
    return {
      hosts: chartConfig("bar", hosts, true),
      oses: chartConfig("doughnut", oses),
      freq: chartConfig("bar", freq, false),
      methods: chartConfig("bar", methods, true),
      waitTime: chartConfig("line", waitTime),
      platform: chartConfig("doughnut", platform),
      category: chartConfig("bar", category, true),
      fbTime: chartConfig("line", fbTime),
    };
  }, [feedback, waitlist]);

  const feedbackRows = useMemo(() => {
    const q = filterFeedback.trim().toLowerCase();
    return feedback.filter((f) => matchesQuery(f, q));
  }, [feedback, filterFeedback]);

  const waitlistRows = useMemo(() => {
    const q = filterWaitlist.trim().toLowerCase();
    return waitlist.filter((w) => matchesQuery(w, q));
  }, [waitlist, filterWaitlist]);

  async function refresh() {
    setBusy(true);
    setError("");
    try {
      const res = await refreshOpsAction();
      if (res.error) {
        setError(res.error);
        return;
      }
      setFeedback(res.feedback ?? []);
      setWaitlist(res.waitlist ?? []);
      setListings(res.listings ?? []);
      setMetrics(res.metrics ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  async function runListingAction(
    id: string,
    action: "verify" | "publish" | "suspend",
  ) {
    setBusy(true);
    setError("");
    try {
      const fn =
        action === "verify"
          ? opsVerifyListingAction
          : action === "publish"
            ? opsPublishListingAction
            : opsSuspendListingAction;
      const res = await fn(id);
      if (res.error) {
        setError(res.error);
        return;
      }
      if (res.listing) {
        setListings((prev) =>
          prev.map((l) => (l.id === res.listing!.id ? res.listing! : l)),
        );
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  async function topUp() {
    setBusy(true);
    setError("");
    try {
      const res = await opsTopUpCreditsAction({
        org_id: creditOrgId.trim(),
        amount_usd: creditAmount.trim(),
        note: creditNote.trim() || undefined,
      });
      if (res.error) {
        setError(res.error);
        return;
      }
      setCreditNote("");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  const tabs: { id: Tab; label: string }[] = [
    { id: "overview", label: "Overview" },
    { id: "feedback", label: "Feedback" },
    { id: "waitlist", label: "Waitlist" },
    { id: "enterprise", label: "Enterprise" },
  ];

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted">Pilot feedback & waitlist · SuperAdmin</p>
        <Button type="button" variant="secondary" disabled={busy} onClick={refresh}>
          {busy ? "Refreshing…" : "Refresh"}
        </Button>
      </div>

      {error ? <Alert tone="danger">{error}</Alert> : null}

      <section
        className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5"
        aria-label="Summary"
      >
        {kpis.map((k) => (
          <div
            key={k.label}
            className="rounded-md border border-stone-300/70 bg-white/60 px-4 py-3"
          >
            <div className="text-[11px] font-medium uppercase tracking-[0.08em] text-muted">
              {k.label}
            </div>
            <div className="mt-1 font-display text-2xl font-semibold tracking-tight text-stone-900">
              {k.value}
            </div>
          </div>
        ))}
      </section>

      <nav className="flex gap-1 border-b border-stone-300/70" role="tablist">
        {tabs.map((t) => (
          <button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={tab === t.id}
            className={`-mb-px border-b-2 px-3.5 py-2.5 text-sm transition ${
              tab === t.id
                ? "border-accent font-semibold text-stone-900"
                : "border-transparent text-muted hover:text-stone-800"
            }`}
            onClick={() => setTab(t.id)}
          >
            {t.label}
          </button>
        ))}
      </nav>

      {tab === "overview" ? (
        <div className="grid gap-4 md:grid-cols-2">
          {(
            [
              { title: "AI hosts", id: "hosts", config: charts.hosts },
              { title: "OS", id: "oses", config: charts.oses },
              { title: "Share frequency", id: "freq", config: charts.freq },
              { title: "Share methods", id: "methods", config: charts.methods },
              {
                title: "Waitlist signups",
                id: "waitTime",
                config: charts.waitTime,
                wide: true,
              },
              {
                title: "Feedback platform",
                id: "platform",
                config: charts.platform,
              },
              {
                title: "Feedback category",
                id: "category",
                config: charts.category,
              },
              {
                title: "Feedback over time",
                id: "fbTime",
                config: charts.fbTime,
                wide: true,
              },
            ] as {
              title: string;
              id: string;
              config: ChartConfiguration;
              wide?: boolean;
            }[]
          ).map(({ title, id, config, wide }) => (
            <article
              key={id}
              className={`flex min-h-72 flex-col rounded-md border border-stone-300/70 bg-white/60 p-4 ${
                wide ? "md:col-span-2" : ""
              }`}
            >
              <h2 className="mb-3 shrink-0 text-[13px] font-semibold tracking-wide text-muted">
                {title}
              </h2>
              <div className="relative min-h-40 flex-1">
                <OpsChart chartId={id} config={config} />
              </div>
            </article>
          ))}
        </div>
      ) : null}

      {tab === "feedback" ? (
        <div className="space-y-3">
          <div className="flex flex-wrap items-center gap-3">
            <Input
              value={filterFeedback}
              onChange={(e) => setFilterFeedback(e.target.value)}
              placeholder="Filter feedback…"
              type="search"
              className="max-w-md"
            />
            <span className="text-sm text-muted">{feedbackRows.length} shown</span>
          </div>
          <div className="overflow-x-auto rounded-md border border-stone-300/70 bg-white/60">
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="text-left text-[11px] uppercase tracking-[0.06em] text-muted">
                  <th className="px-3 py-2.5 font-semibold">When</th>
                  <th className="px-3 py-2.5 font-semibold">Handle</th>
                  <th className="px-3 py-2.5 font-semibold">Email</th>
                  <th className="px-3 py-2.5 font-semibold">Platform</th>
                  <th className="px-3 py-2.5 font-semibold">Category</th>
                  <th className="px-3 py-2.5 font-semibold">Version</th>
                  <th className="px-3 py-2.5 font-semibold">Message</th>
                </tr>
              </thead>
              <tbody>
                {feedbackRows.length === 0 ? (
                  <tr>
                    <td
                      colSpan={7}
                      className="px-3 py-8 text-center text-muted"
                    >
                      No feedback yet
                    </td>
                  </tr>
                ) : (
                  feedbackRows.map((f) => (
                    <tr
                      key={f.id}
                      className="border-t border-stone-200/80 align-top"
                    >
                      <td className="px-3 py-2.5 whitespace-nowrap">
                        {fmtWhen(f.created_at)}
                      </td>
                      <td className="px-3 py-2.5">{f.handle || "—"}</td>
                      <td className="px-3 py-2.5">{f.email || "—"}</td>
                      <td className="px-3 py-2.5">{f.platform || "—"}</td>
                      <td className="px-3 py-2.5">{f.category || "—"}</td>
                      <td className="px-3 py-2.5">{f.app_version || "—"}</td>
                      <td className="max-w-md px-3 py-2.5 whitespace-pre-wrap break-words">
                        {f.message || ""}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}

      {tab === "waitlist" ? (
        <div className="space-y-3">
          <div className="flex flex-wrap items-center gap-3">
            <Input
              value={filterWaitlist}
              onChange={(e) => setFilterWaitlist(e.target.value)}
              placeholder="Filter waitlist…"
              type="search"
              className="max-w-md"
            />
            <span className="text-sm text-muted">{waitlistRows.length} shown</span>
          </div>
          <div className="overflow-x-auto rounded-md border border-stone-300/70 bg-white/60">
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="text-left text-[11px] uppercase tracking-[0.06em] text-muted">
                  <th className="px-3 py-2.5 font-semibold">When</th>
                  <th className="px-3 py-2.5 font-semibold">Email</th>
                  <th className="px-3 py-2.5 font-semibold">Hosts</th>
                  <th className="px-3 py-2.5 font-semibold">OS</th>
                  <th className="px-3 py-2.5 font-semibold">Frequency</th>
                  <th className="px-3 py-2.5 font-semibold">Methods</th>
                </tr>
              </thead>
              <tbody>
                {waitlistRows.length === 0 ? (
                  <tr>
                    <td
                      colSpan={6}
                      className="px-3 py-8 text-center text-muted"
                    >
                      No waitlist entries yet
                    </td>
                  </tr>
                ) : (
                  waitlistRows.map((w) => (
                    <tr
                      key={w.id}
                      className="border-t border-stone-200/80 align-top"
                    >
                      <td className="px-3 py-2.5 whitespace-nowrap">
                        {fmtWhen(w.created_at)}
                      </td>
                      <td className="px-3 py-2.5">{w.email || "—"}</td>
                      <td className="px-3 py-2.5">
                        <ChipList items={w.ai_hosts} />
                      </td>
                      <td className="px-3 py-2.5">
                        <ChipList items={w.oses} />
                      </td>
                      <td className="px-3 py-2.5">
                        {w.share_frequency || "—"}
                      </td>
                      <td className="px-3 py-2.5">
                        <ChipList items={w.share_methods} />
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}

      {tab === "enterprise" ? (
        <div className="space-y-6">
          <section className="rounded-md border border-stone-300/70 bg-white/60 p-4">
            <h2 className="mb-3 text-[13px] font-semibold tracking-wide text-muted">
              Top up org credits
            </h2>
            <div className="flex flex-wrap items-end gap-3">
              <label className="text-sm">
                <span className="mb-1 block text-muted">Org id</span>
                <Input
                  value={creditOrgId}
                  onChange={(e) => setCreditOrgId(e.target.value)}
                  placeholder="uuid"
                  className="w-64"
                />
              </label>
              <label className="text-sm">
                <span className="mb-1 block text-muted">Amount USD</span>
                <Input
                  value={creditAmount}
                  onChange={(e) => setCreditAmount(e.target.value)}
                  className="w-28"
                />
              </label>
              <label className="text-sm">
                <span className="mb-1 block text-muted">Note</span>
                <Input
                  value={creditNote}
                  onChange={(e) => setCreditNote(e.target.value)}
                  placeholder="pilot grant"
                  className="w-48"
                />
              </label>
              <Button
                type="button"
                disabled={busy || !creditOrgId.trim()}
                onClick={topUp}
              >
                Credit
              </Button>
            </div>
          </section>

          <section className="space-y-3">
            <h2 className="text-[13px] font-semibold tracking-wide text-muted">
              Registry listings · review SLA 5 business days
            </h2>
            <div className="overflow-x-auto rounded-md border border-stone-300/70 bg-white/60">
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="text-left text-[11px] uppercase tracking-[0.06em] text-muted">
                    <th className="px-3 py-2.5 font-semibold">Address</th>
                    <th className="px-3 py-2.5 font-semibold">Status</th>
                    <th className="px-3 py-2.5 font-semibold">Price</th>
                    <th className="px-3 py-2.5 font-semibold">Verified</th>
                    <th className="px-3 py-2.5 font-semibold">Org</th>
                    <th className="px-3 py-2.5 font-semibold">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {listings.length === 0 ? (
                    <tr>
                      <td
                        colSpan={6}
                        className="px-3 py-8 text-center text-muted"
                      >
                        No registry listings
                      </td>
                    </tr>
                  ) : (
                    listings.map((l) => (
                      <tr
                        key={l.id}
                        className="border-t border-stone-200/80 align-top"
                      >
                        <td className="px-3 py-2.5 font-mono text-[13px]">
                          {l.address}
                        </td>
                        <td className="px-3 py-2.5">{l.status}</td>
                        <td className="px-3 py-2.5">
                          ${l.billing.price_usd}
                        </td>
                        <td className="px-3 py-2.5">
                          {l.domain_verified
                            ? l.reserved_org_slug || "yes"
                            : "—"}
                        </td>
                        <td className="px-3 py-2.5 font-mono text-[12px]">
                          {l.org_id.slice(0, 8)}…
                        </td>
                        <td className="px-3 py-2.5">
                          <div className="flex flex-wrap gap-2">
                            {!l.domain_verified ? (
                              <Button
                                type="button"
                                variant="secondary"
                                disabled={busy}
                                onClick={() => runListingAction(l.id, "verify")}
                              >
                                Verify
                              </Button>
                            ) : null}
                            {l.status === "draft" && l.domain_verified ? (
                              <Button
                                type="button"
                                disabled={busy}
                                onClick={() =>
                                  runListingAction(l.id, "publish")
                                }
                              >
                                Publish
                              </Button>
                            ) : null}
                            {l.status === "published" ? (
                              <Button
                                type="button"
                                variant="secondary"
                                disabled={busy}
                                onClick={() =>
                                  runListingAction(l.id, "suspend")
                                }
                              >
                                Suspend
                              </Button>
                            ) : null}
                          </div>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </section>

          <section className="space-y-3">
            <h2 className="text-[13px] font-semibold tracking-wide text-muted">
              Delivery metrics (no PII) · {metrics.length} recent
            </h2>
            <div className="overflow-x-auto rounded-md border border-stone-300/70 bg-white/60">
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="text-left text-[11px] uppercase tracking-[0.06em] text-muted">
                    <th className="px-3 py-2.5 font-semibold">When</th>
                    <th className="px-3 py-2.5 font-semibold">Listing</th>
                    <th className="px-3 py-2.5 font-semibold">Sender org</th>
                    <th className="px-3 py-2.5 font-semibold">Bytes</th>
                    <th className="px-3 py-2.5 font-semibold">Est. tokens</th>
                    <th className="px-3 py-2.5 font-semibold">Blobs</th>
                    <th className="px-3 py-2.5 font-semibold">Latency</th>
                    <th className="px-3 py-2.5 font-semibold">Price¢</th>
                  </tr>
                </thead>
                <tbody>
                  {metrics.length === 0 ? (
                    <tr>
                      <td
                        colSpan={8}
                        className="px-3 py-8 text-center text-muted"
                      >
                        No enterprise deliveries yet
                      </td>
                    </tr>
                  ) : (
                    metrics.map((m) => (
                      <tr
                        key={m.id}
                        className="border-t border-stone-200/80 align-top"
                      >
                        <td className="px-3 py-2.5 whitespace-nowrap">
                          {fmtWhen(m.created_at)}
                        </td>
                        <td className="px-3 py-2.5 font-mono text-[12px]">
                          {m.listing_id.slice(0, 8)}…
                        </td>
                        <td className="px-3 py-2.5 font-mono text-[12px]">
                          {m.sender_org_id.slice(0, 8)}…
                        </td>
                        <td className="px-3 py-2.5">{m.payload_bytes}</td>
                        <td className="px-3 py-2.5">{m.estimated_tokens}</td>
                        <td className="px-3 py-2.5">{m.blob_count}</td>
                        <td className="px-3 py-2.5">{m.latency_ms}ms</td>
                        <td className="px-3 py-2.5">{m.price_cents}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </section>
        </div>
      ) : null}
    </div>
  );
}

function ChipList({ items }: { items?: string[] }) {
  if (!Array.isArray(items) || !items.length) return <span>—</span>;
  return (
    <span className="flex flex-wrap gap-1">
      {items.map((x) => (
        <span
          key={x}
          className="rounded bg-accent/10 px-1.5 py-0.5 text-[12px] text-stone-800"
        >
          {x}
        </span>
      ))}
    </span>
  );
}
