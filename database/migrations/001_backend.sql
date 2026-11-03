CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE nodes (
 node_id uuid PRIMARY KEY, group_id text NOT NULL DEFAULT 'local-demo',
 display_name text NOT NULL, platform text NOT NULL,
 role text NOT NULL CHECK (role IN ('node','gateway','operator','server')),
 last_seen bigint NOT NULL DEFAULT 0
);
CREATE TABLE credentials (
 token_hash text PRIMARY KEY, node_id uuid NOT NULL REFERENCES nodes,
 kind text NOT NULL CHECK (kind IN ('bearer','session')), revoked boolean NOT NULL DEFAULT false,
 expires_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
-- Serialize mutations through this single row for the small MVP. This ensures
-- cursor order follows commit order, unlike unconstrained concurrent bigserial inserts.
CREATE TABLE commit_clock (id integer PRIMARY KEY CHECK(id=1), lamport bigint NOT NULL DEFAULT 0);
INSERT INTO commit_clock(id) VALUES(1);
CREATE TABLE operations (
 operation_id uuid PRIMARY KEY, kind text NOT NULL CHECK(kind IN ('OPERATION','RESOLUTION')),
 group_id text NOT NULL, request jsonb NOT NULL, operation jsonb NOT NULL,
 result jsonb NOT NULL, received_at bigint NOT NULL
);
CREATE TABLE entities (
 entity_id uuid PRIMARY KEY, group_id text NOT NULL, entity_type text NOT NULL,
 version bigint NOT NULL CHECK(version>0), current_operation_id uuid NOT NULL REFERENCES operations,
 payload jsonb NOT NULL
);
CREATE TABLE acknowledgments (
 ack_id uuid PRIMARY KEY, operation_id uuid NOT NULL REFERENCES operations,
 node_id uuid NOT NULL REFERENCES nodes, stage text NOT NULL, body jsonb NOT NULL,
 UNIQUE(operation_id,node_id,stage)
);
CREATE TABLE conflicts (
 conflict_id uuid PRIMARY KEY, entity_id uuid NOT NULL REFERENCES entities,
 group_id text NOT NULL, body jsonb NOT NULL
);
CREATE UNIQUE INDEX one_open_conflict ON conflicts(entity_id) WHERE body->>'status'='OPEN';
CREATE TABLE changes (
 sequence bigserial PRIMARY KEY, event_id uuid NOT NULL UNIQUE, group_id text NOT NULL, body jsonb NOT NULL
);
CREATE INDEX changes_group_sequence ON changes(group_id,sequence);
CREATE INDEX operations_group_time ON operations(group_id,received_at DESC);
