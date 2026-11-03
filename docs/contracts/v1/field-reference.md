# Field reference — v1 candidate

JSON Schema is authoritative. Every named object rejects unknown fields. All fields are required unless Optional says yes. $ref values name another entry below. OneOf variants are exclusive. See README for semantic checks (identity/authorization, uniqueness, clocks, hop sum, idempotence, cursor ordering, version guards) that schema alone cannot prove.

## UUID

```json
{
  "type": "string",
  "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
}
```

## Integer

```json
{
  "type": "integer",
  "minimum": 0,
  "maximum": 9007199254740991
}
```

## Cursor

```json
{
  "type": "string",
  "pattern": "^c[0-9]{1,20}$"
}
```

## MessagePayload

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| text | `{"type":"string","minLength":1,"maxLength":1024}` | no |
| recipientNodeId | `{"$ref":"#/$defs/UUID"}` | no |

## SOSPayload

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| text | `{"type":"string","minLength":1,"maxLength":1024}` | no |
| category | `{"enum":["ASSISTANCE","MEDICAL","SUPPLIES","OTHER"]}` | no |
| location | `{"type":"object","properties":{"label":{"type":"string","minLength":1,"maxLength":256},"latitude":{"type":"number","minimum":-90,"maximum":90},"longitude":{"type":"number","minimum":-180,"maximum":180}},"required":["label"],"additionalProperties":false,"dependentRequired":{"latitude":["longitude"],"longitude":["latitude"]}}` | no |

## AnnouncementPayload

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| text | `{"type":"string","minLength":1,"maxLength":1000}` | no |

## Operation

### Variant 1

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| operationId | `{"$ref":"#/$defs/UUID"}` | no |
| originNodeId | `{"$ref":"#/$defs/UUID"}` | no |
| entityId | `{"$ref":"#/$defs/UUID"}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |
| lamportClock | `{"$ref":"#/$defs/Integer"}` | no |
| entityType | `{"const":"MESSAGE"}` | no |
| action | `{"const":"CREATE"}` | no |
| baseVersion | `{"const":0}` | no |
| payload | `{"$ref":"#/$defs/MessagePayload"}` | no |

### Variant 2

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| operationId | `{"$ref":"#/$defs/UUID"}` | no |
| originNodeId | `{"$ref":"#/$defs/UUID"}` | no |
| entityId | `{"$ref":"#/$defs/UUID"}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |
| lamportClock | `{"$ref":"#/$defs/Integer"}` | no |
| entityType | `{"const":"SOS"}` | no |
| action | `{"const":"CREATE"}` | no |
| baseVersion | `{"const":0}` | no |
| payload | `{"$ref":"#/$defs/SOSPayload"}` | no |

### Variant 3

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| operationId | `{"$ref":"#/$defs/UUID"}` | no |
| originNodeId | `{"$ref":"#/$defs/UUID"}` | no |
| entityId | `{"$ref":"#/$defs/UUID"}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |
| lamportClock | `{"$ref":"#/$defs/Integer"}` | no |
| entityType | `{"const":"ANNOUNCEMENT"}` | no |
| action | `{"const":"CREATE"}` | no |
| baseVersion | `{"const":0}` | no |
| payload | `{"$ref":"#/$defs/AnnouncementPayload"}` | no |

### Variant 4

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| operationId | `{"$ref":"#/$defs/UUID"}` | no |
| originNodeId | `{"$ref":"#/$defs/UUID"}` | no |
| entityId | `{"$ref":"#/$defs/UUID"}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |
| lamportClock | `{"$ref":"#/$defs/Integer"}` | no |
| entityType | `{"const":"ANNOUNCEMENT"}` | no |
| action | `{"const":"UPDATE"}` | no |
| baseVersion | `{"type":"integer","minimum":1,"maximum":9007199254740991}` | no |
| payload | `{"$ref":"#/$defs/AnnouncementPayload"}` | no |

