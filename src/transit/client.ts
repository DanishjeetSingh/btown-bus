import { z } from 'zod';
import { realtimeFreshness } from './freshness';
import { decodePolyline } from './polyline';
import type { AgencyId, TransitArrival, TransitRoute, TransitSnapshot, TransitStop, TransitVehicle } from './types';

const FEEDS: Record<AgencyId, string> = {
  bt: 'https://bloomingtontransit.etaspot.net/service.php',
  iu: 'https://iucbs.etaspot.net/service.php',
};

const routeSchema = z.object({
  id: z.union([z.string(), z.number()]), name: z.string(), abbr: z.string(), color: z.string().optional(),
  stops: z.array(z.union([z.string(), z.number()])).default([]), encLine: z.string().optional(),
});
const stopSchema = z.object({ id: z.union([z.string(), z.number()]), name: z.string(), lat: z.coerce.number(), lng: z.coerce.number() });
const vehicleSchema = z.object({
  routeID: z.union([z.string(), z.number()]).optional(), equipmentID: z.union([z.string(), z.number()]),
  tripID: z.union([z.string(), z.number()]).nullable().optional(), lat: z.coerce.number(), lng: z.coerce.number(),
  h: z.coerce.number().optional(), receiveTime: z.coerce.number(), inService: z.coerce.number().optional(),
  direction: z.string().optional(), load: z.coerce.number().nullable().optional(), capacity: z.coerce.number().nullable().optional(),
  onSchedule: z.coerce.number().nullable().optional(),
  minutesToNextStops: z.array(z.object({ stopID: z.union([z.string(), z.number()]), minutes: z.coerce.number() })).default([]),
});
const etaSchema = z.object({
  stopID: z.union([z.string(), z.number()]), routeID: z.union([z.string(), z.number()]),
  equipmentID: z.union([z.string(), z.number()]).nullable().optional(), minutes: z.coerce.number(), direction: z.string().optional(),
});
const routesResponse = z.object({ get_routes: z.array(routeSchema) });
const stopsResponse = z.object({ get_stops: z.array(stopSchema) });
const vehiclesResponse = z.object({ get_vehicles: z.array(vehicleSchema) });
const arrivalsResponse = z.object({
  get_stop_etas: z.array(z.object({ id: z.union([z.string(), z.number()]), enRoute: z.array(etaSchema).default([]) })),
});
const staticAgencyData = new Map<AgencyId, Promise<Pick<TransitSnapshot, 'routes' | 'stops'>>>();

