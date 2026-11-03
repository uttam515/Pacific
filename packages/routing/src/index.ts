/**
 * Routing and peer table interfaces
 */

export interface PeerRoute {
  destinationNodeId: string;
  nextHopNodeId: string;
  hopCount: number;
  metric: number;
  expiresAt: number;
}

export interface RouteTable {
  routes: Map<string, PeerRoute>;
}