## Acknowledgment

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| ackId | `{"$ref":"#/$defs/UUID"}` | no |
| operationId | `{"$ref":"#/$defs/UUID"}` | no |
| stage | `{"enum":["PEER_STORED","BACKEND_COMMITTED","RECIPIENT_ACKNOWLEDGED"]}` | no |
| acknowledgingNodeId | `{"$ref":"#/$defs/UUID"}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |
| packetId | `{"$ref":"#/$defs/UUID"}` | yes |
| entityVersion | `{"type":"integer","minimum":1,"maximum":9007199254740991}` | yes |

Additional conditions:
```json
[
  {
    "if": {
      "properties": {
        "stage": {
          "const": "BACKEND_COMMITTED"
        }
      }
    },
    "then": {
      "required": [
        "entityVersion"
      ],
      "properties": {
        "entityVersion": {
          "type": "integer",
          "minimum": 1,
          "maximum": 9007199254740991
        }
      }
    }
  }
]
```

## Envelope

### Variant 1

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| version | `{"const":1}` | no |
| packetId | `{"$ref":"#/$defs/UUID"}` | no |
| sourceNodeId | `{"$ref":"#/$defs/UUID"}` | no |
| destinationNodeId | `{"anyOf":[{"$ref":"#/$defs/UUID"},{"const":"*"}]}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |
| ttl | `{"type":"integer","minimum":0,"maximum":8}` | no |
| hopCount | `{"type":"integer","minimum":0,"maximum":8}` | no |
| type | `{"const":"SYNC_OP"}` | no |
| payload | `{"$ref":"#/$defs/Operation"}` | no |

### Variant 2

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| version | `{"const":1}` | no |
| packetId | `{"$ref":"#/$defs/UUID"}` | no |
| sourceNodeId | `{"$ref":"#/$defs/UUID"}` | no |
| destinationNodeId | `{"anyOf":[{"$ref":"#/$defs/UUID"},{"const":"*"}]}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |
| ttl | `{"type":"integer","minimum":0,"maximum":8}` | no |
| hopCount | `{"type":"integer","minimum":0,"maximum":8}` | no |
| type | `{"const":"ACK"}` | no |
| payload | `{"$ref":"#/$defs/Acknowledgment"}` | no |

## Error

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| code | `{"enum":["VALIDATION_ERROR","UNAUTHORIZED","FORBIDDEN","ID_REUSE","STALE_RESOLUTION","CURSOR_EXPIRED","UNSUPPORTED_VERSION","TOO_LARGE","TEMPORARY_FAILURE","ENTITY_NOT_FOUND"]}` | no |
| message | `{"type":"string","minLength":1,"maxLength":512}` | no |
| retryable | `{"type":"boolean"}` | no |

## ErrorResponse

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| error | `{"$ref":"#/$defs/Error"}` | no |

## PushRequest

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| nodeId | `{"$ref":"#/$defs/UUID"}` | no |
| operations | `{"type":"array","items":{"$ref":"#/$defs/Operation"},"minItems":1,"maxItems":100}` | no |

## PushResult

### Variant 1

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| operationId | `{"$ref":"#/$defs/UUID"}` | no |
| outcome | `{"const":"COMMITTED"}` | no |
| duplicate | `{"type":"boolean"}` | no |
| entityVersion | `{"type":"integer","minimum":1,"maximum":9007199254740991}` | no |
| ack | `{"$ref":"#/$defs/Acknowledgment"}` | no |

### Variant 2

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| operationId | `{"$ref":"#/$defs/UUID"}` | no |
| outcome | `{"const":"CONFLICT"}` | no |
| duplicate | `{"type":"boolean"}` | no |
| conflictId | `{"$ref":"#/$defs/UUID"}` | no |

### Variant 3

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| operationId | `{"$ref":"#/$defs/UUID"}` | no |
| outcome | `{"const":"REJECTED"}` | no |
| error | `{"$ref":"#/$defs/Error"}` | no |

## PushResponse

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| requestId | `{"$ref":"#/$defs/UUID"}` | no |
| results | `{"type":"array","items":{"$ref":"#/$defs/PushResult"},"maxItems":100}` | no |
| serverLamportClock | `{"$ref":"#/$defs/Integer"}` | no |

## Change

### Variant 1

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| sequence | `{"$ref":"#/$defs/Cursor"}` | no |
| kind | `{"const":"COMMITTED_OPERATION"}` | no |
| operation | `{"$ref":"#/$defs/Operation"}` | no |
| entityVersion | `{"type":"integer","minimum":1,"maximum":9007199254740991}` | no |
| committedAt | `{"$ref":"#/$defs/Integer"}` | no |

### Variant 2

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| sequence | `{"$ref":"#/$defs/Cursor"}` | no |
| kind | `{"const":"CONFLICT_CHANGED"}` | no |
| conflictId | `{"$ref":"#/$defs/UUID"}` | no |
| revision | `{"type":"integer","minimum":1}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |

### Variant 3

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| sequence | `{"$ref":"#/$defs/Cursor"}` | no |
| kind | `{"const":"ACKNOWLEDGMENT"}` | no |
| ack | `{"$ref":"#/$defs/Acknowledgment"}` | no |

