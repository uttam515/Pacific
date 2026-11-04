import { useCallback, useEffect, useRef, useState } from "react";
import {
  Activity,
  ArrowDownToLine,
  ArrowRight,
  ArrowUpRight,
  Battery,
  Check,
  CheckCheck,
  ChevronRight,
  CircleHelp,
  Cloud,
  Cog,
  Database,
  GitBranch,
  Globe,
  LayoutDashboard,
  Menu,
  Network,
  Plus,
  Radio,
  RefreshCw,
  Search,
  Send,
  Server,
  ShieldCheck,
  Signal,
  Smartphone,
  TriangleAlert,
  WifiOff,
  X,
  Zap,
} from "lucide-react";
import {
  makeId,
  applyDemoAction,
  demoSnapshot,
  emptySnapshot,
  event,
  isSnapshot,
  nodeName,
  toggleDemoGateway,
  type Action,
  type Node,
  type Snapshot,
} from "./domain";
import { enqueue, get, put, removeQueued, saveSnapshot } from "./storage";
import {
  fetchSnapshot,
  sendAction,
  validateConnection,
  type Connection,
} from "./api";
const pages = [
  { name: "Overview", icon: LayoutDashboard },
  { name: "Network", icon: Network },
  { name: "Synchronization", icon: RefreshCw },
  { name: "Gateways", icon: Globe },
  { name: "Conflicts", icon: GitBranch },
  { name: "Emergencies", icon: Radio },
];
const ago = (t: number) =>
  !t
    ? "Not observed"
    : Math.max(0, Math.round((Date.now() - t) / 60000)) < 1
      ? "Just now"
      : `${Math.max(0, Math.round((Date.now() - t) / 60000))}m ago`;
const time = (t: number) =>
  new Date(t).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
