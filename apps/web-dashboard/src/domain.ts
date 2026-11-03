export function makeId(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  const h = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
export type Node = {
  id: string;
  name: string;
  platform: string;
  role: "client" | "relay" | "gateway";
  status: "active" | "unreachable";
  lastSeen: number;
  battery?: number;
};
export type Operation = {
  id: string;
  origin: string;
  kind: string;
  status: "queued" | "relayed" | "synced" | "conflict";
  createdAt: number;
  hops: number;
  conflictId?: string;
};
export type Alert = {
  id: string;
  title: string;
  category: string;
  location: string;
  nodeId: string;
  status: "new" | "acknowledged" | "resolved";
  createdAt: number;
};
export type Conflict = {
  id: string;
  entity: string;
  baseVersion: number;
  left: string;
  right: string;
  leftNode: string;
  rightNode: string;
  resolved?: "left" | "right";
};
export type Gateway = {
  nodeId: string;
  reachable: boolean;
  selected: boolean;
  latency: number;
};
export type Event = {
  id: string;
  title: string;
  detail: string;
  time: number;
  kind: "info" | "success" | "warning";
};
export type Snapshot = {
  schemaVersion: 1;
  observedAt: number;
  nodes: Node[];
  links: { from: string; to: string }[];
  operations: Operation[];
  alerts: Alert[];
  conflicts: Conflict[];
  gateways: Gateway[];
  events: Event[];
};
export type Action = {
  operationId: string;
  type:
    | "ACK_ALERT"
    | "RESOLVE_ALERT"
    | "RESOLVE_CONFLICT"
    | "RETRY_SYNC"
    | "CREATE_ANNOUNCEMENT";
  entityId?: string;
  choice?: "left" | "right";
  text?: string;
  createdAt: number;
};
export const emptySnapshot = (): Snapshot => ({
  schemaVersion: 1,
  observedAt: 0,
  nodes: [],
  links: [],
  operations: [],
  alerts: [],
  conflicts: [],
  gateways: [],
  events: [],
});
export function demoSnapshot(now = Date.now()): Snapshot {
  const nodes: Node[] = [
    {
      id: "n1",
      name: "Command station",
      platform: "Windows",
      role: "gateway",
      status: "active",
      lastSeen: now,
      battery: 96,
    },
    {
      id: "n2",
      name: "Library relay",
      platform: "macOS",
      role: "relay",
      status: "active",
      lastSeen: now,
      battery: 84,
    },
    {
      id: "n3",
      name: "Field team A",
      platform: "Android",
      role: "client",
      status: "active",
      lastSeen: now,
      battery: 68,
    },
    {
      id: "n4",
      name: "North gate",
      platform: "iOS",
      role: "client",
      status: "active",
      lastSeen: now,
      battery: 73,
    },
    {
      id: "n5",
      name: "Backup gateway",
      platform: "Windows",
      role: "gateway",
      status: "active",
      lastSeen: now,
      battery: 92,
    },
    {
      id: "n6",
      name: "Field team B",
      platform: "iOS",
      role: "client",
      status: "unreachable",
      lastSeen: now - 240000,
      battery: 32,
    },
  ];
  return {
    schemaVersion: 1,
    observedAt: now,
    nodes,
    links: [
      { from: "n3", to: "n2" },
      { from: "n4", to: "n2" },
      { from: "n2", to: "n1" },
      { from: "n2", to: "n5" },
    ],
    gateways: [
      { nodeId: "n1", reachable: true, selected: true, latency: 28 },
      { nodeId: "n5", reachable: true, selected: false, latency: 46 },
    ],
    operations: Array.from({ length: 24 }, (_, i) => ({
      id: `op-${String(i + 1).padStart(3, "0")}`,
      origin: nodes[i % 5].id,
      kind: i % 4 === 0 ? "SOS" : i % 3 === 0 ? "Announcement" : "Message",
      status:
        i < 19
          ? "synced"
          : i < 22
            ? "queued"
            : i === 22
              ? "relayed"
              : "conflict",
      createdAt: now - (24 - i) * 45000,
      hops: i % 3,
      conflictId: i === 23 ? "conflict-01" : undefined,
    })),
    alerts: [
      {
        id: "sos-001",
        title: "Assistance requested at north gate",
        category: "Assistance",
        location: "North gate · campus",
        nodeId: "n4",
        status: "new",
        createdAt: now - 120000,
      },
      {
        id: "sos-002",
        title: "Water supply needed",
        category: "Supplies",
        location: "Library · ground floor",
        nodeId: "n3",
        status: "acknowledged",
        createdAt: now - 480000,
      },
    ],
    conflicts: [
      {
        id: "conflict-01",
        entity: "Campus shelter announcement",
        baseVersion: 3,
        left: "Shelter is open in the library until 18:00.",
        right: "Shelter has moved to the sports hall.",
        leftNode: "Field team A",
        rightNode: "North gate",
      },
    ],
    events: [
      {
        id: "e1",
        title: "SOS received",
        detail: "North gate · awaiting operator acknowledgment",
        time: now - 120000,
        kind: "warning",
      },
      {
        id: "e2",
        title: "Operations synchronized",
        detail: "Command station committed a batch of 8 operations",
        time: now - 180000,
        kind: "success",
      },
      {
        id: "e3",
        title: "Peer no longer reachable",
        detail: "Field team B · last known state retained",
        time: now - 240000,
        kind: "warning",
      },
      {
        id: "e4",
        title: "Backup gateway available",
        detail: "Alternative route through Library relay",
        time: now - 360000,
        kind: "info",
      },
    ],
  };
}
export function event(
  s: Snapshot,
  title: string,
  detail: string,
  kind: Event["kind"] = "info",
): Snapshot {
  return {
    ...s,
    observedAt: Date.now(),
    events: [
      { id: makeId(), title, detail, kind, time: Date.now() },
      ...s.events,
    ].slice(0, 100),
  };
}
export function applyDemoAction(s: Snapshot, a: Action): Snapshot {
  if (a.type === "ACK_ALERT" || a.type === "RESOLVE_ALERT")
    return event(
      {
        ...s,
        alerts: s.alerts.map((x) =>
          x.id === a.entityId
            ? {
                ...x,
                status: a.type === "ACK_ALERT" ? "acknowledged" : "resolved",
              }
            : x,
        ),
      },
      a.type === "ACK_ALERT" ? "Alert acknowledged" : "Alert resolved",
      `${a.entityId} · demo operator`,
      "success",
    );
  if (a.type === "RESOLVE_CONFLICT" && a.choice)
    return event(
      {
        ...s,
        conflicts: s.conflicts.map((x) =>
          x.id === a.entityId ? { ...x, resolved: a.choice } : x,
        ),
        operations: s.operations.map((x) =>
          x.conflictId === a.entityId ? { ...x, status: "synced" } : x,
        ),
      },
      "Conflict resolved",
      "Selected version retained; original versions remain in history",
      "success",
    );
  if (a.type === "RETRY_SYNC") {
    if (!s.gateways.some((x) => x.selected && x.reachable))
      return event(
        s,
        "Sync deferred",
        "No reachable gateway. Operations remain queued.",
        "warning",
      );
    return event(
      {
        ...s,
        operations: s.operations.map((x) =>
          x.status === "queued" || x.status === "relayed"
            ? { ...x, status: "synced" }
            : x,
        ),
      },
      "Pending operations synchronized",
      "Demo server acknowledgment received",
      "success",
    );
  }
  if (a.type === "CREATE_ANNOUNCEMENT")
    return event(
      {
        ...s,
        operations: [
          {
            id: a.operationId,
            origin: "n1",
            kind: "Announcement",
            status: "queued",
            createdAt: a.createdAt,
            hops: 0,
          },
          ...s.operations,
        ],
      },
      "Announcement saved",
      a.text || "",
      "success",
    );
  return s;
}
export function toggleDemoGateway(s: Snapshot): Snapshot {
  const failed = s.gateways[0].reachable;
  const gateways = s.gateways.map((g, i) => ({
    ...g,
    reachable: i === 0 ? !failed : g.reachable,
    selected: i === (failed ? 1 : 0),
  }));
  return event(
    {
      ...s,
      gateways,
      nodes: s.nodes.map((n) =>
        n.id === "n1"
          ? {
              ...n,
              status: failed ? "unreachable" : "active",
              lastSeen: Date.now(),
            }
          : n,
      ),
    },
    failed ? "Gateway failover simulated" : "Primary gateway restored",
    failed
      ? "Backup gateway selected. Local operations are preserved."
      : "Command station selected.",
    "warning",
  );
}
export function isSnapshot(v: unknown): v is Snapshot {
  if (!v || typeof v !== "object") return false;
  const s = v as Snapshot;
  const obj = (x: unknown) => !!x && typeof x === "object";
  const str = (x: unknown) => typeof x === "string";
  const num = (x: unknown) => typeof x === "number" && Number.isFinite(x);
  return (
    s.schemaVersion === 1 &&
    num(s.observedAt) &&
    Array.isArray(s.nodes) &&
    s.nodes.every(
      (n) =>
        obj(n) &&
        str(n.id) &&
        str(n.name) &&
        str(n.platform) &&
        ["client", "relay", "gateway"].includes(n.role) &&
        ["active", "unreachable"].includes(n.status) &&
        num(n.lastSeen),
    ) &&
    Array.isArray(s.links) &&
    s.links.every((l) => obj(l) && str(l.from) && str(l.to)) &&
    Array.isArray(s.operations) &&
    s.operations.every(
      (o) =>
        obj(o) &&
        str(o.id) &&
        str(o.origin) &&
        str(o.kind) &&
        ["queued", "relayed", "synced", "conflict"].includes(o.status) &&
        num(o.createdAt) &&
        num(o.hops),
    ) &&
    Array.isArray(s.alerts) &&
    s.alerts.every(
      (a) =>
        obj(a) &&
        str(a.id) &&
        str(a.title) &&
        str(a.category) &&
        str(a.location) &&
        str(a.nodeId) &&
        num(a.createdAt) &&
        ["new", "acknowledged", "resolved"].includes(a.status),
    ) &&
    Array.isArray(s.conflicts) &&
    s.conflicts.every(
      (c) =>
        obj(c) &&
        str(c.id) &&
        str(c.entity) &&
        str(c.left) &&
        str(c.right) &&
        str(c.leftNode) &&
        str(c.rightNode) &&
        num(c.baseVersion) &&
        (!c.resolved || ["left", "right"].includes(c.resolved)),
    ) &&
    Array.isArray(s.gateways) &&
    s.gateways.every(
      (g) =>
        obj(g) &&
        str(g.nodeId) &&
        typeof g.reachable === "boolean" &&
        typeof g.selected === "boolean" &&
        num(g.latency),
    ) &&
    Array.isArray(s.events) &&
    s.events.every(
      (e) =>
        obj(e) &&
        str(e.id) &&
        str(e.title) &&
        str(e.detail) &&
        num(e.time) &&
        ["info", "success", "warning"].includes(e.kind),
    )
  );
}
export const nodeName = (s: Snapshot, id: string) =>
  s.nodes.find((n) => n.id === id)?.name || id;
