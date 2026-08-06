const state = {
  feedback: [],
  waitlist: [],
  charts: {},
  loggedIn: false,
};

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

const $ = (id) => document.getElementById(id);

function setError(msg) {
  const el = $("error");
  if (!msg) {
    el.hidden = true;
    el.textContent = "";
    return;
  }
  el.hidden = false;
  el.textContent = msg;
}

function setAuthUi(loggedIn) {
  state.loggedIn = loggedIn;
  $("login").hidden = loggedIn;
  $("logout").hidden = !loggedIn;
  $("auth-status").textContent = loggedIn ? "Signed in" : "Not signed in";
  $("refresh").disabled = !loggedIn;
}

async function api(path) {
  const res = await fetch(path, {
    headers: { Accept: "application/json" },
    credentials: "same-origin",
    cache: "no-store",
  });
  const text = await res.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = { error: text || res.statusText };
  }
  if (!res.ok) {
    if (res.status === 401) {
      setAuthUi(false);
      throw new Error("Not signed in — use Log in (org admin account).");
    }
    if (res.status === 403) {
      throw new Error(
        "Forbidden — this Auth0 user needs the SuperAdmin role (roles claim on the access token).",
      );
    }
    throw new Error(body?.error || body?.message || res.statusText || "Request failed");
  }
  return body;
}

function daysAgoIso(n) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString();
}

function countLastDays(items, n) {
  const cut = daysAgoIso(n);
  return items.filter((x) => (x.created_at || "") >= cut).length;
}

function uniqueEmails(items) {
  return new Set(
    items.map((x) => (x.email || "").toLowerCase()).filter(Boolean),
  ).size;
}

function tally(values) {
  const map = new Map();
  for (const v of values) {
    const key = v && String(v).trim() ? String(v).trim() : "—";
    map.set(key, (map.get(key) || 0) + 1);
  }
  const entries = [...map.entries()].sort((a, b) =>
    b[1] - a[1] || a[0].localeCompare(b[0])
  );
  return {
    labels: entries.map(([k]) => k),
    data: entries.map(([, n]) => n),
  };
}

function tallyMulti(lists) {
  const flat = [];
  for (const list of lists) {
    if (Array.isArray(list)) flat.push(...list);
  }
  return tally(flat);
}

function tallyByDay(items) {
  const map = new Map();
  for (const item of items) {
    const day = (item.created_at || "").slice(0, 10) || "—";
    map.set(day, (map.get(day) || 0) + 1);
  }
  const labels = [...map.keys()].sort();
  return { labels, data: labels.map((l) => map.get(l)) };
}

function destroyCharts() {
  for (const chart of Object.values(state.charts)) {
    chart?.destroy?.();
  }
  state.charts = {};
}

function makeChart(id, config) {
  const canvas = $(id);
  if (!canvas) return;
  state.charts[id]?.destroy?.();
  state.charts[id] = new Chart(canvas, config);
}

