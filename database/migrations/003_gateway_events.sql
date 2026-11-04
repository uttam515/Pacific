CREATE TABLE gateway_events (
 event_id uuid PRIMARY KEY, group_id text NOT NULL, node_id uuid NOT NULL REFERENCES nodes,
 kind text NOT NULL, occurred_at bigint NOT NULL, details jsonb NOT NULL
);
CREATE INDEX gateway_events_group_time ON gateway_events(group_id,occurred_at DESC);
