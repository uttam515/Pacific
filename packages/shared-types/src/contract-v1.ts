/* Generated from pinned rc.2 JSON Schema. Run pnpm contract:types; do not edit by hand. */

export type UUID = string;
export type Integer = number;
export type Cursor = string;
export type Operation =
  | {
      schemaVersion: 1;
      operationId: UUID;
      originNodeId: UUID;
      entityId: UUID;
      timestamp: Integer;
      lamportClock: Integer;
      entityType: "MESSAGE";
      action: "CREATE";
      baseVersion: 0;
      payload: MessagePayload;
    }
  | {
      schemaVersion: 1;
      operationId: UUID;
      originNodeId: UUID;
      entityId: UUID;
      timestamp: Integer;
      lamportClock: Integer;
      entityType: "SOS";
      action: "CREATE";
      baseVersion: 0;
      payload: SOSPayload;
    }
  | {
      schemaVersion: 1;
      operationId: UUID;
      originNodeId: UUID;
      entityId: UUID;
      timestamp: Integer;
      lamportClock: Integer;
      entityType: "ANNOUNCEMENT";
      action: "CREATE";
      baseVersion: 0;
      payload: AnnouncementPayload;
    }
  | {
      schemaVersion: 1;
      operationId: UUID;
      originNodeId: UUID;
      entityId: UUID;
      timestamp: Integer;
      lamportClock: Integer;
      entityType: "ANNOUNCEMENT";
      action: "UPDATE";
      baseVersion: number;
      payload: AnnouncementPayload;
    };
export type Acknowledgment = {
  [k: string]: unknown;
} & {
  schemaVersion: 1;
  ackId: UUID;
  operationId: UUID;
  stage: "PEER_STORED" | "BACKEND_COMMITTED" | "RECIPIENT_ACKNOWLEDGED";
  acknowledgingNodeId: UUID;
  timestamp: Integer;
  packetId?: UUID;
  entityVersion?: number;
};
export type Envelope =
  | {
      version: 1;
      packetId: UUID;
      sourceNodeId: UUID;
      destinationNodeId: UUID | "*";
      timestamp: Integer;
      ttl: number;
      hopCount: number;
      type: "SYNC_OP";
      payload: Operation;
    }
  | {
      version: 1;
      packetId: UUID;
      sourceNodeId: UUID;
      destinationNodeId: UUID | "*";
      timestamp: Integer;
      ttl: number;
      hopCount: number;
      type: "ACK";
      payload: Acknowledgment;
    };
export type PushResult =
  | {
      operationId: UUID;
      outcome: "COMMITTED";
      duplicate: boolean;
      entityVersion: number;
      ack: Acknowledgment;
    }
  | {
      operationId: UUID;
      outcome: "CONFLICT";
      duplicate: boolean;
      conflictId: UUID;
    }
  | {
      operationId: UUID;
      outcome: "REJECTED";
      error: Error;
    };
export type Change =
  | {
      sequence: Cursor;
      kind: "COMMITTED_OPERATION";
      operation: Operation;
      entityVersion: number;
      committedAt: Integer;
    }
  | {
      sequence: Cursor;
      kind: "CONFLICT_CHANGED";
      conflictId: UUID;
      revision: number;
      timestamp: Integer;
    }
  | {
      sequence: Cursor;
      kind: "ACKNOWLEDGMENT";
      ack: Acknowledgment;
    };
export type Conflict = {
  [k: string]: unknown;
} & {
  schemaVersion: 1;
  conflictId: UUID;
  entityId: UUID;
  baseVersion: Integer;
  revision: number;
  currentEntityVersion: number;
  status: "OPEN" | "RESOLVED";
  /**
   * @minItems 2
   * @maxItems 100
   */
  candidates: Candidate[];
  resolutionOperationId?: UUID;
  selectedOperationId?: UUID;
};