## PullResponse

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| changes | `{"type":"array","items":{"$ref":"#/$defs/Change"},"maxItems":100}` | no |
| nextCursor | `{"$ref":"#/$defs/Cursor"}` | no |
| hasMore | `{"type":"boolean"}` | no |
| serverLamportClock | `{"$ref":"#/$defs/Integer"}` | no |

## Candidate

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| operation | `{"$ref":"#/$defs/Operation"}` | no |

## Conflict

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| conflictId | `{"$ref":"#/$defs/UUID"}` | no |
| entityId | `{"$ref":"#/$defs/UUID"}` | no |
| baseVersion | `{"$ref":"#/$defs/Integer"}` | no |
| revision | `{"type":"integer","minimum":1}` | no |
| currentEntityVersion | `{"type":"integer","minimum":1}` | no |
| status | `{"enum":["OPEN","RESOLVED"]}` | no |
| candidates | `{"type":"array","items":{"$ref":"#/$defs/Candidate"},"minItems":2,"maxItems":100}` | no |
| resolutionOperationId | `{"$ref":"#/$defs/UUID"}` | yes |
| selectedOperationId | `{"$ref":"#/$defs/UUID"}` | yes |

Additional conditions:
```json
[
  {
    "if": {
      "properties": {
        "status": {
          "const": "RESOLVED"
        }
      }
    },
    "then": {
      "required": [
        "resolutionOperationId",
        "selectedOperationId"
      ],
      "properties": {
        "resolutionOperationId": {
          "$ref": "#/$defs/UUID"
        },
        "selectedOperationId": {
          "$ref": "#/$defs/UUID"
        }
      }
    }
  }
]
```

## ConflictList

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| conflicts | `{"type":"array","items":{"$ref":"#/$defs/Conflict"},"maxItems":100}` | no |
| nextCursor | `{"$ref":"#/$defs/Cursor"}` | no |
| hasMore | `{"type":"boolean"}` | no |

