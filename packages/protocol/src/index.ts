/**
 * OFFGRID Wire Protocol Definitions
 * Canonical definitions maintained by Engineer 1.
 */

export enum PacketType {
  SOS = 'SOS',
  MESSAGE = 'MESSAGE',
  ACK = 'ACK',
  ANNOUNCEMENT = 'ANNOUNCEMENT',
  SYNC_OP = 'SYNC_OP',
  HEARTBEAT = 'HEARTBEAT'
}

export interface PacketEnvelope<T = unknown> {
  version: number;
  packetId: string;
  type: PacketType;
  sourceNodeId: string;
  destinationNodeId: string; // Broadcast: '*'
  timestamp: number;
  ttl: number;
  hopCount: number;
  payload: T;
  signature?: string;
}

export interface AckPayload {
  acknowledgedPacketId: string;
  receivingNodeId: string;
  timestamp: number;
}
