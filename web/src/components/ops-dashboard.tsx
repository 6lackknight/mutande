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
} from "chart.js";
import { useEffect, useMemo, useRef, useState } from "react";
import { refreshOpsAction } from "@/app/actions";
import { Alert, Button, Input } from "@/components/ui";
import type { Feedback, WaitlistEntry } from "@/lib/types";

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

type Tab = "overview" | "feedback" | "waitlist";

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

function uniqueEmails(items: WaitlistEntry[]): number {
  return new Set(
    items.map((x) => (x.email || "").toLowerCase()).filter(Boolean),
  ).size;
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

function barOpts(horizontal = false): ChartConfiguration["options"] {
  return {
    indexAxis: horizontal ? "y" : "x",
    responsive: true,
    maintainAspectRatio: true,
    plugins: { legend: { display: false } },
    scales: {
      x: {
        beginAtZero: true,
        ticks: { precision: 0, color: "#78716c" },
        grid: { color: "rgba(168,162,158,0.25)" },
      },
      y: {
        ticks: { color: "#78716c" },
        grid: { color: "rgba(168,162,158,0.15)" },
      },
    },
  };
}

function doughnutOpts(): ChartConfiguration["options"] {
  return {
    responsive: true,
    maintainAspectRatio: true,
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

  return <canvas ref={canvasRef} />;
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
  };
}

export function OpsDashboard({
  initialFeedback,
  initialWaitlist,
  loadError,
}: {
  initialFeedback: Feedback[];
  initialWaitlist: WaitlistEntry[];
  loadError?: string | null;
}) {
  const [feedback, setFeedback] = useState(initialFeedback);
  const [waitlist, setWaitlist] = useState(initialWaitlist);
  const [error, setError] = useState(loadError ?? "");
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<Tab>("overview");
  const [filterFeedback, setFilterFeedback] = useState("");
  const [filterWaitlist, setFilterWaitlist] = useState("");

  const kpis = useMemo(
    () => [
      { label: "Feedback", value: feedback.length },
      { label: "Waitlist", value: waitlist.length },
      { label: "Feedback 7d", value: countLastDays(feedback, 7) },
      { label: "Waitlist 7d", value: countLastDays(waitlist, 7) },
      { label: "Unique emails", value: uniqueEmails(waitlist) },
    ],
    [feedback, waitlist],
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
              className={`min-h-64 rounded-md border border-stone-300/70 bg-white/60 p-4 ${
                wide ? "md:col-span-2" : ""
              }`}
            >
              <h2 className="mb-3 text-[13px] font-semibold tracking-wide text-muted">
                {title}
              </h2>
              <OpsChart chartId={id} config={config} />
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