## ResolveRequest

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| operationId | `{"$ref":"#/$defs/UUID"}` | no |
| resolverNodeId | `{"$ref":"#/$defs/UUID"}` | no |
| selectedOperationId | `{"$ref":"#/$defs/UUID"}` | no |
| expectedConflictRevision | `{"type":"integer","minimum":1}` | no |
| expectedEntityVersion | `{"type":"integer","minimum":1}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |
| lamportClock | `{"$ref":"#/$defs/Integer"}` | no |

## ResolveResponse

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| resolutionOperationId | `{"$ref":"#/$defs/UUID"}` | no |
| duplicate | `{"type":"boolean"}` | no |
| conflict | `{"$ref":"#/$defs/Conflict"}` | no |
| ack | `{"$ref":"#/$defs/Acknowledgment"}` | no |

## Notification

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| type | `{"const":"SYNC_NOTIFICATION"}` | no |
| eventId | `{"$ref":"#/$defs/UUID"}` | no |
| timestamp | `{"$ref":"#/$defs/Integer"}` | no |
| latestCursor | `{"$ref":"#/$defs/Cursor"}` | no |

## ReceiptRequest

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| nodeId | `{"$ref":"#/$defs/UUID"}` | no |
| ack | `{"$ref":"#/$defs/Acknowledgment"}` | no |

## ReceiptResponse

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| acceptedAckId | `{"$ref":"#/$defs/UUID"}` | no |
| duplicate | `{"type":"boolean"}` | no |

## DeliveryEvidence

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| localStoredAt | `{"$ref":"#/$defs/Integer"}` | yes |
| queuedAt | `{"$ref":"#/$defs/Integer"}` | yes |
| peerReceipts | `{"type":"array","items":{"$ref":"#/$defs/Acknowledgment"},"maxItems":100}` | no |
| relayAttempts | `{"type":"array","maxItems":100,"items":{"type":"object","properties":{"packetId":{"$ref":"#/$defs/UUID"},"forwarderNodeId":{"$ref":"#/$defs/UUID"},"nextHopNodeId":{"$ref":"#/$defs/UUID"},"timestamp":{"$ref":"#/$defs/Integer"},"result":{"enum":["SENT","FAILED"]},"retryable":{"type":"boolean"}},"required":["packetId","forwarderNodeId","nextHopNodeId","timestamp","result","retryable"],"additionalProperties":false}}` | no |
| backendReceipt | `{"$ref":"#/$defs/Acknowledgment"}` | yes |
| recipientReceipts | `{"type":"array","items":{"$ref":"#/$defs/Acknowledgment"},"maxItems":100}` | no |
| lastAttemptError | `{"$ref":"#/$defs/Error"}` | yes |

## DashboardNode

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| id | `{"$ref":"#/$defs/UUID"}` | no |
| name | `{"type":"string","minLength":1,"maxLength":256}` | no |
| platform | `{"enum":["iOS","Android","Windows","macOS","Linux","Web","Server"]}` | no |
| role | `{"enum":["client","relay","gateway"]}` | no |
| status | `{"enum":["active","unreachable"]}` | no |
| lastSeen | `{"$ref":"#/$defs/Integer"}` | no |
| battery | `{"type":"number","minimum":0,"maximum":100}` | yes |

## DashboardOperation

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| id | `{"$ref":"#/$defs/UUID"}` | no |
| origin | `{"$ref":"#/$defs/UUID"}` | no |
| kind | `{"enum":["Message","SOS","Announcement"]}` | no |
| status | `{"enum":["queued","relayed","synced","conflict"]}` | no |
| createdAt | `{"$ref":"#/$defs/Integer"}` | no |
| hops | `{"type":"integer","minimum":0,"maximum":8}` | no |
| conflictId | `{"$ref":"#/$defs/UUID"}` | yes |
| delivery | `{"$ref":"#/$defs/DeliveryEvidence"}` | no |

## DashboardAlert

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| id | `{"$ref":"#/$defs/UUID"}` | no |
| title | `{"type":"string","minLength":1,"maxLength":1024}` | no |
| category | `{"type":"string","minLength":1,"maxLength":64}` | no |
| location | `{"type":"string","minLength":1,"maxLength":256}` | no |
| nodeId | `{"$ref":"#/$defs/UUID"}` | no |
| status | `{"enum":["new","acknowledged","resolved"]}` | no |
| createdAt | `{"$ref":"#/$defs/Integer"}` | no |

## DashboardConflict

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| id | `{"$ref":"#/$defs/UUID"}` | no |
| entity | `{"type":"string","minLength":1,"maxLength":256}` | no |
| baseVersion | `{"$ref":"#/$defs/Integer"}` | no |
| left | `{"type":"string","minLength":1,"maxLength":1000}` | no |
| right | `{"type":"string","minLength":1,"maxLength":1000}` | no |
| leftNode | `{"type":"string","minLength":1,"maxLength":256}` | no |
| rightNode | `{"type":"string","minLength":1,"maxLength":256}` | no |
| resolved | `{"enum":["left","right"]}` | yes |
| revision | `{"type":"integer","minimum":1}` | no |
| currentEntityVersion | `{"type":"integer","minimum":1}` | no |
| candidateOperationIds | `{"type":"array","items":{"$ref":"#/$defs/UUID"},"minItems":2,"maxItems":2}` | no |

## DashboardGateway

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| nodeId | `{"$ref":"#/$defs/UUID"}` | no |
| reachable | `{"type":"boolean"}` | no |
| selected | `{"type":"boolean"}` | no |
| latency | `{"type":"number","minimum":0}` | no |

## DashboardEvent

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| id | `{"$ref":"#/$defs/UUID"}` | no |
| title | `{"type":"string","minLength":1,"maxLength":256}` | no |
| detail | `{"type":"string","minLength":1,"maxLength":1024}` | no |
| time | `{"$ref":"#/$defs/Integer"}` | no |
| kind | `{"enum":["info","success","warning"]}` | no |

## DashboardSnapshot

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| observedAt | `{"$ref":"#/$defs/Integer"}` | no |
| nodes | `{"type":"array","items":{"$ref":"#/$defs/DashboardNode"},"maxItems":1000}` | no |
| links | `{"type":"array","maxItems":5000,"items":{"type":"object","properties":{"from":{"$ref":"#/$defs/UUID"},"to":{"$ref":"#/$defs/UUID"}},"required":["from","to"],"additionalProperties":false}}` | no |
| operations | `{"type":"array","items":{"$ref":"#/$defs/DashboardOperation"},"maxItems":100}` | no |
| alerts | `{"type":"array","items":{"$ref":"#/$defs/DashboardAlert"},"maxItems":100}` | no |
| conflicts | `{"type":"array","items":{"$ref":"#/$defs/DashboardConflict"},"maxItems":100}` | no |
| gateways | `{"type":"array","items":{"$ref":"#/$defs/DashboardGateway"},"maxItems":1000}` | no |
| events | `{"type":"array","items":{"$ref":"#/$defs/DashboardEvent"},"maxItems":100}` | no |

## Health

| Field | Exact schema/type | Optional |
| --- | --- | --- |
| schemaVersion | `{"const":1}` | no |
| status | `{"const":"ok"}` | no |