function barOpts(horizontal = false) {
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

function doughnutOpts() {
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

function emptyDataset(series) {
  return !series.labels.length || series.data.every((n) => n === 0);
}

function renderCharts() {
  destroyCharts();
  const { feedback, waitlist } = state;

  const hosts = tallyMulti(waitlist.map((w) => w.ai_hosts));
  const oses = tallyMulti(waitlist.map((w) => w.oses));
  const freq = tally(waitlist.map((w) => w.share_frequency));
  const methods = tallyMulti(waitlist.map((w) => w.share_methods));
  const waitTime = tallyByDay(waitlist);
  const platform = tally(feedback.map((f) => f.platform));
  const category = tally(feedback.map((f) => f.category));
  const fbTime = tallyByDay(feedback);

  const mkBar = (id, series, horizontal = true) => {
    if (emptyDataset(series)) {
      makeChart(id, {
        type: "bar",
        data: {
          labels: ["No data"],
          datasets: [{ data: [0], backgroundColor: "#d6d3d1" }],
        },
        options: barOpts(horizontal),
      });
      return;
    }
    makeChart(id, {
      type: "bar",
      data: {
        labels: series.labels,
        datasets: [{
          data: series.data,
          backgroundColor: series.labels.map((_, i) =>
            PALETTE[i % PALETTE.length]
          ),
          borderWidth: 0,
          borderRadius: 4,
        }],
      },
      options: barOpts(horizontal),
    });
  };

  const mkDoughnut = (id, series) => {
    if (emptyDataset(series)) {
      makeChart(id, {
        type: "doughnut",
        data: {
          labels: ["No data"],
          datasets: [{ data: [1], backgroundColor: ["#d6d3d1"] }],
        },
        options: doughnutOpts(),
      });
      return;
    }
    makeChart(id, {
      type: "doughnut",
      data: {
        labels: series.labels,
        datasets: [{
          data: series.data,
          backgroundColor: series.labels.map((_, i) =>
            PALETTE[i % PALETTE.length]
          ),
          borderWidth: 0,
        }],
      },
      options: doughnutOpts(),
    });
  };

  const mkLine = (id, series) => {
    makeChart(id, {
      type: "line",
      data: {
        labels: series.labels.length ? series.labels : ["—"],
        datasets: [{
          data: series.labels.length ? series.data : [0],
          borderColor: "#5c4033",
          backgroundColor: "rgba(92,64,51,0.12)",
          fill: true,
          tension: 0.25,
          pointRadius: 3,
        }],
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
    });
  };

  mkBar("chart-hosts", hosts, true);
  mkDoughnut("chart-oses", oses);
  mkBar("chart-freq", freq, false);
  mkBar("chart-methods", methods, true);
  mkLine("chart-waitlist-time", waitTime);
  mkDoughnut("chart-platform", platform);
  mkBar("chart-category", category, true);
  mkLine("chart-feedback-time", fbTime);
}

function renderKpis() {
  const { feedback, waitlist } = state;
  $("kpis").innerHTML = [
    { label: "Feedback", value: feedback.length },
    { label: "Waitlist", value: waitlist.length },
    { label: "Feedback 7d", value: countLastDays(feedback, 7) },
    { label: "Waitlist 7d", value: countLastDays(waitlist, 7) },
    { label: "Unique emails", value: uniqueEmails(waitlist) },
  ]
    .map(
      (i) =>
        `<div class="kpi"><div class="label">${i.label}</div><div class="value">${i.value}</div></div>`,
    )
    .join("");
}

function fmtWhen(iso) {
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

function chips(list) {
  if (!Array.isArray(list) || !list.length) return "—";
  return `<span class="chips">${
    list.map((x) => `<span class="chip">${escapeHtml(x)}</span>`).join("")
  }</span>`;
}

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function matchesQuery(row, q) {
  if (!q) return true;
  return JSON.stringify(row).toLowerCase().includes(q);
}

function renderFeedbackTable() {
  const q = ($("filter-feedback").value || "").trim().toLowerCase();
  const rows = state.feedback.filter((f) => matchesQuery(f, q));
  $("count-feedback").textContent = `${rows.length} shown`;
  const tbody = $("tbody-feedback");
  if (!rows.length) {
    tbody.innerHTML =
      `<tr><td colspan="7" class="empty">No feedback yet</td></tr>`;
    return;
  }
  tbody.innerHTML = rows
    .map(
      (f) => `<tr>
      <td>${escapeHtml(fmtWhen(f.created_at))}</td>
      <td>${escapeHtml(f.handle || "—")}</td>
      <td>${escapeHtml(f.email || "—")}</td>
      <td>${escapeHtml(f.platform || "—")}</td>
      <td>${escapeHtml(f.category || "—")}</td>
      <td>${escapeHtml(f.app_version || "—")}</td>
      <td class="message">${escapeHtml(f.message || "")}</td>
    </tr>`,
    )
    .join("");
}

function renderWaitlistTable() {
  const q = ($("filter-waitlist").value || "").trim().toLowerCase();
  const rows = state.waitlist.filter((w) => matchesQuery(w, q));
  $("count-waitlist").textContent = `${rows.length} shown`;
  const tbody = $("tbody-waitlist");
  if (!rows.length) {
    tbody.innerHTML =
      `<tr><td colspan="6" class="empty">No waitlist entries yet</td></tr>`;
    return;
  }
  tbody.innerHTML = rows
    .map(
      (w) => `<tr>
      <td>${escapeHtml(fmtWhen(w.created_at))}</td>
      <td>${escapeHtml(w.email || "—")}</td>
      <td>${chips(w.ai_hosts)}</td>
      <td>${chips(w.oses)}</td>
      <td>${escapeHtml(w.share_frequency || "—")}</td>
      <td>${chips(w.share_methods)}</td>
    </tr>`,
    )
    .join("");
}

async function refresh() {
  setError("");
  if (!state.loggedIn) {
    setError("Log in with your org admin Auth0 account.");
    return;
  }
  $("refresh").disabled = true;
  try {
    const [fb, wl] = await Promise.all([
      api("/api/feedback"),
      api("/api/waitlist"),
    ]);
    state.feedback = Array.isArray(fb?.feedback) ? fb.feedback : [];
    state.waitlist = Array.isArray(wl?.waitlist) ? wl.waitlist : [];
    state.feedback.sort((a, b) =>
      String(b.created_at).localeCompare(String(a.created_at))
    );
    state.waitlist.sort((a, b) =>
      String(b.created_at).localeCompare(String(a.created_at))
    );
    renderKpis();
    renderCharts();
    renderFeedbackTable();
    renderWaitlistTable();
  } catch (err) {
    setError(err instanceof Error ? err.message : String(err));
  } finally {
    $("refresh").disabled = !state.loggedIn;
  }
}

function switchTab(name) {
  document.querySelectorAll(".tab").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.tab === name);
  });
  document.querySelectorAll(".panel").forEach((panel) => {
    panel.classList.toggle("active", panel.id === `panel-${name}`);
  });
}

async function init() {
  $("refresh").addEventListener("click", refresh);
  $("filter-feedback").addEventListener("input", renderFeedbackTable);
  $("filter-waitlist").addEventListener("input", renderWaitlistTable);
  document.querySelectorAll(".tab").forEach((btn) => {
    btn.addEventListener("click", () => switchTab(btn.dataset.tab));
  });

  try {
    const cfg = await api("/api/config");
    setAuthUi(Boolean(cfg.loggedIn));
    $("hub-line").textContent = cfg.loggedIn
      ? `Hub ${cfg.hub}`
      : `Hub ${cfg.hub} · log in as org admin`;
    if (cfg.loggedIn) await refresh();
    else setError("Log in with your org admin Auth0 account.");
  } catch (err) {
    setAuthUi(false);
    setError(err instanceof Error ? err.message : String(err));
  }
}

init();
