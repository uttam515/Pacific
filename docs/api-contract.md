> **Contract review update:** [v1 candidate](contracts/v1/README.md) supersedes the draft definitions below for review. Neither these drafts nor the candidate are implemented backend APIs. Freeze requires all three engineers' approval.

# OFFGRID API & Synchronization Contract

> **Owner:** Engineer 1 (Web, Backend & Infrastructure Lead)  
> **Clients:** Web Dashboard (Eng 1), Android (Eng 2), iOS (Eng 3)

---

## 1. REST Endpoints (HTTP Gateway)

Base URL: `http://<gateway-ip>:4000/api/v1`

### Health & Discovery
- `GET /health`  
  Returns server health, gateway role, and current system timestamp.

- `GET /network/status`  
  Returns active node counts, mesh metrics, and known gateway list.

### Synchronization
- `POST /sync/push`  
  Pushes a batch of local operations from a mobile client to the central server.  
  **Request Body:**
  ```json
  {
    "nodeId": "STRING",
    "operations": [
      {
        "operationId": "UUID",
        "entityType": "MESSAGE | SOS | ANNOUNCEMENT",
        "action": "CREATE | UPDATE | DELETE",
        "timestamp": 1730650000000,
        "lamportClock": 42,
        "payload": { ... }
      }
    ]
  }
  ```
  **Response:**
  ```json
  {
    "acceptedIds": ["UUID-1", "UUID-2"],
    "conflictedIds": [],
    "serverLamportClock": 50
  }
  ```

- `GET /sync/pull?sinceClock=<int>&nodeId=<string>`  
  Retrieves operations committed to the central database since the client's last observed clock.

---

## 2. WebSocket Real-Time Channel

Endpoint: `ws://<gateway-ip>:4001/ws`

### Client -> Server Events
- `NODE_ANNOUNCE`: Client registers its presence, active radios, and public key.
- `DISPATCH_PACKET`: Sends a packet to the server for distribution or relay.
- `SUBSCRIBE_CHANNELS`: Requests real-time updates for specific chat rooms or emergency channels.

### Server -> Client Events
- `PACKET_INCOMING`: Server relays a packet destined for or broadcasted to this node.
- `PEER_PRESENCE_UPDATE`: Alerts node of nearby connected peers.
- `SYNC_NOTIFICATION`: Informs client that new operations exist to pull.
