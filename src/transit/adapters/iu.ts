import { z } from 'zod';
import { realtimeFreshness } from '../freshness';
import { decodePolyline } from '../polyline';
import type { TransitArrival, TransitRoute, TransitSnapshot, TransitStop, TransitVehicle } from '../types';

const BASE = 'https://iucbs.etaspot.net/service.php';
const routeSchema = z.object({
  id: z.union([z.string(), z.number()]), name: z.string(), abbr: z.string(), color: z.string().optional(),
  stops: z.array(z.union([z.string(), z.number()])).default([]), encLine: z.string().optional(),
});
const stopSchema = z.object({
  id: z.union([z.string(), z.number()]), name: z.string(), lat: z.coerce.number(), lng: z.coerce.number(),
});
const vehicleSchema = z.object({
  routeID: z.union([z.string(), z.number()]).optional(), equipmentID: z.union([z.string(), z.number()]),
  tripID: z.union([z.string(), z.number()]).nullable().optional(), lat: z.coerce.number(), lng: z.coerce.number(),
  h: z.coerce.number().optional(), receiveTime: z.coerce.number(), inService: z.coerce.number().optional(),
});
const etaSchema = z.object({
  stopID: z.union([z.string(), z.number()]), routeID: z.union([z.string(), z.number()]),
  equipmentID: z.union([z.string(), z.number()]).nullable().optional(), minutes: z.coerce.number(),
  direction: z.string().optional(), schedule: z.string().optional(),
});

async function etaFetch<T>(service: string, schema: z.ZodType<T>, params: Record<string, string> = {}): Promise<T> {
  const query = new URLSearchParams({ service, ...params });
  const response = await fetch(`${BASE}?${query}`, { headers: { accept: 'application/json' } });
  if (!response.ok) throw new Error(`IU feed returned ${response.status}`);
  return schema.parse(await response.json());
}

const routesResponse = z.object({ get_routes: z.array(routeSchema) });
const stopsResponse = z.object({ get_stops: z.array(stopSchema) });
const vehiclesResponse = z.object({ get_vehicles: z.array(vehicleSchema) });

export async function getIuSnapshot(): Promise<TransitSnapshot> {
  const [routeData, stopData, vehicleData] = await Promise.all([
    etaFetch('get_routes', routesResponse),
    etaFetch('get_stops', stopsResponse),
    etaFetch('get_vehicles', vehiclesResponse, { includeETAData: '1', orderedETAArray: '1' }),
  ]);
  const stopRoutes = new Map<string, string[]>();
  for (const route of routeData.get_routes) {
    for (const stopId of route.stops) {
      const id = String(stopId);
      stopRoutes.set(id, [...(stopRoutes.get(id) ?? []), String(route.id)]);
    }
  }
  const routes: TransitRoute[] = routeData.get_routes.map((route) => ({
    agency: 'iu', id: String(route.id), shortName: route.abbr, longName: route.name,
    color: normalizeColor(route.color, '#990000'), textColor: '#ffffff',
    paths: route.encLine ? [decodePolyline(route.encLine)] : [],
  }));
  const stops: TransitStop[] = stopData.get_stops.map((stop) => ({
    agency: 'iu', id: String(stop.id), name: stop.name, lat: stop.lat, lng: stop.lng,
    routeIds: stopRoutes.get(String(stop.id)) ?? [],
  }));
  const vehicles: TransitVehicle[] = vehicleData.get_vehicles
    .filter((vehicle) => vehicle.inService !== 0 && vehicle.lat !== 0 && vehicle.lng !== 0)
    .map((vehicle) => ({
      agency: 'iu', id: String(vehicle.equipmentID), routeId: vehicle.routeID == null ? undefined : String(vehicle.routeID),
      tripId: vehicle.tripID == null ? undefined : String(vehicle.tripID), lat: vehicle.lat, lng: vehicle.lng,
      heading: vehicle.h, updatedAt: vehicle.receiveTime, freshness: realtimeFreshness(vehicle.receiveTime),
    }));
  return {
    routes, stops, vehicles, alerts: [], generatedAt: Date.now(),
    sources: [{ agency: 'iu', ok: true, updatedAt: Math.max(...vehicles.map((v) => v.updatedAt), Date.now()) }],
  };
}

const stopEtasResponse = z.object({
  get_stop_etas: z.array(z.object({ id: z.union([z.string(), z.number()]), enRoute: z.array(etaSchema).default([]) })),
});

export async function getIuArrivals(stopIds: string[]): Promise<TransitArrival[]> {
  const data = await etaFetch('get_stop_etas', stopEtasResponse, { stopIDs: stopIds.join(',') });
  const updatedAt = Date.now();
  return data.get_stop_etas.flatMap((stop) => stop.enRoute.map((eta) => ({
    agency: 'iu' as const, routeId: String(eta.routeID), stopId: String(eta.stopID || stop.id),
    vehicleId: eta.equipmentID == null ? undefined : String(eta.equipmentID),
    destination: eta.direction, predictedArrival: updatedAt + Math.max(0, eta.minutes) * 60_000,
    source: 'realtime' as const, updatedAt, freshness: 'live' as const,
  }))).sort((a, b) => a.predictedArrival - b.predictedArrival);
}

function normalizeColor(value: string | undefined, fallback: string) {
  if (!value) return fallback;
  return value.startsWith('#') ? value : `#${value}`;
}
