# Concrete JSON examples — v1 candidate

These fixtures use synthetic IDs and a fixed example timestamp. No bearer token is included. Replace IDs and timestamps for actual runs. Every example below is loaded by the same fixture test suite.

## Operation

```json
{
  "schemaVersion": 1,
  "operationId": "00000000-0000-4000-8000-000000000020",
  "originNodeId": "00000000-0000-4000-8000-000000000001",
  "entityId": "00000000-0000-4000-8000-000000000010",
  "timestamp": 1793721600000,
  "lamportClock": 1,
  "entityType": "MESSAGE",
  "action": "CREATE",
  "baseVersion": 0,
  "payload": {
    "text": "Offline iPhone integration test",
    "recipientNodeId": "00000000-0000-4000-8000-000000000002"
  }
}
```

## Transport envelope

```json
{
  "version": 1,
  "packetId": "00000000-0000-4000-8000-000000000030",
  "sourceNodeId": "00000000-0000-4000-8000-000000000001",
  "destinationNodeId": "00000000-0000-4000-8000-000000000002",
  "timestamp": 1793721600000,
  "ttl": 5,
  "hopCount": 0,
  "type": "SYNC_OP",
  "payload": {
    "schemaVersion": 1,
    "operationId": "00000000-0000-4000-8000-000000000020",
    "originNodeId": "00000000-0000-4000-8000-000000000001",
    "entityId": "00000000-0000-4000-8000-000000000010",
    "timestamp": 1793721600000,
    "lamportClock": 1,
    "entityType": "MESSAGE",
    "action": "CREATE",
    "baseVersion": 0,
    "payload": {
      "text": "Offline iPhone integration test",
      "recipientNodeId": "00000000-0000-4000-8000-000000000002"
    }
  }
}
```

## Peer acknowledgment

```json
{
  "schemaVersion": 1,
  "ackId": "00000000-0000-4000-8000-000000000041",
  "operationId": "00000000-0000-4000-8000-000000000020",
  "stage": "PEER_STORED",
  "acknowledgingNodeId": "00000000-0000-4000-8000-000000000002",
  "timestamp": 1793721602000,
  "packetId": "00000000-0000-4000-8000-000000000030"
}
```

## Backend acknowledgment

```json
{
  "schemaVersion": 1,
  "ackId": "00000000-0000-4000-8000-000000000040",
  "operationId": "00000000-0000-4000-8000-000000000020",
  "stage": "BACKEND_COMMITTED",
  "acknowledgingNodeId": "00000000-0000-4000-8000-000000000003",
  "timestamp": 1793721602000,
  "entityVersion": 1
}
```

## Recipient acknowledgment

```json
{
  "schemaVersion": 1,
  "ackId": "00000000-0000-4000-8000-000000000042",
  "operationId": "00000000-0000-4000-8000-000000000020",
  "stage": "RECIPIENT_ACKNOWLEDGED",
  "acknowledgingNodeId": "00000000-0000-4000-8000-000000000002",
  "timestamp": 1793721602000,
  "packetId": "00000000-0000-4000-8000-000000000030"
}
```

## Push request

```json
{
  "schemaVersion": 1,
  "nodeId": "00000000-0000-4000-8000-000000000001",
  "operations": [
    {
      "schemaVersion": 1,
      "operationId": "00000000-0000-4000-8000-000000000020",
      "originNodeId": "00000000-0000-4000-8000-000000000001",
      "entityId": "00000000-0000-4000-8000-000000000010",
      "timestamp": 1793721600000,
      "lamportClock": 1,
      "entityType": "MESSAGE",
      "action": "CREATE",
      "baseVersion": 0,
      "payload": {
        "text": "Offline iPhone integration test",
        "recipientNodeId": "00000000-0000-4000-8000-000000000002"
      }
    }
  ]
}
```

## Push response

```json
{
  "schemaVersion": 1,
  "requestId": "00000000-0000-4000-8000-000000000050",
  "results": [
    {
      "operationId": "00000000-0000-4000-8000-000000000020",
      "outcome": "COMMITTED",
      "duplicate": false,
      "entityVersion": 1,
      "ack": {
        "schemaVersion": 1,
        "ackId": "00000000-0000-4000-8000-000000000040",
        "operationId": "00000000-0000-4000-8000-000000000020",
        "stage": "BACKEND_COMMITTED",
        "acknowledgingNodeId": "00000000-0000-4000-8000-000000000003",
        "timestamp": 1793721602000,
        "entityVersion": 1
      }
    }
  ],
  "serverLamportClock": 2
}
```

