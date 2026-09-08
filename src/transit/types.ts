export type AgencyId = 'bt' | 'iu';
export type Freshness = 'live' | 'stale' | 'unavailable';

export interface TransitRoute {
  agency: AgencyId;
  id: string;
  shortName: string;
  longName?: string;
  color?: string;
  textColor?: string;
  paths?: [number, number][][];
}

export interface TransitStop {
  agency: AgencyId;
  id: string;
  name: string;
  lat: number;
  lng: number;
  routeIds?: string[];
}

export interface TransitVehicle {
  agency: AgencyId;
  id: string;
  routeId?: string;
  tripId?: string;
  lat: number;
  lng: number;
  heading?: number;
  direction?: string;
  load?: number;
  capacity?: number;
  onSchedule?: number;
  nextStops?: { stopId: string; minutes: number }[];
  updatedAt: number;
  freshness: Freshness;
}

export interface TransitArrival {
  agency: AgencyId;
  routeId: string;
  stopId: string;
  vehicleId?: string;
  destination?: string;
  predictedArrival: number;
  updatedAt?: number;
  freshness: Freshness;
}

export interface SourceStatus {
  agency: AgencyId;
  ok: boolean;
  updatedAt: number;
  message?: string;
}

export interface TransitSnapshot {
  routes: TransitRoute[];
  stops: TransitStop[];
  vehicles: TransitVehicle[];
  sources: SourceStatus[];
  generatedAt: number;
}