const badge = (s: string) => (
  <span className={`badge ${s.toLowerCase().replaceAll(" ", "-")}`}>
    <i />
    {s}
  </span>
);
function Topology({ s, select }: { s: Snapshot; select: (n: Node) => void }) {
  const positions = s.nodes.map((_, i) =>
    i < 6
      ? [
          [340, 128],
          [185, 128],
          [73, 47],
          [73, 215],
          [340, 235],
          [480, 65],
        ][i]
      : [460 + (i % 2) * 70, 170 + Math.floor((i - 6) / 2) * 70],
  );
  return (
    <div className="topology">
      <svg
        viewBox={`0 0 580 ${Math.max(320, 240 + Math.ceil(Math.max(0, s.nodes.length - 6) / 2) * 70)}`}
        role="group"
        aria-label="Reported network links. Select a node for details."
      >
        <defs>
          <pattern
            id="dots"
            width="18"
            height="18"
            patternUnits="userSpaceOnUse"
          >
            <circle cx="2" cy="2" r="1" fill="#dfe6df" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#dots)" />
        {s.links.map((l, i) => {
          const a = s.nodes.findIndex((n) => n.id === l.from),
            b = s.nodes.findIndex((n) => n.id === l.to);
          if (a < 0 || b < 0) return null;
          const active =
            s.nodes[a].status === "active" && s.nodes[b].status === "active";
          return (
            <g key={i}>
              <path
                d={`M${positions[a][0]} ${positions[a][1]} L${positions[b][0]} ${positions[b][1]}`}
                stroke={active ? "#88ab7e" : "#bac4bb"}
                strokeWidth="2"
                strokeDasharray={active ? "" : "5 5"}
              />
              {active && (
                <circle
                  cx={(positions[a][0] + positions[b][0]) / 2}
                  cy={(positions[a][1] + positions[b][1]) / 2}
                  r="4"
                  fill="#478364"
                />
              )}
            </g>
          );
        })}
        {s.nodes.map((n, i) => {
          const [x, y] = positions[i],
            active = n.status === "active";
          return (
            <g
              key={n.id}
              role="button"
              tabIndex={0}
              aria-label={`${n.name}, ${n.role}, ${n.status}`}
              onClick={() => select(n)}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  select(n);
                }
              }}
              className="svg-node"
            >
              <circle
                cx={x}
                cy={y}
                r="29"
                fill={active ? "#e7efdf" : "#f1f2ef"}
                stroke={active ? "#afc3a2" : "#cfd5ce"}
              />
              <rect
                x={x - 18}
                y={y - 18}
                width="36"
                height="36"
                rx="10"
                fill={n.role === "gateway" && active ? "#224c3b" : "white"}
                stroke="#dae3d6"
              />
              {n.role === "client" ? (
                <Smartphone
                  x={x - 9}
                  y={y - 9}
                  width={18}
                  height={18}
                  color={active ? "#355744" : "#919b92"}
                />
              ) : n.role === "relay" ? (
                <Network
                  x={x - 9}
                  y={y - 9}
                  width={18}
                  height={18}
                  color="#355744"
                />
              ) : (
                <Server
                  x={x - 9}
                  y={y - 9}
                  width={18}
                  height={18}
                  color={active ? "white" : "#919b92"}
                />
              )}
              <circle
                cx={x + 23}
                cy={y - 18}
                r="5"
                fill={active ? "#679a56" : "#b3b8b1"}
                stroke="white"
                strokeWidth="2"
              />
              <text
                x={x}
                y={y + 43}
                textAnchor="middle"
                fontSize="11"
                fontWeight="600"
                fill="#314536"
              >
                {n.name}
              </text>
              <text
                x={x}
                y={y + 58}
                textAnchor="middle"
                fontSize="10"
                fill="#849083"
              >
                {n.role === "gateway"
                  ? s.gateways.find((g) => g.nodeId === n.id)?.selected
                    ? "Selected gateway"
                    : "Standby gateway"
                  : n.status === "unreachable"
                    ? "Last known position"
                    : n.platform}
              </text>
            </g>
          );
        })}
      </svg>
      {!s.nodes.length && (
        <div className="empty">
          No observed nodes yet. Connect a compatible backend to load network
          data.
        </div>
      )}
    </div>
  );
}
export default function App() {
  const [page, setPage] = useState("Overview"),
    [s, setS] = useState<Snapshot>(emptySnapshot),
    [mode, setMode] = useState<"demo" | "live">("live"),
    [connection, setConnection] = useState<Connection>({
      apiUrl: "",
      wsUrl: "",
    }),
    [ready, setReady] = useState(false),
    [status, setStatus] = useState("Loading"),
    [error, setError] = useState(""),
    [storageError, setStorageError] = useState(""),
    [online, setOnline] = useState(navigator.onLine),
    [modal, setModal] = useState<
      "settings" | "announcement" | "demo" | "help" | null
    >(null),
    [selected, setSelected] = useState<Node | null>(null),
    [query, setQuery] = useState(""),
    [filter, setFilter] = useState("all"),
    [toast, setToast] = useState(""),
    [pending, setPending] = useState(0),
    [busy, setBusy] = useState(false),
    [mobile, setMobile] = useState(false),
    [announcement, setAnnouncement] = useState(""),
    [clock, setClock] = useState(Date.now());
  const refreshRef = useRef<() => Promise<void>>(async () => {}),
    busyRef = useRef(false),
    generation = useRef(0);
  const scope = `live:${connection.apiUrl}`;
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const c = await get<Connection>("connection");
        const m = await get<"demo" | "live">("mode");
        const nextMode = m === "live" && c ? "live" : "demo";
        const cached = await get<Snapshot>(
          `snapshot:${nextMode === "demo" ? "demo" : `live:${c?.apiUrl}`}`,
        );
        if (alive) {
          setConnection(c || { apiUrl: "", wsUrl: "" });
          setMode(nextMode);
          setS(
            isSnapshot(cached)
              ? cached
              : nextMode === "demo"
                ? demoSnapshot()
                : emptySnapshot(),
          );
        }
      } catch {
        if (alive) {
          setS(demoSnapshot());
          setStorageError(
            "Local storage is unavailable. Changes cannot be saved reliably.",
          );
        }
      } finally {
        if (alive) setReady(true);
      }
    })();
    return () => {
      alive = false;
    };
  }, []);
  useEffect(() => {
    const on = () => setOnline(navigator.onLine);
    window.addEventListener("online", on);
    window.addEventListener("offline", on);
    const t = setInterval(() => setClock(Date.now()), 30000);
    return () => {
      window.removeEventListener("online", on);
      window.removeEventListener("offline", on);
      clearInterval(t);
    };
  }, []);
  useEffect(() => {
    if (toast) {
      const t = setTimeout(() => setToast(""), 4500);
      return () => clearTimeout(t);
    }
  }, [toast]);
  useEffect(() => {
    setQuery("");
    setFilter("all");
    setMobile(false);
  }, [page]);
  useEffect(() => {
    if (!ready) return;
    let disposed = false;
    const gen = ++generation.current;
    let socket: WebSocket | undefined;
    let reconnect: ReturnType<typeof setTimeout>;
    let flight = false;
    const refresh = async () => {
      if (flight || disposed) return;
      flight = true;
      try {
        if (mode === "demo") {
          setStatus("Demo workspace");
          return;
        }
        setStatus("Connecting");
        const data = await fetchSnapshot(connection);
        if (disposed || gen !== generation.current) return;
        setS(data);
        setError("");
        setStatus("Connected");
        await saveSnapshot(scope, data);
        setPending(((await get<Action[]>(`outbox:${scope}`)) || []).length);
      } catch (e) {
        if (!disposed) {
          setStatus("Disconnected");
          setError(e instanceof Error ? e.message : "Unable to connect");
        }
      } finally {
        flight = false;
      }
    };
    refreshRef.current = refresh;
    refresh();
    const poll = setInterval(refresh, 15000);
    function connectSocket() {
      if (disposed || mode !== "live" || !connection.wsUrl) return;
      try {
        socket = new WebSocket(connection.wsUrl);
        socket.onmessage = () => {
          void refresh();
        };
        socket.onclose = () => {
          if (!disposed) reconnect = setTimeout(connectSocket, 5000);
        };
        socket.onerror = () => socket?.close();
      } catch {
        /* REST polling remains available. */
      }
    }
    connectSocket();
    return () => {
      disposed = true;
      clearInterval(poll);
      clearTimeout(reconnect);
      socket?.close();
    };
  }, [mode, connection, ready, scope]);
  const flush = useCallback(async () => {
    if (mode !== "live" || busyRef.current) return;
    busyRef.current = true;
    const gen = generation.current;
    try {
      const queue = (await get<Action[]>(`outbox:${scope}`)) || [];
      for (const action of queue) {
        if (gen !== generation.current) break;
        await sendAction(connection, action);
        await removeQueued(scope, action.operationId);
      }
      if (gen === generation.current) {
        setPending(((await get<Action[]>(`outbox:${scope}`)) || []).length);
        if (queue.length) await refreshRef.current();
      }
    } catch (e) {
      if (gen === generation.current)
        setError(e instanceof Error ? e.message : "Action remains queued");
    } finally {
      busyRef.current = false;
    }
  }, [mode, connection, scope]);
  useEffect(() => {
    if (!ready || mode !== "live") return;
    void flush();
    const t = setInterval(() => void flush(), 15000);
    return () => clearInterval(t);
  }, [flush, ready, mode, online]);
  async function commitDemo(next: Snapshot) {
    await saveSnapshot("demo", next);
    setStorageError("");
    setS(next);
  }
  async function act(part: Omit<Action, "operationId" | "createdAt">) {
    if (busy) return false;
    setBusy(true);
    try {
      const action = { ...part, operationId: makeId(), createdAt: Date.now() };
      if (mode === "demo") {
        await commitDemo(applyDemoAction(s, action));
        setToast("Saved in demo workspace");
      } else {
        await enqueue(scope, action);
        setPending(((await get<Action[]>(`outbox:${scope}`)) || []).length);
        setToast("Action saved locally. Waiting for server acknowledgment.");
        await flush();
      }
      return true;
    } catch (e) {
      setStorageError(
        "Could not persist this action. Please export your current data and check browser storage.",
      );
      return false;
    } finally {
      setBusy(false);
    }
  }
  async function switchMode(next: "demo" | "live", c = connection) {
    try {
      if (next === "live") validateConnection(c);
      const cached = await get<Snapshot>(
        `snapshot:${next === "demo" ? "demo" : `live:${c.apiUrl}`}`,
      );
      await put("connection", c);
      await put("mode", next);
      setS(
        isSnapshot(cached)
          ? cached
          : next === "demo"
            ? demoSnapshot()
            : emptySnapshot(),
      );
      setConnection(c);
      setMode(next);
      setError("");
      setPending(0);
      setModal(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save connection");
    }
  }
  function exportData() {
    const url = URL.createObjectURL(
      new Blob(
        [
          JSON.stringify(
            { source: mode, exportedAt: new Date().toISOString(), snapshot: s },
            null,
            2,
          ),
        ],
        { type: "application/json" },
      ),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = `offgrid-${mode}-snapshot.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    setToast("Snapshot exported");
  }
  const active = s.nodes.filter((n) => n.status === "active").length,
    synced = s.operations.filter((o) => o.status === "synced").length,
    queued = s.operations.filter(
      (o) => o.status === "queued" || o.status === "relayed",
    ).length,
    unresolved = s.conflicts.filter((c) => !c.resolved).length,
    newAlerts = s.alerts.filter((a) => a.status === "new").length,
    stale =
      mode === "live" &&
      (status !== "Connected" || clock - s.observedAt > 45000),
    match = (text: string) => text.toLowerCase().includes(query.toLowerCase());
  const view = (name: string) => setPage(name);
  function operations() {
    const list = s.operations.filter(
      (o) =>
        (filter === "all" || o.status === filter) &&
        match(`${o.id} ${o.kind} ${nodeName(s, o.origin)}`),
    );
    return (
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Operation</th>
              <th>Origin node</th>
              <th>Status</th>
              <th>Hops</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            {list.slice(0, 100).map((o) => (
              <tr key={o.id}>
                <td>
                  <span className="cell-main">{o.kind}</span>
                  <small className="mono">{o.id.slice(0, 18)}</small>
                </td>
                <td>{nodeName(s, o.origin)}</td>
                <td>{badge(o.status)}</td>
                <td>{o.hops}</td>
                <td className="muted">{time(o.createdAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {!list.length && (
          <div className="empty">No operations match this view.</div>
        )}
        {list.length > 100 && (
          <p className="muted">
            Showing the first 100 matching operations. Export to inspect the
            full snapshot.
          </p>
        )}
      </div>
    );
  }
  function alerts(compact = false) {
    const list = s.alerts.filter((a) =>
      compact
        ? a.status !== "resolved"
        : (filter === "all" || a.status === filter) &&
          match(`${a.title} ${a.location}`),
    );
    return (
      <div className="alert-list">
        {list.slice(0, compact ? 3 : 100).map((a) => (
          <article className="alert-item" key={a.id}>
            <div className={`alert-icon ${a.status}`}>
              <Radio size={17} />
            </div>
            <div className="alert-body">
              <div className="row">
                <span className="eyebrow">{a.category}</span>
                <small>{ago(a.createdAt)}</small>
              </div>
              <h4>{a.title}</h4>
              <p>{a.location}</p>
              <div className="row">
                {badge(a.status)}
                {!compact && a.status !== "resolved" && (
                  <button
                    disabled={busy}
                    className="text-button"
                    onClick={() =>
                      void act({
                        type:
                          a.status === "new" ? "ACK_ALERT" : "RESOLVE_ALERT",
                        entityId: a.id,
                      })
                    }
                  >
                    {a.status === "new" ? "Acknowledge" : "Resolve"}
                    <Check size={14} />
                  </button>
                )}
              </div>
            </div>
          </article>
        ))}
        {!list.length && (
          <div className="empty">
            <ShieldCheck />
            No alerts in this view.
          </div>
        )}
      </div>
    );
  }
  return (
    <div className="app">
      <a className="skip" href="#main">
        Skip to content
      </a>
      <aside className={mobile ? "sidebar open" : "sidebar"}>
        <a
          className="brand"
          href="#"
          onClick={(e) => {
            e.preventDefault();
            view("Overview");
          }}
        >
          <span className="brand-mark">
            <Network size={23} />
          </span>
          <span>
            OFFGRID<small>CONNECTED. EVEN OFFLINE.</small>
          </span>
        </a>
        <div className="workspace">
          <span className="workspace-icon">
            <Radio size={18} />
          </span>
          <div>
            Campus operations
            <small>
              {mode === "demo"
                ? "Demonstration workspace"
                : "Connected workspace"}
            </small>
          </div>
          <span className="tiny-dot" />
        </div>
        <p className="nav-label">WORKSPACE</p>
        <nav>
          {pages.map((p) => (
            <button
              key={p.name}
              className={page === p.name ? "nav-item active" : "nav-item"}
              onClick={() => view(p.name)}
              aria-current={page === p.name ? "page" : undefined}
            >
              <p.icon size={18} />
              <span>{p.name}</span>
              {p.name === "Conflicts" && unresolved > 0 && <b>{unresolved}</b>}
              {p.name === "Emergencies" && newAlerts > 0 && (
                <b className="urgent-count">{newAlerts}</b>
              )}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="resilience">
            <span>
              <ShieldCheck size={16} /> Local-first by design
            </span>
            <p>
              Every operation matters.
              <br />
              Keep it safe. Keep it moving.
            </p>
          </div>
          <button className="nav-item" onClick={() => setModal("help")}>
            <CircleHelp size={18} />
            How OFFGRID works
          </button>
          <button className="nav-item" onClick={() => setModal("settings")}>
            <Cog size={18} />
            Connection settings
          </button>
          <div className="profile">
            <span>DC</span>
            <div>
              Danveer Cheema<small>Engineer 1 · Operations</small>
            </div>
            <span className="profile-dot" />
          </div>
        </div>
      </aside>
      {mobile && (
        <button
          className="scrim"
          aria-label="Close navigation"
          onClick={() => setMobile(false)}
        />
      )}
      <div className="shell">
        <header className="topbar">
          <div className="breadcrumb">
            <button
              className="mobile-toggle icon-button"
              aria-label="Open navigation"
              onClick={() => setMobile(!mobile)}
            >
              <Menu />
            </button>
            <span>Workspace</span>
            <ChevronRight size={13} />
            <strong>{page}</strong>
          </div>
          <div className="top-actions">
            <span className="connection-pill">
              <i className={stale ? "amber" : "green"} />
              {mode === "demo"
                ? "Demo data"
                : stale
                  ? "Connection interrupted"
                  : "Backend connected"}
            </span>
            <button
              className="icon-button"
              title="Connection settings"
              aria-label="Connection settings"
              onClick={() => setModal("settings")}
            >
              <Cog size={18} />
            </button>
            <span className="avatar">DC</span>
          </div>
        </header>
        <main id="main">
          <div className="heading">
            <div>
              <div className="eyebrow overline">
                OFFGRID / OPERATIONS CENTER
              </div>
              <h1>{page === "Overview" ? "Network overview" : page}</h1>
              <p>
                {
                  (
                    {
                      Overview:
                        "A clear picture of your network. Every node, every operation.",
                      Network:
                        "Explore observed connections and the last known state of each node.",
                      Synchronization:
                        "Follow operations from local storage to server acknowledgment.",
                      Gateways:
                        "Keep an eye on reachable gateways and alternative paths.",
                      Conflicts:
                        "Review competing edits without losing either version.",
                      Emergencies:
                        "Track incoming requests and coordinate your response.",
                    } as Record<string, string>
                  )[page]
                }
              </p>
            </div>
            <div className="heading-actions">
              <button className="button" onClick={exportData}>
                <ArrowDownToLine size={15} />
                Export
              </button>
              <button
                className="button primary"
                onClick={() => setModal("announcement")}
              >
                <Plus size={16} />
                Announcement
              </button>
            </div>
          </div>
          {(error || storageError) && (
            <div className="notice warning" role="alert">
              <TriangleAlert size={18} />
              <span>
                {storageError || error}
                {mode === "live" &&
                  " · Last known data is retained. No simulated data is substituted."}
              </span>
              <button
                className="text-button"
                onClick={() => setModal("settings")}
              >
                Settings
              </button>
            </div>
          )}
          <div
            className={`notice ${mode === "demo" ? "demo" : stale ? "warning" : "healthy"}`}
          >
            <span className="notice-symbol">
              {mode === "demo" ? (
                <Flask />
              ) : stale ? (
                <WifiOff size={17} />
              ) : (
                <ShieldCheck size={17} />
              )}
            </span>
            <div>
              <strong>
                {mode === "demo"
                  ? "Demo environment"
                  : stale
                    ? "Viewing last known state"
                    : "Connected to your backend"}
              </strong>
              <span>
                {mode === "demo"
                  ? "Sample network · actions are saved only in this browser."
                  : `Observed ${ago(s.observedAt)}${!online ? " · browser reports offline" : ""}${pending ? ` · ${pending} local actions awaiting acknowledgment` : ""}`}
              </span>
            </div>
            <button
              className="text-button"
              onClick={() =>
                mode === "demo" ? setModal("demo") : void refreshRef.current()
              }
            >
              {mode === "demo" ? "Demo controls" : "Refresh"}
              <ArrowRight size={15} />
            </button>
          </div>
          {page === "Overview" && (
            <>
              <div className="metrics">
                <Metric
                  title="Reachable nodes"
                  value={`${active}`}
                  suffix={`/ ${s.nodes.length}`}
                  icon={<Network size={18} />}
                  detail={`${s.nodes.length - active} not currently reachable`}
                  tone="green"
                />
                <Metric
                  title="Synchronized operations"
                  value={`${synced}`}
                  suffix={`/ ${s.operations.length}`}
                  icon={<CheckCheck size={18} />}
                  detail={`${queued} awaiting synchronization`}
                  tone="green"
                />
                <Metric
                  title="Needs attention"
                  value={`${newAlerts + unresolved}`}
                  icon={<TriangleAlert size={18} />}
                  detail={`${newAlerts} new alert${newAlerts === 1 ? "" : "s"} · ${unresolved} unresolved conflict${unresolved === 1 ? "" : "s"}`}
                  tone="amber"
                />
              </div>
              <div className="overview-grid">
                <section className="panel">
                  <PanelTitle
                    title="Network topology"
                    subtitle={
                      mode === "demo"
                        ? "Illustrative links · click a node to inspect"
                        : "Reported links · click a node to inspect"
                    }
                    action={() => view("Network")}
                  />
                  <Topology s={s} select={setSelected} />
                  <div className="legend">
                    <span>
                      <i className="green" />
                      Reachable
                    </span>
                    <span>
                      <i className="gray" />
                      Unreachable
                    </span>
                    <span>
                      <i className="line" />
                      Reported link
                    </span>
                    <span className="legend-note">
                      {s.gateways.filter((g) => g.reachable).length} gateways
                      available
                    </span>
                  </div>
                </section>
                <section className="panel">
                  <PanelTitle
                    title="Emergency inbox"
                    subtitle="Requests that need a response"
                    action={() => view("Emergencies")}
                  />
                  {alerts(true)}
                  <button
                    className="panel-footer"
                    onClick={() => view("Emergencies")}
                  >
                    Open emergency monitor
                    <ArrowRight size={15} />
                  </button>
                </section>
              </div>
              <div className="bottom-grid">
                <section className="panel">
                  <PanelTitle
                    title="Recent activity"
                    subtitle={
                      mode === "demo"
                        ? "Scenario history"
                        : "Latest reported network events"
                    }
                    action={() => view("Synchronization")}
                  />
                  <ActivityList s={s} count={4} />
                </section>
                <section className="panel sync-summary">
                  <PanelTitle
                    title="Synchronization health"
                    subtitle="Progress across observed operations"
                  />
                  <div className="sync-number">
                    {s.operations.length
                      ? Math.round((synced / s.operations.length) * 100)
                      : 0}
                    <span>%</span>
                    <span className="synced-label">committed to backend</span>
                  </div>
                  <div className="progress">
                    <span
                      style={{
                        width: `${s.operations.length ? (synced / s.operations.length) * 100 : 0}%`,
                      }}
                    />
                  </div>
                  <div className="summary-row">
                    <span>
                      <i className="green" />
                      Synchronized
                    </span>
                    <b>{synced}</b>
                  </div>
                  <div className="summary-row">
                    <span>
                      <i className="amber" />
                      Queued or relayed
                    </span>
                    <b>{queued}</b>
                  </div>
                  <div className="summary-row">
                    <span>
                      <i className="gray" />
                      Conflicting operations
                    </span>
                    <b>
                      {
                        s.operations.filter((o) => o.status === "conflict")
                          .length
                      }
                    </b>
                  </div>
                  <button
                    className="panel-footer"
                    onClick={() => view("Synchronization")}
                  >
                    Inspect operation queue
                    <ArrowRight size={15} />
                  </button>
                </section>
              </div>
            </>
          )}
          {page === "Network" && (
            <>
              <section className="panel">
                <PanelTitle
                  title="Observed network"
                  subtitle="Links indicate reported connectivity, not guaranteed delivery."
                />
                <Topology s={s} select={setSelected} />
              </section>
              <section className="panel spaced">
                <Toolbar
                  query={query}
                  setQuery={setQuery}
                  filter={filter}
                  setFilter={setFilter}
                  options={["all", "active", "unreachable"]}
                  placeholder="Find a node…"
                />
                <div className="node-grid">
                  {s.nodes
                    .filter(
                      (n) =>
                        (filter === "all" || n.status === filter) &&
                        match(`${n.name} ${n.platform}`),
                    )
                    .map((n) => (
                      <button
                        className="node-card"
                        key={n.id}
                        onClick={() => setSelected(n)}
                      >
                        <div className="row">
                          <span className="square-icon">
                            {n.role === "client" ? (
                              <Smartphone size={20} />
                            ) : (
                              <Server size={20} />
                            )}
                          </span>
                          {badge(n.status)}
                        </div>
                        <h3>{n.name}</h3>
                        <p>
                          {n.platform} · {n.role}
                        </p>
                        <div className="row muted">
                          <span>{ago(n.lastSeen)}</span>
                          <span>
                            <Battery size={13} /> {n.battery ?? "—"}%
                          </span>
                        </div>
                      </button>
                    ))}
                </div>
              </section>
            </>
          )}
          {page === "Synchronization" && (
            <section className="panel">
              <PanelTitle
                title="Operation queue"
                subtitle={`${pending} dashboard actions awaiting server acknowledgment`}
              >
                <button
                  className="button"
                  disabled={busy}
                  onClick={() => void act({ type: "RETRY_SYNC" })}
                >
                  <RefreshCw size={15} />
                  Request sync
                </button>
              </PanelTitle>
              <Toolbar
                query={query}
                setQuery={setQuery}
                filter={filter}
                setFilter={setFilter}
                options={["all", "queued", "relayed", "synced", "conflict"]}
                placeholder="Search operation or node…"
              />
              {operations()}
              <div className="info-foot">
                <ShieldCheck size={16} />
                Relayed means a peer received the operation. Synced means the
                server committed it.
              </div>
            </section>
          )}
          {page === "Gateways" && (
            <>
              <div className="gateway-grid">
                {s.gateways.map((g) => (
                  <section className="panel gateway" key={g.nodeId}>
                    <div className="row">
                      <span
                        className={`gateway-symbol ${g.selected ? "selected" : ""}`}
                      >
                        <Globe size={25} />
                      </span>
                      {badge(
                        g.reachable
                          ? g.selected
                            ? "selected"
                            : "standby"
                          : "unreachable",
                      )}
                    </div>
                    <h2>{nodeName(s, g.nodeId)}</h2>
                    <p>
                      {g.selected
                        ? "Currently selected by the routing engine"
                        : "Alternative path when reachable"}
                    </p>
                    <div className="gateway-stats">
                      <div>
                        <small>Reported latency</small>
                        <strong>{g.reachable ? `${g.latency} ms` : "—"}</strong>
                      </div>
                      <div>
                        <small>Backend reachability</small>
                        <strong>
                          {g.reachable ? "Available" : "Unavailable"}
                        </strong>
                      </div>
                    </div>
                  </section>
                ))}
              </div>
              {!s.gateways.length && (
                <div className="panel empty">No gateways reported yet.</div>
              )}
              <div className="notice healthy spaced">
                <GitBranch size={18} />
                <div>
                  <strong>
                    Routing decisions stay with the network engine
                  </strong>
                  <span>
                    The dashboard observes gateway selection. An alternative
                    must be reachable before failover can succeed.
                  </span>
                </div>
              </div>
              <section className="panel spaced">
                <PanelTitle title="Network activity" />
                <ActivityList s={s} count={12} />
              </section>
            </>
          )}
          {page === "Conflicts" && (
            <>
              <div className="notice healthy">
                <GitBranch size={18} />
                <div>
                  <strong>Both versions stay preserved</strong>
                  <span>
                    Choose a version after reviewing the source. In live mode,
                    resolution is complete only after backend confirmation.
                  </span>
                </div>
              </div>
              {s.conflicts.map((c) => (
                <section className="panel conflict spaced" key={c.id}>
                  <div className="row">
                    <div>
                      <span className="eyebrow">
                        ANNOUNCEMENT · BASE VERSION {c.baseVersion}
                      </span>
                      <h2>{c.entity}</h2>
                    </div>
                    {badge(c.resolved ? "resolved" : "conflict")}
                  </div>
                  <div className="versions">
                    {(["left", "right"] as const).map((side) => (
                      <div
                        key={side}
                        className={
                          c.resolved === side ? "version chosen" : "version"
                        }
                      >
                        <div className="row">
                          <strong>
                            {side === "left" ? c.leftNode : c.rightNode}
                          </strong>
                          <span className="muted">
                            Version {side === "left" ? "A" : "B"}
                          </span>
                        </div>
                        <p>{c[side]}</p>
                        <button
                          className="button"
                          disabled={!!c.resolved || busy}
                          onClick={() =>
                            void act({
                              type: "RESOLVE_CONFLICT",
                              entityId: c.id,
                              choice: side,
                            })
                          }
                        >
                          {c.resolved === side ? (
                            <Check size={15} />
                          ) : (
                            <GitBranch size={15} />
                          )}{" "}
                          {c.resolved === side
                            ? "Selected version"
                            : "Keep this version"}
                        </button>
                      </div>
                    ))}
                  </div>
                </section>
              ))}
              {!s.conflicts.length && (
                <div className="panel empty">
                  <ShieldCheck />
                  No conflicts reported.
                </div>
              )}
            </>
          )}
          {page === "Emergencies" && (
            <section className="panel">
              <Toolbar
                query={query}
                setQuery={setQuery}
                filter={filter}
                setFilter={setFilter}
                options={["all", "new", "acknowledged", "resolved"]}
                placeholder="Search alerts or locations…"
              />
              {alerts()}
              <div className="info-foot">
                <Radio size={16} />
                Operator acknowledgment records that this alert was reviewed. It
                does not confirm that help has arrived.
              </div>
            </section>
          )}
          <footer>
            <span>
              <span className="tiny-dot" /> OFFGRID CORE{" "}
              <span className="footer-divider">/</span> Operations dashboard
            </span>
            <span>
              {mode === "demo"
                ? "Demonstration data"
                : `Last snapshot: ${s.observedAt ? new Date(s.observedAt).toLocaleString() : "not available"}`}{" "}
              · v0.1
            </span>
          </footer>
        </main>
      </div>
      {toast && (
        <div className="toast" role="status">
          <Check size={17} />
          {toast}
        </div>
      )}
      {selected && (
        <Dialog title={selected.name} close={() => setSelected(null)}>
          <div className="detail-grid">
            <span>Node ID</span>
            <code>{selected.id}</code>
            <span>Platform</span>
            <strong>{selected.platform}</strong>
            <span>Role</span>
            <strong>{selected.role}</strong>
            <span>Last reported state</span>
            {badge(selected.status)}
            <span>Last seen</span>
            <strong>{new Date(selected.lastSeen).toLocaleString()}</strong>
            <span>Battery</span>
            <strong>
              {selected.battery ?? "Unknown"}
              {selected.battery !== undefined ? "%" : ""}
            </strong>
          </div>
          <p className="hint">
            A missing heartbeat indicates lost visibility, not proof that this
            device stopped working.
          </p>
        </Dialog>
      )}
      {modal === "settings" && (
        <Dialog
          title="Connection settings"
          close={() => {
            setModal(null);
            setError("");
          }}
        >
          <Settings
            current={connection}
            mode={mode}
            error={error}
            connect={(c) => void switchMode("live", c)}
            demo={() => void switchMode("demo")}
          />
        </Dialog>
      )}
      {modal === "announcement" && (
        <Dialog title="New announcement" close={() => setModal(null)}>
          <p className="hint">
            {mode === "demo"
              ? "Saved as a queued operation in this demo workspace."
              : "Saved to your local outbox before transmission. Publishing requires backend acknowledgment."}
          </p>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              const saved = await act({
                type: "CREATE_ANNOUNCEMENT",
                text: announcement.trim(),
              });
              if (saved) {
                setAnnouncement("");
                setModal(null);
              }
            }}
          >
            <label>
              Announcement
              <textarea
                required
                maxLength={1000}
                minLength={3}
                value={announcement}
                onChange={(e) => setAnnouncement(e.target.value)}
                placeholder="Share an update with your network…"
              />
            </label>
            <div className="row">
              <small className="muted">
                {announcement.length}/1000 characters
              </small>
              <button
                className="button primary"
                disabled={busy || announcement.trim().length < 3}
              >
                <Send size={15} />
                Save announcement
              </button>
            </div>
          </form>
        </Dialog>
      )}
      {modal === "demo" && (
        <Dialog title="Explore the demo" close={() => setModal(null)}>
          <p className="hint">
            These controls simulate events locally. They do not control physical
            devices or prove actual mesh networking.
          </p>
          <div className="demo-controls">
            <button
              className="button"
              onClick={async () => {
                try {
                  await commitDemo(toggleDemoGateway(s));
                  setModal(null);
                } catch {
                  setStorageError("Demo change could not be saved");
                }
              }}
            >
              <WifiOff size={17} />
              {s.gateways[0]?.reachable
                ? "Simulate primary gateway failure"
                : "Restore primary gateway"}
            </button>
            <button
              className="button"
              onClick={async () => {
                const id = makeId();
                try {
                  await commitDemo(
                    event(
                      {
                        ...s,
                        alerts: [
                          {
                            id,
                            title: "New assistance request",
                            category: "Assistance",
                            location: "East courtyard · campus",
                            nodeId: "n3",
                            status: "new",
                            createdAt: Date.now(),
                          },
                          ...s.alerts,
                        ],
                        operations: [
                          {
                            id,
                            origin: "n3",
                            kind: "SOS",
                            status: "queued",
                            createdAt: Date.now(),
                            hops: 0,
                          },
                          ...s.operations,
                        ],
                      },
                      "SOS saved locally",
                      "Waiting for delivery through the available gateway",
                      "warning",
                    ),
                  );
                  setModal(null);
                } catch {
                  setStorageError("Demo event could not be saved");
                }
              }}
            >
              <Radio size={17} />
              Simulate incoming SOS
            </button>
            <button
              className="button"
              onClick={() => {
                void act({ type: "RETRY_SYNC" });
                setModal(null);
              }}
            >
              <RefreshCw size={17} />
              Synchronize pending operations
            </button>
          </div>
          <details>
            <summary>Reset demo workspace</summary>
            <p className="hint">
              Replaces this browser’s demo history and actions with the original
              scenario. Live data is separate.
            </p>
            <button
              className="button"
              onClick={async () => {
                try {
                  await commitDemo(demoSnapshot());
                  setModal(null);
                } catch {
                  setStorageError("Could not reset demo");
                }
              }}
            >
              Reset demo data
            </button>
          </details>
        </Dialog>
      )}
      {modal === "help" && (
        <Dialog title="How OFFGRID works" close={() => setModal(null)}>
          <div className="help-step">
            <Database />
            <div>
              <h3>Save locally</h3>
              <p>
                User actions are stored on their device before delivery is
                attempted.
              </p>
            </div>
          </div>
          <div className="help-step">
            <Network />
            <div>
              <h3>Relay when reachable</h3>
              <p>
                Participating nodes exchange and forward packets over supported
                local transports.
              </p>
            </div>
          </div>
          <div className="help-step">
            <Cloud />
            <div>
              <h3>Synchronize with evidence</h3>
              <p>
                A gateway uploads operations. The backend deduplicates them,
                preserves conflicts, and acknowledges commits.
              </p>
            </div>
          </div>
          <p className="hint">
            This dashboard observes the network. Demo mode uses illustrative
            data; live mode requires the documented dashboard backend endpoints.
          </p>
        </Dialog>
      )}
    </div>
  );
}
function Flask() {
  return <Zap size={17} />;
}
function Metric({
  title,
  value,
  suffix,
  icon,
  detail,
  tone,
}: {
  title: string;
  value: string;
  suffix?: string;
  icon: React.ReactNode;
  detail: string;
  tone: string;
}) {
  return (
    <section className="metric">
      <div className="row">
        <span>{title}</span>
        <span className={`metric-icon ${tone}`}>{icon}</span>
      </div>
      <div className="metric-value">
        {value}
        <span>{suffix}</span>
      </div>
      <small>
        <i className={tone} />
        {detail}
      </small>
    </section>
  );
}
function PanelTitle({
  title,
  subtitle,
  action,
  children,
}: {
  title: string;
  subtitle?: string;
  action?: () => void;
  children?: React.ReactNode;
}) {
  return (
    <div className="panel-title">
      <div>
        <h2>{title}</h2>
        {subtitle && <p>{subtitle}</p>}
      </div>
      {children}
      {action && (
        <button
          className="icon-button"
          aria-label={`Open ${title}`}
          onClick={action}
        >
          <ArrowUpRight size={18} />
        </button>
      )}
    </div>
  );
}
function ActivityList({ s, count }: { s: Snapshot; count: number }) {
  return (
    <div className="activity-list">
      {s.events.slice(0, count).map((e) => (
        <div className="activity-item" key={e.id}>
          <span className={`activity-icon ${e.kind}`}>
            {e.kind === "success" ? (
              <Check size={15} />
            ) : e.kind === "warning" ? (
              <TriangleAlert size={15} />
            ) : (
              <Activity size={15} />
            )}
          </span>
          <div>
            <strong>{e.title}</strong>
            <p>{e.detail}</p>
          </div>
          <time>{time(e.time)}</time>
        </div>
      ))}
      {!s.events.length && <div className="empty">No events reported.</div>}
    </div>
  );
}
function Toolbar({
  query,
  setQuery,
  filter,
  setFilter,
  options,
  placeholder,
}: {
  query: string;
  setQuery: (s: string) => void;
  filter: string;
  setFilter: (s: string) => void;
  options: string[];
  placeholder: string;
}) {
  return (
    <div className="toolbar">
      <label className="search">
        <Search size={16} />
        <input
          aria-label={placeholder}
          placeholder={placeholder}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </label>
      <select
        aria-label="Filter by status"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
      >
        {options.map((o) => (
          <option key={o} value={o}>
            {o === "all" ? "All statuses" : o[0].toUpperCase() + o.slice(1)}
          </option>
        ))}
      </select>
    </div>
  );
}
function Dialog({
  title,
  close,
  children,
}: {
  title: string;
  close: () => void;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement;
    ref.current?.showModal();
    return () => {
      previous?.focus();
    };
  }, []);
  return (
    <dialog
      ref={ref}
      onCancel={(e) => {
        e.preventDefault();
        close();
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) close();
      }}
      aria-label={title}
    >
      <div className="dialog-inner">
        <div className="panel-title">
          <h2>{title}</h2>
          <button
            className="icon-button"
            aria-label="Close dialog"
            onClick={close}
          >
            <X size={20} />
          </button>
        </div>
        {children}
      </div>
    </dialog>
  );
}
function Settings({
  current,
  mode,
  error,
  connect,
  demo,
}: {
  current: Connection;
  mode: string;
  error: string;
  connect: (c: Connection) => void;
  demo: () => void;
}) {
  const [c, setC] = useState(current);
  return (
    <>
      <div className="notice demo">
        <Zap size={16} />
        <span>
          Current source:{" "}
          <strong>{mode === "demo" ? "Demo workspace" : "Live backend"}</strong>
        </span>
      </div>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          connect(c);
        }}
      >
        <label>
          Backend API base URL
          <input
            required
            type="url"
            placeholder="https://your-backend.example/api/v1"
            value={c.apiUrl}
            onChange={(e) => setC({ ...c, apiUrl: e.target.value })}
          />
        </label>
        <label>
          WebSocket URL <small>(optional)</small>
          <input
            type="url"
            placeholder="wss://your-backend.example/ws"
            value={c.wsUrl}
            onChange={(e) => setC({ ...c, wsUrl: e.target.value })}
          />
        </label>
        <p className="hint">
          The backend must implement the dashboard snapshot and action contract.
          REST refreshes every 15 seconds; WebSocket messages trigger an earlier
          refresh. Credentials use your backend session cookie.
        </p>
        {error && (
          <p role="alert" className="error-text">
            {error}
          </p>
        )}
        <div className="row">
          <button type="button" className="button" onClick={demo}>
            Use demo data
          </button>
          <button className="button primary">
            <Signal size={16} />
            Connect backend
          </button>
        </div>
      </form>
    </>
  );
}