## Duplicate response

```json
{
  "schemaVersion": 1,
  "requestId": "00000000-0000-4000-8000-000000000051",
  "results": [
    {
      "operationId": "00000000-0000-4000-8000-000000000020",
      "outcome": "COMMITTED",
      "duplicate": true,
      "entityVersion": 1,
      "ack": {
        "schemaVersion": 1,
        "ackId": "00000000-0000-4000-8000-000000000040",
        "operationId": "00000000-0000-4000-8000-000000000020",
        "stage": "BACKEND_COMMITTED",
        "acknowledgingNodeId": "00000000-0000-4000-8000-000000000003",
        "timestamp": 1793721602000,
        "entityVersion": 1
      }
    }
  ],
  "serverLamportClock": 2
}
```

## Pull response

```json
{
  "schemaVersion": 1,
  "changes": [
    {
      "sequence": "c1",
      "kind": "COMMITTED_OPERATION",
      "operation": {
        "schemaVersion": 1,
        "operationId": "00000000-0000-4000-8000-000000000020",
        "originNodeId": "00000000-0000-4000-8000-000000000001",
        "entityId": "00000000-0000-4000-8000-000000000010",
        "timestamp": 1793721600000,
        "lamportClock": 1,
        "entityType": "MESSAGE",
        "action": "CREATE",
        "baseVersion": 0,
        "payload": {
          "text": "Offline iPhone integration test",
          "recipientNodeId": "00000000-0000-4000-8000-000000000002"
        }
      },
      "entityVersion": 1,
      "committedAt": 1793721602000
    }
  ],
  "nextCursor": "c1",
  "hasMore": false,
  "serverLamportClock": 2
}
```

## Open conflict

```json
{
  "schemaVersion": 1,
  "conflictId": "00000000-0000-4000-8000-000000000060",
  "entityId": "00000000-0000-4000-8000-000000000011",
  "baseVersion": 1,
  "revision": 1,
  "currentEntityVersion": 2,
  "status": "OPEN",
  "candidates": [
    {
      "operation": {
        "schemaVersion": 1,
        "operationId": "00000000-0000-4000-8000-000000000022",
        "originNodeId": "00000000-0000-4000-8000-000000000001",
        "entityId": "00000000-0000-4000-8000-000000000011",
        "timestamp": 1793721600000,
        "lamportClock": 2,
        "entityType": "ANNOUNCEMENT",
        "action": "UPDATE",
        "baseVersion": 1,
        "payload": {
          "text": "Library shelter open until 18:00."
        }
      }
    },
    {
      "operation": {
        "schemaVersion": 1,
        "operationId": "00000000-0000-4000-8000-000000000023",
        "originNodeId": "00000000-0000-4000-8000-000000000002",
        "entityId": "00000000-0000-4000-8000-000000000011",
        "timestamp": 1793721600000,
        "lamportClock": 2,
        "entityType": "ANNOUNCEMENT",
        "action": "UPDATE",
        "baseVersion": 1,
        "payload": {
          "text": "Shelter moved to the sports hall."
        }
      }
    }
  ]
}
```

## Conflict resolution request

```json
{
  "schemaVersion": 1,
  "operationId": "00000000-0000-4000-8000-000000000024",
  "resolverNodeId": "00000000-0000-4000-8000-000000000004",
  "selectedOperationId": "00000000-0000-4000-8000-000000000023",
  "expectedConflictRevision": 1,
  "expectedEntityVersion": 2,
  "timestamp": 1793721604000,
  "lamportClock": 5
}
```

## Conflict resolution response

