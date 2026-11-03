/**
 * Central API Server Entry Point Placeholder
 * Owned by Engineer 1.
 */
import { PacketType } from '@offgrid/protocol';
import type { NodeStatus } from '@offgrid/shared-types';

export function getApiStatus(): { status: string; timestamp: number } {
  return {
    status: 'OFFGRID API Server Ready',
    timestamp: Date.now()
  };
}

