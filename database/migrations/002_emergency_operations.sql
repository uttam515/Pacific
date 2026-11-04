-- Additive projection: canonical rc.2 operations and ACKs remain unchanged.
CREATE TABLE authorities (
 authority_id uuid PRIMARY KEY, group_id text NOT NULL, name text NOT NULL,
 category text NOT NULL, contact text NOT NULL, active boolean NOT NULL DEFAULT true,
 revision integer NOT NULL DEFAULT 1
);
CREATE TABLE responders (
 responder_id uuid PRIMARY KEY, group_id text NOT NULL, authority_id uuid NOT NULL REFERENCES authorities,
 name text NOT NULL, contact text NOT NULL, active boolean NOT NULL DEFAULT true,
 revision integer NOT NULL DEFAULT 1
);
CREATE TABLE incidents (
 incident_id uuid PRIMARY KEY REFERENCES entities(entity_id), group_id text NOT NULL,
 operation_id uuid UNIQUE NOT NULL REFERENCES operations, origin_node_id uuid NOT NULL REFERENCES nodes,
 first_gateway_id uuid REFERENCES nodes, received_at bigint NOT NULL,
 status text NOT NULL DEFAULT 'RECEIVED' CHECK(status IN ('RECEIVED','ACKNOWLEDGED','AUTHORITY_NOTIFIED','RESPONDER_ASSIGNED','RESPONDER_EN_ROUTE','RESOLVED','CANCELLED')),
 authority_id uuid REFERENCES authorities, responder_id uuid REFERENCES responders,
 revision integer NOT NULL DEFAULT 1
);
CREATE INDEX incidents_group_time ON incidents(group_id,received_at DESC,incident_id);
CREATE TABLE incident_events (
 event_id uuid PRIMARY KEY, incident_id uuid NOT NULL REFERENCES incidents, group_id text NOT NULL,
 actor_id uuid NOT NULL REFERENCES nodes, kind text NOT NULL, occurred_at bigint NOT NULL,
 details jsonb NOT NULL DEFAULT '{}'
);
CREATE INDEX incident_events_order ON incident_events(incident_id,occurred_at,event_id);
CREATE TABLE authority_notifications (
 notification_id uuid PRIMARY KEY, incident_id uuid NOT NULL REFERENCES incidents,
 authority_id uuid NOT NULL REFERENCES authorities, group_id text NOT NULL,
 mode text NOT NULL CHECK(mode='SANDBOX'), status text NOT NULL CHECK(status IN ('SANDBOX_SUBMITTED','SANDBOX_ACKNOWLEDGED')),
 submitted_at bigint NOT NULL, acknowledged_at bigint
);
CREATE TABLE gateway_health (
 node_id uuid PRIMARY KEY REFERENCES nodes, group_id text NOT NULL, observed_at bigint NOT NULL,
 reported_at bigint NOT NULL, body jsonb NOT NULL
);
CREATE TABLE gateway_uploads (
 node_id uuid NOT NULL REFERENCES nodes, operation_id uuid NOT NULL REFERENCES operations,
 first_seen bigint NOT NULL, last_seen bigint NOT NULL, attempts integer NOT NULL DEFAULT 1,
 observation jsonb, PRIMARY KEY(node_id,operation_id)
);
CREATE TABLE emergency_commands (
 command_id uuid PRIMARY KEY, actor_id uuid NOT NULL REFERENCES nodes, group_id text NOT NULL,
 request jsonb NOT NULL, response jsonb NOT NULL, created_at bigint NOT NULL
);
CREATE TABLE emergency_audit (
 audit_id uuid PRIMARY KEY, group_id text NOT NULL, actor_id uuid NOT NULL REFERENCES nodes,
 kind text NOT NULL, subject_id uuid NOT NULL, timestamp bigint NOT NULL, details jsonb NOT NULL
);
CREATE INDEX emergency_audit_group_time ON emergency_audit(group_id,timestamp DESC);
-- Existing SOS commitments become incidents without inventing a receiving gateway.
INSERT INTO incidents(incident_id,group_id,operation_id,origin_node_id,received_at)
SELECT e.entity_id,e.group_id,o.operation_id,(o.operation->>'originNodeId')::uuid,o.received_at
FROM entities e JOIN operations o ON o.operation_id=e.current_operation_id WHERE e.entity_type='SOS';
INSERT INTO incident_events(event_id,incident_id,group_id,actor_id,kind,occurred_at,details)
SELECT a.ack_id,i.incident_id,i.group_id,a.node_id,'SERVER_RECEIVED',i.received_at,'{"source":"existing durable commitment"}'::jsonb
FROM incidents i JOIN acknowledgments a ON a.operation_id=i.operation_id AND a.stage='BACKEND_COMMITTED';
