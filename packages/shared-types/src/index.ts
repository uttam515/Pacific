/**
 * Shared Domain Entities across OFFGRID
 */

export type OperationType = 'CREATE' | 'UPDATE' | 'DELETE';
export type EntityType = 'MESSAGE' | 'SOS' | 'ANNOUNCEMENT' | 'FILE_METADATA';

export interface OperationRecord {
  operationId: string;
  entityType: EntityType;
  action: OperationType;
  timestamp: number;
  lamportClock: number;
  originNodeId: string;
  payloadJson: string;
  synced: boolean;
}

export interface NodeStatus {
  nodeId: string;
  displayName: string;
  hardwareType: 'IOS' | 'ANDROID' | 'SERVER' | 'WEB';
  lastSeen: number;
  isGateway: boolean;
  batteryLevel?: number;
}

export type { ContractV1 } from './contract-v1.js';