export interface ContractV1 {
  UUID: UUID;
  Integer: Integer;
  Cursor: Cursor;
  MessagePayload: MessagePayload;
  SOSPayload: SOSPayload;
  AnnouncementPayload: AnnouncementPayload;
  Operation: Operation;
  Acknowledgment: Acknowledgment;
  Envelope: Envelope;
  Error: Error;
  ErrorResponse: ErrorResponse;
  PushRequest: PushRequest;
  PushResult: PushResult;
  PushResponse: PushResponse;
  Change: Change;
  PullResponse: PullResponse;
  Candidate: Candidate;
  Conflict: Conflict;
  ConflictList: ConflictList;
  ResolveRequest: ResolveRequest;
  ResolveResponse: ResolveResponse;
  Notification: Notification;
  ReceiptRequest: ReceiptRequest;
  ReceiptResponse: ReceiptResponse;
  DeliveryEvidence: DeliveryEvidence;
  DashboardNode: DashboardNode;
  DashboardOperation: DashboardOperation;
  DashboardAlert: DashboardAlert;
  DashboardConflict: DashboardConflict;
  DashboardGateway: DashboardGateway;
  DashboardEvent: DashboardEvent;
  DashboardSnapshot: DashboardSnapshot;
  Health: Health;
}
export interface MessagePayload {
  text: string;
  recipientNodeId: UUID;
}
export interface SOSPayload {
  text: string;
  category: "ASSISTANCE" | "MEDICAL" | "SUPPLIES" | "OTHER";
  location: {
    label: string;
    latitude?: number;
    longitude?: number;
  };
}
export interface AnnouncementPayload {
  text: string;
}
export interface Error {
  code:
    | "VALIDATION_ERROR"
    | "UNAUTHORIZED"
    | "FORBIDDEN"
    | "ID_REUSE"
    | "STALE_RESOLUTION"
    | "CURSOR_EXPIRED"
    | "UNSUPPORTED_VERSION"
    | "TOO_LARGE"
    | "TEMPORARY_FAILURE"
    | "ENTITY_NOT_FOUND";
  message: string;
  retryable: boolean;
}
export interface ErrorResponse {
  schemaVersion: 1;
  error: Error;
}
export interface PushRequest {
  schemaVersion: 1;
  nodeId: UUID;
  /**
   * @minItems 1
   * @maxItems 100
   */
  operations: Operation[];
}
export interface PushResponse {
  schemaVersion: 1;
  requestId: UUID;
  /**
   * @maxItems 100
   */
  results: PushResult[];
  serverLamportClock: Integer;
}
export interface PullResponse {
  schemaVersion: 1;
  /**
   * @maxItems 100
   */
  changes: Change[];
  nextCursor: Cursor;
  hasMore: boolean;
  serverLamportClock: Integer;
}
export interface Candidate {
  operation: Operation;
}
export interface ConflictList {
  schemaVersion: 1;
  /**
   * @maxItems 100
   */
  conflicts: Conflict[];
  nextCursor: Cursor;
  hasMore: boolean;
}
export interface ResolveRequest {
  schemaVersion: 1;
  operationId: UUID;
  resolverNodeId: UUID;
  selectedOperationId: UUID;
  expectedConflictRevision: number;
  expectedEntityVersion: number;
  timestamp: Integer;
  lamportClock: Integer;
}
export interface ResolveResponse {
  schemaVersion: 1;
  resolutionOperationId: UUID;
  duplicate: boolean;
  conflict: Conflict;
  ack: Acknowledgment;
}
export interface Notification {
  schemaVersion: 1;
  type: "SYNC_NOTIFICATION";
  eventId: UUID;
  timestamp: Integer;
  latestCursor: Cursor;
}
export interface ReceiptRequest {
  schemaVersion: 1;
  nodeId: UUID;
  ack: Acknowledgment;
}
export interface ReceiptResponse {
  schemaVersion: 1;
  acceptedAckId: UUID;
  duplicate: boolean;
}
export interface DeliveryEvidence {
  localStoredAt?: Integer;
  queuedAt?: Integer;
  /**
   * @maxItems 100
   */
  peerReceipts: Acknowledgment[];
  /**
   * @maxItems 100
   */
  relayAttempts: {
    packetId: UUID;
    forwarderNodeId: UUID;
    nextHopNodeId: UUID;
    timestamp: Integer;
    result: "SENT" | "FAILED";
    retryable: boolean;
  }[];
  backendReceipt?: Acknowledgment;
  /**
   * @maxItems 100
   */
  recipientReceipts: Acknowledgment[];
  lastAttemptError?: Error;
}
export interface DashboardNode {
  id: UUID;
  name: string;
  platform: "iOS" | "Android" | "Windows" | "macOS" | "Linux" | "Web" | "Server";
  role: "client" | "relay" | "gateway";
  status: "active" | "unreachable";
  lastSeen: Integer;
  battery?: number;
}
export interface DashboardOperation {
  id: UUID;
  origin: UUID;
  kind: "Message" | "SOS" | "Announcement";
  status: "queued" | "relayed" | "synced" | "conflict";
  createdAt: Integer;
  hops: number;
  conflictId?: UUID;
  delivery: DeliveryEvidence;
}
export interface DashboardAlert {
  id: UUID;
  title: string;
  category: string;
  location: string;
  nodeId: UUID;
  status: "new" | "acknowledged" | "resolved";
  createdAt: Integer;
}
export interface DashboardConflict {
  id: UUID;
  entity: string;
  baseVersion: Integer;
  left: string;
  right: string;
  leftNode: string;
  rightNode: string;
  resolved?: "left" | "right";
  revision: number;
  currentEntityVersion: number;
  /**
   * @minItems 2
   * @maxItems 2
   */
  candidateOperationIds: UUID[];
}
export interface DashboardGateway {
  nodeId: UUID;
  reachable: boolean;
  selected: boolean;
  latency: number;
}
export interface DashboardEvent {
  id: UUID;
  title: string;
  detail: string;
  time: Integer;
  kind: "info" | "success" | "warning";
}
export interface DashboardSnapshot {
  schemaVersion: 1;
  observedAt: Integer;
  /**
   * @maxItems 1000
   */
  nodes: DashboardNode[];
  /**
   * @maxItems 5000
   */
  links: {
    from: UUID;
    to: UUID;
  }[];
  /**
   * @maxItems 100
   */
  operations: DashboardOperation[];
  /**
   * @maxItems 100
   */
  alerts: DashboardAlert[];
  /**
   * @maxItems 100
   */
  conflicts: DashboardConflict[];
  /**
   * @maxItems 1000
   */
  gateways: DashboardGateway[];
  /**
   * @maxItems 100
   */
  events: DashboardEvent[];
}
export interface Health {
  schemaVersion: 1;
  status: "ok";
}
