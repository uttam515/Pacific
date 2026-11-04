import pg from "pg";
import { randomUUID } from "node:crypto";
import type { ContractV1 } from "@offgrid/shared-types";
import {
  ApiError,
  canonical,
  validate,
  type Operation,
  type PushResult,
  type Ack,
  type Conflict,
} from "./contract.js";
import type { Actor } from "./database.js";
import { projectSOS } from "./emergency.js";
type Client = pg.PoolClient;
const now = () => Date.now();
const reject = (
  operationId: string,
  code: string,
  message: string,
  retryable = false,
) =>
  ({
    operationId,
    outcome: "REJECTED",
    error: { code, message, retryable },
  }) as PushResult;
export class Engine {
  onCommit?: () => void;
  constructor(
    public db: pg.Pool,
    public serverNodeId = "00000000-0000-4000-8000-000000000003",
  ) {}
  async init() {
    await this.db.query(
      "INSERT INTO nodes(node_id,group_id,display_name,platform,role,last_seen) VALUES($1,'__backend__','Backend gateway','Server','server',$2) ON CONFLICT DO NOTHING",
      [this.serverNodeId, now()],
    );
    const n = await this.db.query("SELECT role FROM nodes WHERE node_id=$1", [
      this.serverNodeId,
    ]);
    if (n.rows[0].role !== "server")
      throw new Error("Backend node ID already belongs to a client");
  }
  async tx<T>(fn: (c: Client) => Promise<T>): Promise<T> {
    const c = await this.db.connect();
    try {
      await c.query("BEGIN");
      await c.query("SELECT id FROM commit_clock WHERE id=1 FOR UPDATE");
      const result = await fn(c);
      await c.query("COMMIT");
      this.onCommit?.();
      return result;
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    } finally {
      c.release();
    }
  }
  async clock(c: Client, remote: number) {
    const old = Number(
        (await c.query("SELECT lamport FROM commit_clock WHERE id=1")).rows[0]
          .lamport,
      ),
      next = Math.max(old, remote) + 1;
    if (!Number.isSafeInteger(next))
      throw new ApiError(422, "VALIDATION_ERROR", "Lamport clock exhausted");
    await c.query("UPDATE commit_clock SET lamport=$1 WHERE id=1", [next]);
    return next;
  }
  async change(c: Client, group: string, body: unknown) {
    const r = await c.query(
      "INSERT INTO changes(event_id,group_id,body) VALUES($1,$2,$3) RETURNING sequence",
      [randomUUID(), group, body],
    );
    return "c" + r.rows[0].sequence;
  }
  async authorizeOrigin(c: Client, a: Actor, op: Operation) {
    let r = await c.query("SELECT group_id FROM nodes WHERE node_id=$1", [
      op.originNodeId,
    ]);
    if (!r.rowCount && a.role === "gateway") {
      await c.query(
        "INSERT INTO nodes(node_id, group_id, display_name, platform, role, last_seen) VALUES($1, $2, 'Mesh Node', 'ios', 'node', $3) ON CONFLICT (node_id) DO NOTHING",
        [op.originNodeId, a.group_id, Date.now()],
      );
      r = await c.query("SELECT group_id FROM nodes WHERE node_id=$1", [
        op.originNodeId,
      ]);
    }
    return (
      !!r.rowCount &&
      r.rows[0].group_id === a.group_id &&
      (op.originNodeId === a.node_id || a.role === "gateway")
    );
  }
  async push(a: Actor, body: ContractV1["PushRequest"]) {
    if (body.nodeId !== a.node_id)
      throw new ApiError(
        403,
        "FORBIDDEN",
        "Request nodeId must match credential",
      );
    const results: PushResult[] = [];
    for (const op of body.operations) {
      const result = await this.tx(async (c) => {
        if (!(await this.authorizeOrigin(c, a, op)))
          return reject(
            op.operationId,
            "FORBIDDEN",
            "Origin is not authorized",
          );
        const old = await c.query(
          "SELECT * FROM operations WHERE operation_id=$1",
          [op.operationId],
        );
        if (old.rowCount) {
          const row = old.rows[0];
          if (
            row.kind !== "OPERATION" ||
            row.group_id !== a.group_id ||
            canonical(row.request) !== canonical(op)
          )
            return reject(
              op.operationId,
              "ID_REUSE",
              "Operation ID already used with different content",
            );
          if (row.result.outcome === "COMMITTED") await projectSOS(c, a, op, Date.now());
          return { ...row.result, duplicate: true } as PushResult;
        }
        const entity = (
          await c.query("SELECT * FROM entities WHERE entity_id=$1", [
            op.entityId,
          ])
        ).rows[0];
        if (entity && entity.group_id !== a.group_id)
          return reject(
            op.operationId,
            "FORBIDDEN",
            "Entity is not authorized",
          );
        if (op.action === "CREATE" && entity)
          return reject(
            op.operationId,
            "VALIDATION_ERROR",
            "Entity already exists",
          );
        if (op.action === "UPDATE" && !entity)
          return reject(
            op.operationId,
            "ENTITY_NOT_FOUND",
            "Retrieve missing entity first",
            true,
          );
        if (entity && entity.entity_type !== op.entityType)
          return reject(
            op.operationId,
            "VALIDATION_ERROR",
            "Entity type cannot change",
          );
        if (op.entityType === "MESSAGE") {
          const recipient = await c.query(
            "SELECT group_id FROM nodes WHERE node_id=$1",
            [op.payload.recipientNodeId],
          );
          if (!recipient.rowCount || recipient.rows[0].group_id !== a.group_id)
            return reject(
              op.operationId,
              "ENTITY_NOT_FOUND",
              "Recipient is not provisioned",
              true,
            );
        }
        if (entity && op.baseVersion > Number(entity.version))
          return reject(
            op.operationId,
            "VALIDATION_ERROR",
            "Base version is ahead of backend",
          );
        const open = entity
          ? (
              await c.query(
                "SELECT * FROM conflicts WHERE entity_id=$1 AND body->>'status'='OPEN'",
                [op.entityId],
              )
            ).rows[0]
          : undefined;
        const time = now();
        await this.clock(c, op.lamportClock);
        if (entity && (open || Number(entity.version) !== op.baseVersion)) {
          let conflict: Conflict;
          if (open) {
            conflict = open.body;
            conflict = {
              ...conflict,
              revision: conflict.revision + 1,
              candidates: [...conflict.candidates, { operation: op }],
            };
            if (conflict.candidates.length > 100)
              throw new ApiError(
                503,
                "TEMPORARY_FAILURE",
                "Conflict candidate limit reached",
                true,
              );
          } else {
            const current = (
              await c.query(
                "SELECT operation FROM operations WHERE operation_id=$1",
                [entity.current_operation_id],
              )
            ).rows[0].operation;
            conflict = {
              schemaVersion: 1,
              conflictId: randomUUID(),
              entityId: op.entityId,
              baseVersion: op.baseVersion,
              revision: 1,
              currentEntityVersion: Number(entity.version),
              status: "OPEN",
              candidates: [{ operation: current }, { operation: op }],
            };
          }
          const result: PushResult = {
            operationId: op.operationId,
            outcome: "CONFLICT",
            duplicate: false,
            conflictId: conflict.conflictId,
          };
          await c.query(
            "INSERT INTO operations(operation_id,kind,group_id,request,operation,result,received_at) VALUES($1,'OPERATION',$2,$3,$3,$4,$5)",
            [op.operationId, a.group_id, op, result, time],
          );
          await c.query(
            "INSERT INTO conflicts(conflict_id,entity_id,group_id,body) VALUES($1,$2,$3,$4) ON CONFLICT(conflict_id) DO UPDATE SET body=excluded.body",
            [conflict.conflictId, op.entityId, a.group_id, conflict],
          );
          await this.change(c, a.group_id, {
            kind: "CONFLICT_CHANGED",
            conflictId: conflict.conflictId,
            revision: conflict.revision,
            timestamp: time,
          });
          return result;
        }
        const version = entity ? Number(entity.version) + 1 : 1;
        if (!Number.isSafeInteger(version))
          throw new ApiError(
            422,
            "VALIDATION_ERROR",
            "Entity version exhausted",
          );
        const ack: Ack = {
          schemaVersion: 1,
          ackId: randomUUID(),
          operationId: op.operationId,
          stage: "BACKEND_COMMITTED",
          acknowledgingNodeId: this.serverNodeId,
          timestamp: time,
          entityVersion: version,
        };
        const result: PushResult = {
          operationId: op.operationId,
          outcome: "COMMITTED",
          duplicate: false,
          entityVersion: version,
          ack,
        };
        await c.query(
          "INSERT INTO operations(operation_id,kind,group_id,request,operation,result,received_at) VALUES($1,'OPERATION',$2,$3,$3,$4,$5)",
          [op.operationId, a.group_id, op, result, time],
        );
        await c.query(
          "INSERT INTO entities(entity_id,group_id,entity_type,version,current_operation_id,payload) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(entity_id) DO UPDATE SET version=excluded.version,current_operation_id=excluded.current_operation_id,payload=excluded.payload",
          [
            op.entityId,
            a.group_id,
            op.entityType,
            version,
            op.operationId,
            op.payload,
          ],
        );
        await c.query(
          "INSERT INTO acknowledgments(ack_id,operation_id,node_id,stage,body) VALUES($1,$2,$3,$4,$5)",
          [ack.ackId, op.operationId, this.serverNodeId, ack.stage, ack],
        );
        await this.change(c, a.group_id, {
          kind: "COMMITTED_OPERATION",
          operation: op,
          entityVersion: version,
          committedAt: time,
        });
        await projectSOS(c, a, op, time);
        return result;
      });
      results.push(result);
    }
    const clock = Number(
      (await this.db.query("SELECT lamport FROM commit_clock WHERE id=1"))
        .rows[0].lamport,
    );
    return validate("PushResponse", {
      schemaVersion: 1,
      requestId: randomUUID(),
      results,
      serverLamportClock: clock,
    });
  }
  canSee(a: Actor, op: Operation) {
    return (
      a.role === "operator" ||
      a.role === "gateway" ||
      op.entityType !== "MESSAGE" ||
      op.originNodeId === a.node_id ||
      (op.entityType === "MESSAGE" && op.payload.recipientNodeId === a.node_id)
    );
  }
  async pull(a: Actor, cursor: string, limit: number, conflictsOnly = false) {
    const sequence = parseCursor(cursor);
    const rows = (
      await this.db.query(
        "SELECT sequence,group_id,body FROM changes WHERE sequence>$1 ORDER BY sequence LIMIT $2",
        [sequence, limit + 1],
      )
    ).rows;
    const scanned = rows.slice(0, limit),
      changes = [];
    for (const row of scanned) {
      if (row.group_id !== a.group_id) continue;
      const b = row.body;
      if (b.kind === "COMMITTED_OPERATION" && !this.canSee(a, b.operation))
        continue;
      if (b.kind === "ACKNOWLEDGMENT") {
        const o = (
          await this.db.query(
            "SELECT operation FROM operations WHERE operation_id=$1",
            [b.ack.operationId],
          )
        ).rows[0];
        if (!o || !this.canSee(a, o.operation)) continue;
      }
      if (conflictsOnly && b.kind !== "CONFLICT_CHANGED") continue;
      changes.push({ sequence: "c" + row.sequence, ...b });
    }
    const nextCursor = scanned.length ? "c" + scanned.at(-1)!.sequence : cursor;
    if (conflictsOnly) {
      const ids = [...new Set(changes.map((x) => x.conflictId))];
      const data = [];
      for (const id of ids) data.push(await this.conflict(a, id));
      return validate("ConflictList", {
        schemaVersion: 1,
        conflicts: data,
        nextCursor,
        hasMore: rows.length > limit,
      });
    }
    return validate("PullResponse", {
      schemaVersion: 1,
      changes,
      nextCursor,
      hasMore: rows.length > limit,
      serverLamportClock: Number(
        (await this.db.query("SELECT lamport FROM commit_clock WHERE id=1"))
          .rows[0].lamport,
      ),
    });
  }
  async conflict(a: Actor, id: string): Promise<Conflict> {
    const r = await this.db.query(
      "SELECT body FROM conflicts WHERE conflict_id=$1 AND group_id=$2",
      [id, a.group_id],
    );
    if (!r.rowCount)
      throw new ApiError(404, "ENTITY_NOT_FOUND", "Conflict not found");
    return r.rows[0].body;
  }
  async resolve(a: Actor, id: string, body: ContractV1["ResolveRequest"]) {
    if (a.role !== "operator" || body.resolverNodeId !== a.node_id)
      throw new ApiError(403, "FORBIDDEN", "Operator resolution required");
    return this.tx(async (c) => {
      const old = (
        await c.query("SELECT * FROM operations WHERE operation_id=$1", [
          body.operationId,
        ])
      ).rows[0];
      if (old) {
        if (
          old.kind !== "RESOLUTION" ||
          old.group_id !== a.group_id ||
          canonical(old.request) !== canonical({ conflictId: id, ...body })
        )
          throw new ApiError(409, "ID_REUSE", "Mutation ID already used");
        return { ...old.result, duplicate: true };
      }
      const row = (
        await c.query(
          "SELECT body FROM conflicts WHERE conflict_id=$1 AND group_id=$2",
          [id, a.group_id],
        )
      ).rows[0];
      if (!row)
        throw new ApiError(404, "ENTITY_NOT_FOUND", "Conflict not found");
      const conflict = row.body as Conflict;
      const entity = (
        await c.query("SELECT * FROM entities WHERE entity_id=$1", [
          conflict.entityId,
        ])
      ).rows[0];
      if (
        conflict.status !== "OPEN" ||
        conflict.revision !== body.expectedConflictRevision ||
        Number(entity.version) !== body.expectedEntityVersion
      )
        throw new ApiError(
          409,
          "STALE_RESOLUTION",
          "Reload conflict before resolving",
        );
      const selected = conflict.candidates.find(
        (x) => x.operation.operationId === body.selectedOperationId,
      );
      if (!selected || selected.operation.entityType !== "ANNOUNCEMENT")
        throw new ApiError(
          422,
          "VALIDATION_ERROR",
          "Invalid conflict candidate",
        );
      const version = Number(entity.version) + 1,
        time = now();
      const op: Operation = {
        schemaVersion: 1,
        operationId: body.operationId,
        originNodeId: a.node_id,
        entityId: conflict.entityId,
        entityType: "ANNOUNCEMENT",
        action: "UPDATE",
        baseVersion: Number(entity.version),
        timestamp: body.timestamp,
        lamportClock: body.lamportClock,
        payload: selected.operation.payload,
      };
      const resolved: Conflict = {
        ...conflict,
        status: "RESOLVED",
        revision: conflict.revision + 1,
        currentEntityVersion: version,
        resolutionOperationId: body.operationId,
        selectedOperationId: body.selectedOperationId,
      };
      const ack: Ack = {
        schemaVersion: 1,
        ackId: randomUUID(),
        operationId: body.operationId,
        stage: "BACKEND_COMMITTED",
        acknowledgingNodeId: this.serverNodeId,
        timestamp: time,
        entityVersion: version,
      };
      const result = validate("ResolveResponse", {
        schemaVersion: 1,
        resolutionOperationId: body.operationId,
        duplicate: false,
        conflict: resolved,
        ack,
      });
      await this.clock(c, body.lamportClock);
      await c.query(
        "INSERT INTO operations(operation_id,kind,group_id,request,operation,result,received_at) VALUES($1,'RESOLUTION',$2,$3,$4,$5,$6)",
        [
          body.operationId,
          a.group_id,
          { conflictId: id, ...body },
          op,
          result,
          time,
        ],
      );
      await c.query(
        "UPDATE entities SET version=$2,payload=$3,current_operation_id=$4 WHERE entity_id=$1",
        [op.entityId, version, op.payload, op.operationId],
      );
      await c.query("UPDATE conflicts SET body=$2 WHERE conflict_id=$1", [
        id,
        resolved,
      ]);
      await c.query(
        "INSERT INTO acknowledgments(ack_id,operation_id,node_id,stage,body) VALUES($1,$2,$3,$4,$5)",
        [ack.ackId, op.operationId, this.serverNodeId, ack.stage, ack],
      );
      await this.change(c, a.group_id, {
        kind: "COMMITTED_OPERATION",
        operation: op,
        entityVersion: version,
        committedAt: time,
      });
      await this.change(c, a.group_id, {
        kind: "CONFLICT_CHANGED",
        conflictId: id,
        revision: resolved.revision,
        timestamp: time,
      });
      return result;
    });
  }
  async receipt(a: Actor, body: ContractV1["ReceiptRequest"]) {
    const ack = body.ack;
    if (
      body.nodeId !== a.node_id ||
      ack.acknowledgingNodeId !== a.node_id ||
      ack.stage === "BACKEND_COMMITTED"
    )
      throw new ApiError(403, "FORBIDDEN", "Client cannot assert this receipt");
    return this.tx(async (c) => {
      const o = (
        await c.query(
          "SELECT operation,group_id FROM operations WHERE operation_id=$1",
          [ack.operationId],
        )
      ).rows[0];
      if (!o || o.group_id !== a.group_id)
        throw new ApiError(
          404,
          "ENTITY_NOT_FOUND",
          "Upload referenced operation first",
          true,
        );
      if (
        ack.stage === "RECIPIENT_ACKNOWLEDGED" &&
        a.role !== "operator" &&
        (o.operation.entityType !== "MESSAGE" ||
          o.operation.payload.recipientNodeId !== a.node_id)
      )
        throw new ApiError(
          403,
          "FORBIDDEN",
          "Only intended recipient or operator may acknowledge",
        );
      const old = (
        await c.query("SELECT body FROM acknowledgments WHERE ack_id=$1", [
          ack.ackId,
        ])
      ).rows[0];
      if (old) {
        if (canonical(old.body) !== canonical(ack))
          throw new ApiError(409, "ID_REUSE", "Acknowledgment ID reused");
        return { schemaVersion: 1, acceptedAckId: ack.ackId, duplicate: true };
      }
      const stage = (
        await c.query(
          "SELECT ack_id FROM acknowledgments WHERE operation_id=$1 AND node_id=$2 AND stage=$3",
          [ack.operationId, a.node_id, ack.stage],
        )
      ).rows[0];
      if (stage)
        throw new ApiError(409, "ID_REUSE", "Reuse the existing receipt ID");
      await c.query(
        "INSERT INTO acknowledgments(ack_id,operation_id,node_id,stage,body) VALUES($1,$2,$3,$4,$5)",
        [ack.ackId, ack.operationId, a.node_id, ack.stage, ack],
      );
      await this.change(c, a.group_id, { kind: "ACKNOWLEDGMENT", ack });
      return validate("ReceiptResponse", {
        schemaVersion: 1,
        acceptedAckId: ack.ackId,
        duplicate: false,
      });
    });
  }
  async snapshot(a: Actor) {
    if (a.role !== "operator")
      throw new ApiError(403, "FORBIDDEN", "Operator session required");
    // Consistent read across all projection queries.
    const c = await this.db.connect();
    try {
      await c.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
      const observedAt = now(),
        probeStart = performance.now();
      const nodes = (
        await c.query(
          "SELECT * FROM nodes WHERE group_id=$1 ORDER BY node_id LIMIT 999",
          [a.group_id],
        )
      ).rows.map((n) => ({
        id: n.node_id,
        name: n.display_name,
        platform: n.platform,
        role: n.role === "gateway" ? "gateway" : "client",
        status:
          observedAt - Number(n.last_seen) < 45000 ? "active" : "unreachable",
        lastSeen: Number(n.last_seen),
      }));
      nodes.push({
        id: this.serverNodeId,
        name: "Backend gateway",
        platform: "Server",
        role: "gateway",
        status: "active",
        lastSeen: observedAt,
      });
      const rows = (
        await c.query(
          "SELECT * FROM operations WHERE group_id=$1 ORDER BY received_at DESC,operation_id LIMIT 100",
          [a.group_id],
        )
      ).rows;
      const operations = [];
      for (const row of rows) {
        const op = row.operation as Operation;
        const receipts = (
          await c.query(
            "SELECT body FROM acknowledgments WHERE operation_id=$1",
            [op.operationId],
          )
        ).rows.map((r) => r.body as Ack);
        const backendReceipt = receipts.find(
          (x) => x.stage === "BACKEND_COMMITTED",
        );
        operations.push({
          id: op.operationId,
          origin: op.originNodeId,
          kind:
            op.entityType === "MESSAGE"
              ? "Message"
              : op.entityType === "SOS"
                ? "SOS"
                : "Announcement",
          status:
            row.result.outcome === "CONFLICT"
              ? "conflict"
              : backendReceipt
                ? "synced"
                : "queued",
          createdAt: op.timestamp,
          hops: 0,
          ...(row.result.conflictId
            ? { conflictId: row.result.conflictId }
            : {}),
          delivery: {
            peerReceipts: receipts.filter((x) => x.stage === "PEER_STORED"),
            relayAttempts: [],
            recipientReceipts: receipts.filter(
              (x) => x.stage === "RECIPIENT_ACKNOWLEDGED",
            ),
            ...(backendReceipt ? { backendReceipt } : {}),
          },
        });
      }
      const conflicts = (
        await c.query(
          "SELECT body FROM conflicts WHERE group_id=$1 ORDER BY conflict_id LIMIT 100",
          [a.group_id],
        )
      ).rows.filter((r) => r.body.candidates.length === 2).map((r) => {
        const x = r.body as Conflict,
          [left, right] = x.candidates;
        return {
          id: x.conflictId,
          entity: "Announcement " + x.entityId,
          baseVersion: x.baseVersion,
          left: left.operation.payload.text,
          right: right.operation.payload.text,
          leftNode: left.operation.originNodeId,
          rightNode: right.operation.originNodeId,
          revision: x.revision,
          currentEntityVersion: x.currentEntityVersion,
          candidateOperationIds: x.candidates
            .slice(0, 2)
            .map((x) => x.operation.operationId),
          ...(x.status === "RESOLVED"
            ? {
                resolved:
                  x.selectedOperationId === left.operation.operationId
                    ? "left"
                    : "right",
              }
            : {}),
        };
      });
      const alertRows = (
        await c.query(
          "SELECT e.*,o.operation FROM entities e JOIN operations o ON o.operation_id=e.current_operation_id WHERE e.group_id=$1 AND e.entity_type='SOS' ORDER BY e.entity_id LIMIT 100",
          [a.group_id],
        )
      ).rows;
      const alerts = [];
      for (const e of alertRows) {
        const receipt = (
          await c.query(
            "SELECT 1 FROM acknowledgments WHERE operation_id=$1 AND stage='RECIPIENT_ACKNOWLEDGED' LIMIT 1",
            [e.current_operation_id],
          )
        ).rowCount;
        alerts.push({
          id: e.entity_id,
          title: e.payload.text,
          category: e.payload.category,
          location: e.payload.location.label,
          nodeId: e.operation.originNodeId,
          status: receipt ? "acknowledged" : "new",
          createdAt: e.operation.timestamp,
        });
      }

      const events = (
        await c.query(
          "SELECT sequence,event_id,body FROM changes WHERE group_id=$1 ORDER BY sequence DESC LIMIT 100",
          [a.group_id],
        )
      ).rows.map((r) => ({
        id: r.event_id,
        title: r.body.kind,
        detail: "Durable backend event",
        time:
          r.body.committedAt ||
          r.body.timestamp ||
          r.body.ack?.timestamp ||
          observedAt,
        kind: "success",
      }));
      const snapshot = validate("DashboardSnapshot", {
        schemaVersion: 1,
        observedAt,
        nodes,
        links: [],
        operations,
        alerts,
        conflicts,
        gateways: [
          {
            nodeId: this.serverNodeId,
            reachable: true,
            selected: true,
            latency: Math.max(0, Math.round(performance.now() - probeStart)),
          },
        ],
        events,
      });
      await c.query("COMMIT");
      return snapshot;
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    } finally {
      c.release();
    }
  }
  async latestCursor() {
    return (
      "c" +
      (
        await this.db.query(
          "SELECT COALESCE(max(sequence),0)::text AS seq FROM changes",
        )
      ).rows[0].seq
    );
  }
}
export function parseCursor(s: string) {
  if (!/^c[0-9]{1,20}$/.test(s))
    throw new ApiError(400, "VALIDATION_ERROR", "Invalid cursor");
  const n = BigInt(s.slice(1));
  if (n > 9223372036854775807n)
    throw new ApiError(400, "VALIDATION_ERROR", "Cursor out of range");
  return n.toString();
}
