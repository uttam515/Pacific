import { randomUUID } from "node:crypto";
import type pg from "pg";
import type { Actor } from "./database.js";
import { ApiError, canonical, validate, type Operation } from "./contract.js";
import type { Engine } from "./engine.js";

export const transitions: Record<string, string[]> = {
  RECEIVED: ["ACKNOWLEDGED", "CANCELLED"],
  ACKNOWLEDGED: ["RESPONDER_ASSIGNED", "RESOLVED", "CANCELLED"],
  AUTHORITY_NOTIFIED: ["RESPONDER_ASSIGNED", "RESOLVED", "CANCELLED"],
  RESPONDER_ASSIGNED: ["RESPONDER_EN_ROUTE", "RESOLVED", "CANCELLED"],
  RESPONDER_EN_ROUTE: ["RESOLVED", "CANCELLED"],
  RESOLVED: [],
  CANCELLED: [],
};
const invalid = (message: string): never => {
  throw new ApiError(422, "VALIDATION_ERROR", message);
};
export function object(raw: unknown, keys: string[]): Record<string, any> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw))
    return invalid("JSON object required");
  const b = raw as Record<string, any>;
  if (Object.keys(b).some((k) => !keys.includes(k)))
    return invalid("Unexpected field");
  return b;
}
export function textField(v: unknown, max = 200): string {
  if (
    typeof v !== "string" ||
    !v.trim() ||
    v.length > max ||
    /[\x00-\x08\x0b-\x1f]/.test(v)
  )
    return invalid("Invalid text");
  return v.trim();
}
export function integer(v: unknown, max = 1000000): number {
  if (!Number.isSafeInteger(v) || (v as number) < 0 || (v as number) > max)
    return invalid("Invalid integer");
  return v as number;
}
function operator(a: Actor) {
  if (a.role !== "operator")
    throw new ApiError(403, "FORBIDDEN", "Operator required");
}
export function gateway(a: Actor) {
  if (a.role !== "gateway")
    throw new ApiError(
      403,
      "FORBIDDEN",
      "Explicitly provisioned gateway required",
    );
}
export async function incidentEvent(
  c: pg.PoolClient,
  a: Actor,
  id: string,
  kind: string,
  details: unknown = {},
) {
  await c.query("INSERT INTO incident_events VALUES($1,$2,$3,$4,$5,$6,$7)", [
    randomUUID(),
    id,
    a.group_id,
    a.node_id,
    kind,
    Date.now(),
    details,
  ]);
}
export async function projectSOS(
  c: pg.PoolClient,
  a: Actor,
  op: Operation,
  time: number,
) {
  if (op.entityType !== "SOS") return;
  const r = await c.query(
    "INSERT INTO incidents(incident_id,group_id,operation_id,origin_node_id,first_gateway_id,received_at) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING RETURNING incident_id",
    [
      op.entityId,
      a.group_id,
      op.operationId,
      op.originNodeId,
      a.role === "gateway" ? a.node_id : null,
      time,
    ],
  );
  if (r.rowCount) {
    await c.query(
      "INSERT INTO incident_events VALUES($1,$2,$3,$4,'SOS_CREATION_REPORTED',$5,$6)",
      [
        randomUUID(),
        op.entityId,
        a.group_id,
        op.originNodeId,
        op.timestamp,
        {
          operationId: op.operationId,
          source: "origin timestamp in accepted operation",
        },
      ],
    );
    await incidentEvent(c, a, op.entityId, "SERVER_RECEIVED", {
      operationId: op.operationId,
      eventTimestamp: op.timestamp,
      source: "backend transaction",
    });
  }
  if (a.role === "gateway") {
    const upload = await c.query(
      "INSERT INTO gateway_uploads(node_id,operation_id,first_seen,last_seen) VALUES($1,$2,$3,$3) ON CONFLICT(node_id,operation_id) DO UPDATE SET last_seen=excluded.last_seen,attempts=gateway_uploads.attempts+1 RETURNING attempts",
      [a.node_id, op.operationId, time],
    );
    if (upload.rows[0].attempts === 1) {
      await incidentEvent(c, a, op.entityId, "GATEWAY_UPLOAD_ACCEPTED", {
        operationId: op.operationId,
        firstIncidentCommit: !!r.rowCount,
      });
    }
  }
}
export class Emergency {
  constructor(private engine: Engine) {}
  async ready(a: Actor) {
    gateway(a);
    await this.engine.db.query("SELECT 1 FROM incidents LIMIT 1");
    return {
      schemaVersion: 1,
      nodeId: a.node_id,
      serverNodeId: this.engine.serverNodeId,
      ready: true,
      timestamp: Date.now(),
    };
  }
  async heartbeat(a: Actor, raw: unknown) {
    gateway(a);
    const b = object(raw, [
      "schemaVersion",
      "nodeId",
      "reportedAt",
      "meshConnected",
      "internetReachable",
      "pendingUploads",
      "failedUploads",
    ]);
    if (
      b.schemaVersion !== 1 ||
      b.nodeId !== a.node_id ||
      typeof b.meshConnected !== "boolean" ||
      (b.internetReachable !== null && typeof b.internetReachable !== "boolean")
    )
      return invalid("Invalid heartbeat");
    integer(b.reportedAt, Number.MAX_SAFE_INTEGER);
    integer(b.pendingUploads);
    integer(b.failedUploads);
    return this.engine.tx(async (c) => {
      const old = (
        await c.query(
          "SELECT body,observed_at FROM gateway_health WHERE node_id=$1",
          [a.node_id],
        )
      ).rows[0];
      if (
        !old ||
        Date.now() - Number(old.observed_at) >= 45000 ||
        canonical({ ...old.body, reportedAt: 0 }) !==
          canonical({ ...b, reportedAt: 0 })
      ) {
        await c.query("INSERT INTO gateway_events VALUES($1,$2,$3,$4,$5,$6)", [
          randomUUID(),
          a.group_id,
          a.node_id,
          !old
            ? "GATEWAY_FIRST_REPORT"
            : Date.now() - Number(old.observed_at) >= 45000
              ? "GATEWAY_RECONNECTED"
              : "GATEWAY_STATE_REPORTED",
          Date.now(),
          b,
        ]);
      }
      await c.query(
        "INSERT INTO gateway_health VALUES($1,$2,$3,$4,$5) ON CONFLICT(node_id) DO UPDATE SET observed_at=excluded.observed_at,reported_at=excluded.reported_at,body=excluded.body",
        [a.node_id, a.group_id, Date.now(), b.reportedAt, b],
      );
      return { schemaVersion: 1, accepted: true };
    });
  }
  async observation(a: Actor, raw: unknown) {
    gateway(a);
    const b = object(raw, [
      "schemaVersion",
      "operationId",
      "packetId",
      "hopCount",
      "receivedAt",
    ]);
    if (b.schemaVersion !== 1) return invalid("schemaVersion must be 1");
    validate("UUID", b.operationId);
    validate("UUID", b.packetId);
    integer(b.hopCount, 32);
    integer(b.receivedAt, Number.MAX_SAFE_INTEGER);
    return this.engine.tx(async (c) => {
      const r = await c.query(
        "SELECT i.incident_id FROM incidents i JOIN gateway_uploads g USING(operation_id) WHERE g.node_id=$1 AND i.operation_id=$2 AND i.group_id=$3",
        [a.node_id, b.operationId, a.group_id],
      );
      if (!r.rowCount)
        throw new ApiError(
          404,
          "ENTITY_NOT_FOUND",
          "Committed gateway upload not found",
        );
      const updated = await c.query(
        "UPDATE gateway_uploads SET observation=$3 WHERE node_id=$1 AND operation_id=$2 AND observation IS NULL RETURNING node_id",
        [a.node_id, b.operationId, b],
      );
      if (updated.rowCount)
        await incidentEvent(
          c,
          a,
          r.rows[0].incident_id,
          "GATEWAY_RECEIPT_REPORTED",
          { ...b, source: "gateway report; not independently verified" },
        );
      return { schemaVersion: 1, accepted: true, duplicate: !updated.rowCount };
    });
  }
  async snapshot(a: Actor) {
    operator(a);
    const c = await this.engine.db.connect();
    try {
      await c.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
      const incidents = (
        await c.query(
          `SELECT i.*,o.operation FROM incidents i JOIN operations o USING(operation_id) WHERE i.group_id=$1 ORDER BY received_at DESC,incident_id DESC LIMIT 501`,
          [a.group_id],
        )
      ).rows;
      const authorities = (
        await c.query(
          "SELECT * FROM authorities WHERE group_id=$1 ORDER BY name",
          [a.group_id],
        )
      ).rows;
      const responders = (
        await c.query(
          "SELECT * FROM responders WHERE group_id=$1 ORDER BY name",
          [a.group_id],
        )
      ).rows;
      const gateways = (
        await c.query(
          `SELECT n.node_id,n.display_name,h.observed_at,h.reported_at,h.body,
     (SELECT count(*)::integer FROM gateway_uploads g WHERE g.node_id=n.node_id) AS successful_uploads,
     (SELECT max(first_seen) FROM gateway_uploads g WHERE g.node_id=n.node_id) AS last_successful_upload
     FROM nodes n LEFT JOIN gateway_health h USING(node_id) WHERE n.group_id=$1 AND n.role='gateway' ORDER BY n.display_name`,
          [a.group_id],
        )
      ).rows.map((g) => ({
        ...g,
        backendConnected:
          !!g.observed_at && Date.now() - Number(g.observed_at) < 45000,
      }));
      const events = (
        await c.query(
          `SELECT event_id,incident_id,actor_id,kind,occurred_at,details FROM incident_events WHERE group_id=$1 UNION ALL SELECT event_id,NULL AS incident_id,node_id AS actor_id,kind,occurred_at,details FROM gateway_events WHERE group_id=$1 ORDER BY occurred_at DESC,event_id LIMIT 200`,
          [a.group_id],
        )
      ).rows;
      const counts = (
        await c.query(
          "SELECT status,count(*)::integer AS count FROM incidents WHERE group_id=$1 GROUP BY status",
          [a.group_id],
        )
      ).rows;
      await c.query("COMMIT");
      return {
        schemaVersion: 1,
        observedAt: Date.now(),
        incidents: incidents.slice(0, 500),
        nextCursor:
          incidents.length > 500
            ? `${incidents[499].received_at}_${incidents[499].incident_id}`
            : null,
        authorities,
        responders,
        gateways,
        events,
        counts,
        incidentLimit: 500,
      };
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    } finally {
      c.release();
    }
  }
  async list(a: Actor, cursor: string, limit: number) {
    operator(a);
    const [stamp, id, ...extra] = cursor.split("_");
    if (
      extra.length ||
      !/^\d{1,16}$/.test(stamp || "") ||
      !Number.isSafeInteger(Number(stamp))
    )
      return invalid("Invalid incident cursor");
    validate("UUID", id);
    integer(limit, 500);
    if (limit < 1) return invalid("limit must be 1..500");
    const rows = (
      await this.engine.db.query(
        `SELECT i.*,o.operation FROM incidents i JOIN operations o USING(operation_id) WHERE i.group_id=$1 AND (i.received_at,i.incident_id)<($2::bigint,$3::uuid) ORDER BY i.received_at DESC,i.incident_id DESC LIMIT $4`,
        [a.group_id, stamp, id, limit + 1],
      )
    ).rows;
    const incidents = rows.slice(0, limit),
      last = incidents.at(-1);
    return {
      schemaVersion: 1,
      incidents,
      nextCursor:
        rows.length > limit ? `${last.received_at}_${last.incident_id}` : null,
    };
  }
  async detail(a: Actor, id: string) {
    operator(a);
    validate("UUID", id);
    const incident = (
      await this.engine.db.query(
        "SELECT i.*,o.operation FROM incidents i JOIN operations o USING(operation_id) WHERE incident_id=$1 AND i.group_id=$2",
        [id, a.group_id],
      )
    ).rows[0];
    if (!incident)
      throw new ApiError(404, "ENTITY_NOT_FOUND", "Incident not found");
    const events = (
      await this.engine.db.query(
        "SELECT * FROM incident_events WHERE incident_id=$1 ORDER BY occurred_at,event_id",
        [id],
      )
    ).rows;
    const notifications = (
      await this.engine.db.query(
        "SELECT * FROM authority_notifications WHERE incident_id=$1 ORDER BY submitted_at",
        [id],
      )
    ).rows;
    const uploads = (
      await this.engine.db.query(
        "SELECT * FROM gateway_uploads WHERE operation_id=$1 ORDER BY first_seen",
        [incident.operation_id],
      )
    ).rows;
    return { schemaVersion: 1, incident, events, notifications, uploads };
  }
  async command(a: Actor, raw: unknown) {
    operator(a);
    const b = object(raw, [
      "schemaVersion",
      "commandId",
      "action",
      "subjectId",
      "expectedRevision",
      "data",
    ]);
    if (b.schemaVersion !== 1) return invalid("schemaVersion must be 1");
    validate("UUID", b.commandId);
    validate("UUID", b.subjectId);
    integer(b.expectedRevision);
    textField(b.action, 40);
    return this.engine.tx(async (c) => {
      const previous = (
        await c.query("SELECT * FROM emergency_commands WHERE command_id=$1", [
          b.commandId,
        ])
      ).rows[0];
      if (previous) {
        if (
          previous.actor_id !== a.node_id ||
          canonical(previous.request) !== canonical(b)
        )
          throw new ApiError(409, "ID_REUSE", "Command ID reused");
        return { ...previous.response, duplicate: true };
      }
      let revision: number;
      if (b.action === "SAVE_AUTHORITY" || b.action === "SAVE_RESPONDER") {
        const authority = b.action === "SAVE_AUTHORITY";
        const d = object(
          b.data,
          authority
            ? ["name", "category", "contact", "active"]
            : ["name", "authorityId", "contact", "active"],
        );
        textField(d.name);
        textField(d.contact, 500);
        if (typeof d.active !== "boolean")
          return invalid("active boolean required");
        if (
          authority &&
          !["POLICE", "AMBULANCE", "FIRE_RESCUE", "DISASTER", "OTHER"].includes(
            d.category,
          )
        )
          return invalid("Invalid authority category");
        if (!authority) {
          validate("UUID", d.authorityId);
          if (
            !(
              await c.query(
                "SELECT 1 FROM authorities WHERE authority_id=$1 AND group_id=$2 AND active",
                [d.authorityId, a.group_id],
              )
            ).rowCount
          )
            throw new ApiError(
              422,
              "VALIDATION_ERROR",
              "Active authority required",
            );
        }
        const table = authority ? "authorities" : "responders",
          key = authority ? "authority_id" : "responder_id";
        const old = (
          await c.query(`SELECT * FROM ${table} WHERE ${key}=$1`, [b.subjectId])
        ).rows[0];
        if (old && old.group_id !== a.group_id)
          throw new ApiError(403, "FORBIDDEN", "Organization mismatch");
        if ((old?.revision || 0) !== b.expectedRevision)
          throw new ApiError(409, "STALE_RESOLUTION", "Refresh revision");
        revision = b.expectedRevision + 1;
        if (authority)
          await c.query(
            "INSERT INTO authorities VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(authority_id) DO UPDATE SET name=excluded.name,category=excluded.category,contact=excluded.contact,active=excluded.active,revision=excluded.revision",
            [
              b.subjectId,
              a.group_id,
              d.name,
              d.category,
              d.contact,
              d.active,
              revision,
            ],
          );
        else
          await c.query(
            "INSERT INTO responders VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(responder_id) DO UPDATE SET authority_id=excluded.authority_id,name=excluded.name,contact=excluded.contact,active=excluded.active,revision=excluded.revision",
            [
              b.subjectId,
              a.group_id,
              d.authorityId,
              d.name,
              d.contact,
              d.active,
              revision,
            ],
          );
      } else {
        const i = (
          await c.query(
            "SELECT * FROM incidents WHERE incident_id=$1 AND group_id=$2 FOR UPDATE",
            [b.subjectId, a.group_id],
          )
        ).rows[0];
        if (!i)
          throw new ApiError(404, "ENTITY_NOT_FOUND", "Incident not found");
        if (i.revision !== b.expectedRevision)
          throw new ApiError(
            409,
            "STALE_RESOLUTION",
            "Refresh incident revision",
          );
        if (["RESOLVED", "CANCELLED"].includes(i.status))
          return invalid("Incident is closed");
        const d = {
          ...object(
            b.data,
            b.action === "SET_STATUS"
              ? ["status", "note"]
              : b.action === "ASSIGN_AUTHORITY"
                ? ["authorityId"]
                : b.action === "ASSIGN_RESPONDER"
                  ? ["responderId"]
                  : b.action === "SANDBOX_ACK"
                    ? ["notificationId"]
                    : [],
          ),
        };
        let kind = b.action;
        if (b.action === "SET_STATUS") {
          textField(d.note, 1000);
          if (
            !transitions[i.status]?.includes(d.status) ||
            d.status === "RESPONDER_ASSIGNED"
          )
            return invalid(
              "Invalid status transition; assign a responder through its command",
            );
          i.status = d.status;
        } else if (b.action === "ASSIGN_AUTHORITY") {
          validate("UUID", d.authorityId);
          if (
            !(
              await c.query(
                "SELECT 1 FROM authorities WHERE authority_id=$1 AND group_id=$2 AND active",
                [d.authorityId, a.group_id],
              )
            ).rowCount
          )
            return invalid("Active authority required");
          if (i.responder_id)
            return invalid(
              "Cannot change authority after responder assignment",
            );
          i.authority_id = d.authorityId;
        } else if (b.action === "ASSIGN_RESPONDER") {
          validate("UUID", d.responderId);
          if (!transitions[i.status]?.includes("RESPONDER_ASSIGNED"))
            return invalid("Acknowledge before assignment");
          const r = (
            await c.query(
              "SELECT * FROM responders WHERE responder_id=$1 AND group_id=$2 AND active",
              [d.responderId, a.group_id],
            )
          ).rows[0];
          if (!r || r.authority_id !== i.authority_id)
            return invalid("Responder must belong to assigned authority");
          i.responder_id = d.responderId;
          i.status = "RESPONDER_ASSIGNED";
        } else if (b.action === "SANDBOX_NOTIFY") {
          if (!i.authority_id || i.status === "RECEIVED")
            return invalid("Acknowledge and assign an authority first");
          if (
            !(
              await c.query(
                "SELECT 1 FROM authorities WHERE authority_id=$1 AND active",
                [i.authority_id],
              )
            ).rowCount
          )
            return invalid("Authority inactive");
          const notificationId = randomUUID();
          await c.query(
            "INSERT INTO authority_notifications VALUES($1,$2,$3,$4,'SANDBOX','SANDBOX_SUBMITTED',$5,NULL)",
            [
              notificationId,
              i.incident_id,
              i.authority_id,
              a.group_id,
              Date.now(),
            ],
          );
          d.notificationId = notificationId;
          d.mode = "SANDBOX";
          kind = "SANDBOX_NOTIFICATION_SUBMITTED";
          // This is not a real authority delivery and must never set AUTHORITY_NOTIFIED.
        } else if (b.action === "SANDBOX_ACK") {
          validate("UUID", d.notificationId);
          if (
            !(
              await c.query(
                "UPDATE authority_notifications SET status='SANDBOX_ACKNOWLEDGED',acknowledged_at=$3 WHERE notification_id=$1 AND incident_id=$2 AND status='SANDBOX_SUBMITTED' RETURNING notification_id",
                [d.notificationId, i.incident_id, Date.now()],
              )
            ).rowCount
          )
            return invalid("Pending sandbox notification required");
          kind = "SANDBOX_AUTHORITY_ACKNOWLEDGED";
        } else return invalid("Unknown command");
        revision = i.revision + 1;
        await c.query(
          "UPDATE incidents SET status=$2,authority_id=$3,responder_id=$4,revision=$5 WHERE incident_id=$1",
          [i.incident_id, i.status, i.authority_id, i.responder_id, revision],
        );
        await incidentEvent(c, a, i.incident_id, kind, {
          ...d,
          status: i.status,
          revision,
          commandId: b.commandId,
        });
      }
      const response = {
        schemaVersion: 1,
        commandId: b.commandId,
        subjectId: b.subjectId,
        revision,
        duplicate: false,
      };
      await c.query(
        "INSERT INTO emergency_commands VALUES($1,$2,$3,$4,$5,$6)",
        [b.commandId, a.node_id, a.group_id, b, response, Date.now()],
      );
      await c.query(
        "INSERT INTO emergency_audit VALUES($1,$2,$3,$4,$5,$6,$7)",
        [
          randomUUID(),
          a.group_id,
          a.node_id,
          b.action,
          b.subjectId,
          Date.now(),
          { commandId: b.commandId, revision },
        ],
      );
      return response;
    });
  }
}
