# OFFGRID API Server

> **Lead:** Engineer 1  
> **Stack:** Node.js, Express, WebSocket (`ws`), PostgreSQL

Provides the central HTTP REST endpoints and WebSocket gateway for the OFFGRID network.
- Ingestion of client synchronization batches (`/api/v1/sync/push`).
- Operation history pull (`/api/v1/sync/pull`).
- Real-time event forwarding to connected web clients and stationary gateways.