async function request<T>(agency: AgencyId, service: string, schema: z.ZodType<T>, params: Record<string, string> = {}) {
  const query = new URLSearchParams({ service, ...params });
  const response = await fetch(`${FEEDS[agency]}?${query}`, { headers: { accept: 'application/json' }, cache: 'no-store', signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error(`${agency.toUpperCase()} feed returned ${response.status}`);
  return schema.parse(await response.json());
}

function getAgencyStaticData(agency: AgencyId) {
  const cached = staticAgencyData.get(agency);
  if (cached) return cached;
  const pending = Promise.all([request(agency, 'get_routes', routesResponse), request(agency, 'get_stops', stopsResponse)]).then(([routeData, stopData]) => {
    const stopRoutes = new Map<string, string[]>();
    for (const route of routeData.get_routes) for (const rawStopId of route.stops) {
      const stopId = String(rawStopId);
      stopRoutes.set(stopId, [...(stopRoutes.get(stopId) ?? []), String(route.id)]);
    }
    const routes: TransitRoute[] = routeData.get_routes.map((route) => ({
      agency, id: String(route.id), shortName: route.abbr, longName: route.name,
      color: normalizeColor(route.color, agency === 'iu' ? '#990000' : '#006298'), textColor: '#ffffff',
      paths: route.encLine ? [decodePolyline(route.encLine)] : [],
    }));
    const stops: TransitStop[] = [...new Map(stopData.get_stops.map((stop) => [String(stop.id), {
      agency, id: String(stop.id), name: stop.name, lat: stop.lat, lng: stop.lng, routeIds: stopRoutes.get(String(stop.id)) ?? [],
    }])).values()];
    return { routes, stops };
  });
  staticAgencyData.set(agency, pending);
  void pending.catch(() => { if (staticAgencyData.get(agency) === pending) staticAgencyData.delete(agency); });
  return pending;
}

async function getAgencySnapshot(agency: AgencyId): Promise<TransitSnapshot> {
  const [staticData, vehicleData] = await Promise.all([
    getAgencyStaticData(agency), request(agency, 'get_vehicles', vehiclesResponse, { includeETAData: '1', orderedETAArray: '1' }),
  ]);
  const vehicles: TransitVehicle[] = vehicleData.get_vehicles
    .filter((vehicle) => vehicle.inService !== 0 && vehicle.lat !== 0 && vehicle.lng !== 0)
    .map((vehicle) => ({
      agency, id: String(vehicle.equipmentID), routeId: vehicle.routeID == null ? undefined : String(vehicle.routeID),
      tripId: vehicle.tripID == null ? undefined : String(vehicle.tripID), lat: vehicle.lat, lng: vehicle.lng,
      heading: vehicle.h, updatedAt: vehicle.receiveTime, freshness: realtimeFreshness(vehicle.receiveTime),
      direction: vehicle.direction?.trim() || undefined,
      load: vehicle.load ?? undefined,
      capacity: vehicle.capacity && vehicle.capacity > 0 ? vehicle.capacity : undefined,
      onSchedule: vehicle.onSchedule ?? undefined,
      nextStops: vehicle.minutesToNextStops.slice(0, 3).map((stop) => ({ stopId: String(stop.stopID), minutes: stop.minutes })),
    }));
  return {
    routes: staticData.routes, stops: staticData.stops, vehicles, generatedAt: Date.now(),
    sources: [{ agency, ok: true, updatedAt: Math.max(...vehicles.map((vehicle) => vehicle.updatedAt), Date.now()) }],
  };
}

export async function getClientSnapshot(): Promise<TransitSnapshot> {
  const agencies: AgencyId[] = ['bt', 'iu'];
  const results = await Promise.allSettled(agencies.map(getAgencySnapshot));
  const good = results.flatMap((result) => result.status === 'fulfilled' ? [result.value] : []);
  return {
    routes: good.flatMap((item) => item.routes), stops: good.flatMap((item) => item.stops),
    vehicles: good.flatMap((item) => item.vehicles), generatedAt: Date.now(),
    sources: results.flatMap((result, index) => result.status === 'fulfilled' ? result.value.sources : [{ agency: agencies[index], ok: false, updatedAt: Date.now(), message: 'Public feed unavailable' }]),
  };
}

export async function getClientArrivals(stops: { agency: AgencyId; id: string }[]): Promise<TransitArrival[]> {
  const now = Date.now();
  const tasks = (['bt', 'iu'] as AgencyId[]).flatMap((agency) => {
    const ids = stops.filter((stop) => stop.agency === agency).map((stop) => stop.id);
    if (!ids.length) return [];
    return [request(agency, 'get_stop_etas', arrivalsResponse, { stopIDs: ids.join(',') }).then((data) =>
      data.get_stop_etas.flatMap((stop) => stop.enRoute.map((eta) => ({
        agency, routeId: String(eta.routeID), stopId: String(eta.stopID || stop.id),
        vehicleId: eta.equipmentID == null ? undefined : String(eta.equipmentID), destination: eta.direction,
        predictedArrival: now + Math.max(0, eta.minutes) * 60_000,
        updatedAt: now, freshness: 'live' as const,
      }))))];
  });
  const results = await Promise.allSettled(tasks);
  if (results.length && results.every((result) => result.status === 'rejected')) {
    throw new Error('All requested arrival feeds are unavailable');
  }
  return results.flatMap((result) => result.status === 'fulfilled' ? result.value : []).sort((a, b) => a.predictedArrival - b.predictedArrival);
}

function normalizeColor(value: string | undefined, fallback: string) {
  if (!value) return fallback;
  return value.startsWith('#') ? value : `#${value}`;
}