```json
{
  "schemaVersion": 1,
  "resolutionOperationId": "00000000-0000-4000-8000-000000000024",
  "duplicate": false,
  "conflict": {
    "schemaVersion": 1,
    "conflictId": "00000000-0000-4000-8000-000000000060",
    "entityId": "00000000-0000-4000-8000-000000000011",
    "baseVersion": 1,
    "revision": 2,
    "currentEntityVersion": 3,
    "status": "RESOLVED",
    "candidates": [
      {
        "operation": {
          "schemaVersion": 1,
          "operationId": "00000000-0000-4000-8000-000000000022",
          "originNodeId": "00000000-0000-4000-8000-000000000001",
          "entityId": "00000000-0000-4000-8000-000000000011",
          "timestamp": 1793721600000,
          "lamportClock": 2,
          "entityType": "ANNOUNCEMENT",
          "action": "UPDATE",
          "baseVersion": 1,
          "payload": {
            "text": "Library shelter open until 18:00."
          }
        }
      },
      {
        "operation": {
          "schemaVersion": 1,
          "operationId": "00000000-0000-4000-8000-000000000023",
          "originNodeId": "00000000-0000-4000-8000-000000000002",
          "entityId": "00000000-0000-4000-8000-000000000011",
          "timestamp": 1793721600000,
          "lamportClock": 2,
          "entityType": "ANNOUNCEMENT",
          "action": "UPDATE",
          "baseVersion": 1,
          "payload": {
            "text": "Shelter moved to the sports hall."
          }
        }
      }
    ],
    "resolutionOperationId": "00000000-0000-4000-8000-000000000024",
    "selectedOperationId": "00000000-0000-4000-8000-000000000023"
  },
  "ack": {
    "schemaVersion": 1,
    "ackId": "00000000-0000-4000-8000-000000000043",
    "operationId": "00000000-0000-4000-8000-000000000024",
    "stage": "BACKEND_COMMITTED",
    "acknowledgingNodeId": "00000000-0000-4000-8000-000000000003",
    "timestamp": 1793721602000,
    "entityVersion": 3
  }
}
```

## Dashboard notification

```json
{
  "schemaVersion": 1,
  "type": "SYNC_NOTIFICATION",
  "eventId": "00000000-0000-4000-8000-000000000070",
  "timestamp": 1793721602000,
  "latestCursor": "c1"
}
```

## Dashboard snapshot

```json
{
  "schemaVersion": 1,
  "observedAt": 1793721603000,
  "nodes": [
    {
      "id": "00000000-0000-4000-8000-000000000001",
      "name": "iPhone A",
      "platform": "iOS",
      "role": "client",
      "status": "active",
      "lastSeen": 1793721602000,
      "battery": 70
    },
    {
      "id": "00000000-0000-4000-8000-000000000003",
      "name": "Backend gateway",
      "platform": "Server",
      "role": "gateway",
      "status": "active",
      "lastSeen": 1793721603000
    }
  ],
  "links": [],
  "operations": [
    {
      "id": "00000000-0000-4000-8000-000000000020",
      "origin": "00000000-0000-4000-8000-000000000001",
      "kind": "Message",
      "status": "synced",
      "createdAt": 1793721600000,
      "hops": 0,
      "delivery": {
        "localStoredAt": 1793721600000,
        "queuedAt": 1793721600000,
        "peerReceipts": [
          {
            "schemaVersion": 1,
            "ackId": "00000000-0000-4000-8000-000000000041",
            "operationId": "00000000-0000-4000-8000-000000000020",
            "stage": "PEER_STORED",
            "acknowledgingNodeId": "00000000-0000-4000-8000-000000000002",
            "timestamp": 1793721602000,
            "packetId": "00000000-0000-4000-8000-000000000030"
          }
        ],
        "relayAttempts": [],
        "backendReceipt": {
          "schemaVersion": 1,
          "ackId": "00000000-0000-4000-8000-000000000040",
          "operationId": "00000000-0000-4000-8000-000000000020",
          "stage": "BACKEND_COMMITTED",
          "acknowledgingNodeId": "00000000-0000-4000-8000-000000000003",
          "timestamp": 1793721602000,
          "entityVersion": 1
        },
        "recipientReceipts": []
      }
    }
  ],
  "alerts": [],
  "conflicts": [
    {
      "id": "00000000-0000-4000-8000-000000000060",
      "entity": "Campus shelter",
      "baseVersion": 1,
      "left": "Library shelter open until 18:00.",
      "right": "Shelter moved to the sports hall.",
      "leftNode": "iPhone A",
      "rightNode": "iPhone B",
      "revision": 1,
      "currentEntityVersion": 2,
      "candidateOperationIds": [
        "00000000-0000-4000-8000-000000000022",
        "00000000-0000-4000-8000-000000000023"
      ]
    }
  ],
  "gateways": [
    {
      "nodeId": "00000000-0000-4000-8000-000000000003",
      "reachable": true,
      "selected": true,
      "latency": 20
    }
  ],
  "events": [
    {
      "id": "00000000-0000-4000-8000-000000000071",
      "title": "Operation committed",
      "detail": "iPhone A operation stored once",
      "time": 1793721602000,
      "kind": "success"
    }
  ]
}
```

