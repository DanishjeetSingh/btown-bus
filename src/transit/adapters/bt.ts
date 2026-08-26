import { parse } from 'csv-parse/sync';
import { unzipSync } from 'fflate';
import GtfsRealtimeBindings from 'gtfs-realtime-bindings';
import { realtimeFreshness, toMillis } from '../freshness';
import type { TransitAlert, TransitArrival, TransitRoute, TransitSnapshot, TransitStop, TransitVehicle } from '../types';

const BASE = 'https://s3.amazonaws.com/etatransit.gtfs/bloomingtontransit.etaspot.net';
const STATIC_TTL = 6 * 60 * 60_000;

type CsvRow = Record<string, string>;
type TripInfo = { routeId: string; headsign?: string; serviceId: string; shapeId?: string };
type StopTime = { tripId: string; seconds: number };
type BtStatic = {
  routes: TransitRoute[]; stops: TransitStop[]; trips: Map<string, TripInfo>;
  stopTimes: Map<string, StopTime[]>; stopTimesByTripStop: Map<string, number>;
  stopByTripSequence: Map<string, { stopId: string; seconds: number }>; loadedAt: number;
};

let staticCache: Promise<BtStatic> | undefined;

async function fetchBytes(path: string) {
  const response = await fetch(`${BASE}/${path}`, { headers: { accept: 'application/octet-stream' } });
  if (!response.ok) throw new Error(`BT ${path} returned ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

function rows(files: Record<string, Uint8Array>, name: string): CsvRow[] {
  const file = files[name];
  if (!file) return [];
  return parse(new TextDecoder().decode(file), { columns: true, skip_empty_lines: true, bom: true, relax_column_count: true });
}

async function loadStatic(): Promise<BtStatic> {
  if (!staticCache) staticCache = fetchBytes('gtfs.zip').then((zip) => buildStatic(unzipSync(zip)));
  const data = await staticCache;
  if (Date.now() - data.loadedAt > STATIC_TTL) {
    staticCache = fetchBytes('gtfs.zip').then((zip) => buildStatic(unzipSync(zip)));
    return staticCache;
  }
  return data;
}

function buildStatic(files: Record<string, Uint8Array>): BtStatic {
  const routeRows = rows(files, 'routes.txt');
  const stopRows = rows(files, 'stops.txt');
  const tripRows = rows(files, 'trips.txt');
  const stopTimeRows = rows(files, 'stop_times.txt');
  const shapeRows = rows(files, 'shapes.txt');
  const activeServices = getActiveServices(rows(files, 'calendar.txt'), rows(files, 'calendar_dates.txt'));
  const trips = new Map<string, TripInfo>();
  for (const trip of tripRows) trips.set(trip.trip_id, {
    routeId: trip.route_id, headsign: trip.trip_headsign || undefined, serviceId: trip.service_id, shapeId: trip.shape_id || undefined,
  });
  const activeTrips = new Set([...trips].filter(([, trip]) => activeServices.has(trip.serviceId)).map(([id]) => id));
  const stopTimes = new Map<string, StopTime[]>();
  const stopTimesByTripStop = new Map<string, number>();
  const stopByTripSequence = new Map<string, { stopId: string; seconds: number }>();
  const stopRoutes = new Map<string, Set<string>>();
  for (const row of stopTimeRows) {
    const trip = trips.get(row.trip_id);
    if (!trip) continue;
    if (!stopRoutes.has(row.stop_id)) stopRoutes.set(row.stop_id, new Set());
    stopRoutes.get(row.stop_id)!.add(trip.routeId);
    if (!activeTrips.has(row.trip_id)) continue;
    const seconds = parseGtfsTime(row.arrival_time || row.departure_time);
    if (seconds == null) continue;
    const item = { tripId: row.trip_id, seconds };
    stopTimes.set(row.stop_id, [...(stopTimes.get(row.stop_id) ?? []), item]);
    stopTimesByTripStop.set(`${row.trip_id}:${row.stop_id}`, seconds);
    stopByTripSequence.set(`${row.trip_id}:${row.stop_sequence}`, { stopId: row.stop_id, seconds });
  }
  const shapes = new Map<string, [number, number][]>();
  for (const row of shapeRows) {
    const points = shapes.get(row.shape_id) ?? [];
    points.push([Number(row.shape_pt_lat), Number(row.shape_pt_lon)]);
    shapes.set(row.shape_id, points);
  }
  const routeShapes = new Map<string, string[]>();
  for (const trip of trips.values()) {
    if (!trip.shapeId) continue;
    const ids = routeShapes.get(trip.routeId) ?? [];
    if (!ids.includes(trip.shapeId) && ids.length < 3) ids.push(trip.shapeId);
    routeShapes.set(trip.routeId, ids);
  }
  const routes: TransitRoute[] = routeRows.map((route) => ({
    agency: 'bt', id: route.route_id, shortName: route.route_short_name || route.route_id,
    longName: route.route_long_name || undefined, color: color(route.route_color, '#006298'),
    textColor: color(route.route_text_color, '#ffffff'),
    paths: (routeShapes.get(route.route_id) ?? []).map((id) => simplify(shapes.get(id) ?? [])),
  }));
  const stops: TransitStop[] = stopRows.map((stop) => ({
    agency: 'bt', id: stop.stop_id, name: stop.stop_name, lat: Number(stop.stop_lat), lng: Number(stop.stop_lon),
    routeIds: [...(stopRoutes.get(stop.stop_id) ?? [])],
  })).filter((stop) => Number.isFinite(stop.lat) && Number.isFinite(stop.lng));
  return { routes, stops, trips, stopTimes, stopTimesByTripStop, stopByTripSequence, loadedAt: Date.now() };
}

export async function getBtSnapshot(): Promise<TransitSnapshot> {
  const [staticData, positionBytes, alertBytes] = await Promise.all([
    loadStatic(), fetchBytes('position_updates.pb'), fetchBytes('alerts.pb'),
  ]);
  const positions = GtfsRealtimeBindings.transit_realtime.FeedMessage.decode(positionBytes);
  const feedUpdatedAt = toMillis(positions.header.timestamp) ?? Date.now();
  const vehicles: TransitVehicle[] = positions.entity.flatMap((entity) => {
    const vehicle = entity.vehicle;
    const position = vehicle?.position;
    if (!vehicle || !position || position.latitude == null || position.longitude == null) return [];
    const updatedAt = toMillis(vehicle.timestamp) ?? feedUpdatedAt;
    return [{ agency: 'bt' as const, id: vehicle.vehicle?.id || entity.id,
      routeId: vehicle.trip?.routeId || undefined, tripId: vehicle.trip?.tripId || undefined,
      lat: position.latitude, lng: position.longitude, heading: position.bearing ?? undefined,
      updatedAt, freshness: realtimeFreshness(updatedAt) }];
  });
  const alertsFeed = GtfsRealtimeBindings.transit_realtime.FeedMessage.decode(alertBytes);
  const alerts: TransitAlert[] = alertsFeed.entity.flatMap((entity) => {
    if (!entity.alert) return [];
    const description = translation(entity.alert.descriptionText) || translation(entity.alert.headerText);
    if (!description) return [];
    return [{ agency: 'bt' as const, id: entity.id, title: translation(entity.alert.headerText) || undefined, description,
      routeIds: entity.alert.informedEntity.map((item) => item.routeId).filter(Boolean) as string[],
      stopIds: entity.alert.informedEntity.map((item) => item.stopId).filter(Boolean) as string[] }];
  });
  return { routes: staticData.routes, stops: staticData.stops, vehicles, alerts, generatedAt: Date.now(),
    sources: [{ agency: 'bt', ok: true, updatedAt: feedUpdatedAt }] };
}

export async function getBtArrivals(stopIds: string[]): Promise<TransitArrival[]> {
  const [staticData, bytes] = await Promise.all([loadStatic(), fetchBytes('trip_updates.pb')]);
  const feed = GtfsRealtimeBindings.transit_realtime.FeedMessage.decode(bytes);
  const updatedAt = toMillis(feed.header.timestamp) ?? Date.now();
  const wanted = new Set(stopIds);
  const arrivals: TransitArrival[] = [];
  const seen = new Set<string>();
  for (const entity of feed.entity) {
    const update = entity.tripUpdate;
    const tripId = update?.trip?.tripId;
    if (!update || !tripId) continue;
    const trip = staticData.trips.get(tripId);
    for (const stopTime of update.stopTimeUpdate) {
      const sequenceInfo = stopTime.stopSequence == null ? undefined : staticData.stopByTripSequence.get(`${tripId}:${stopTime.stopSequence}`);
      const stopId = stopTime.stopId || sequenceInfo?.stopId;
      if (!stopId || !wanted.has(stopId)) continue;
      const scheduledSeconds = sequenceInfo?.seconds ?? staticData.stopTimesByTripStop.get(`${tripId}:${stopId}`);
      const scheduledArrival = scheduledSeconds == null ? undefined : localEpochForSeconds(scheduledSeconds);
      const suppliedArrival = [toMillis(stopTime.arrival?.time), toMillis(stopTime.departure?.time)].find((value) => value != null && value > 1_000_000_000_000);
      const predictedArrival = suppliedArrival ??
        (scheduledArrival != null && stopTime.arrival?.delay != null ? scheduledArrival + Number(stopTime.arrival.delay) * 1000 : undefined);
      if (!predictedArrival || predictedArrival < Date.now() - 60_000) continue;
      seen.add(`${tripId}:${stopId}`);
      arrivals.push({ agency: 'bt', routeId: update.trip?.routeId || trip?.routeId || '?', stopId, tripId,
        vehicleId: update.vehicle?.id || undefined, destination: trip?.headsign, predictedArrival, scheduledArrival,
        source: 'realtime', updatedAt, freshness: realtimeFreshness(updatedAt) });
    }
  }
  for (const stopId of stopIds) {
    for (const scheduled of staticData.stopTimes.get(stopId) ?? []) {
      if (seen.has(`${scheduled.tripId}:${stopId}`)) continue;
      const predictedArrival = localEpochForSeconds(scheduled.seconds);
      if (predictedArrival < Date.now() || predictedArrival > Date.now() + 90 * 60_000) continue;
      const trip = staticData.trips.get(scheduled.tripId);
      arrivals.push({ agency: 'bt', routeId: trip?.routeId || '?', stopId, tripId: scheduled.tripId,
        destination: trip?.headsign, predictedArrival, scheduledArrival: predictedArrival,
        source: 'scheduled', freshness: 'scheduled' });
    }
  }
  return arrivals.sort((a, b) => a.predictedArrival - b.predictedArrival).slice(0, 40);
}

function parseGtfsTime(value: string) {
  const match = /^(\d+):(\d+):(\d+)$/.exec(value);
  return match ? Number(match[1]) * 3600 + Number(match[2]) * 60 + Number(match[3]) : undefined;
}

function localEpochForSeconds(seconds: number) {
  const now = new Date();
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Indiana/Indianapolis', year: 'numeric', month: '2-digit', day: '2-digit', timeZoneName: 'longOffset' }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)?.value || '';
  const offset = /GMT([+-])(\d{2}):(\d{2})/.exec(get('timeZoneName'));
  const offsetMs = offset ? (offset[1] === '+' ? 1 : -1) * (Number(offset[2]) * 60 + Number(offset[3])) * 60_000 : 0;
  return Date.UTC(Number(get('year')), Number(get('month')) - 1, Number(get('day')), 0, 0, seconds) - offsetMs;
}

function getActiveServices(calendar: CsvRow[], exceptions: CsvRow[]) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Indiana/Indianapolis', year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'long' }).formatToParts(new Date());
  const get = (type: string) => parts.find((part) => part.type === type)?.value || '';
  const date = `${get('year')}${get('month')}${get('day')}`;
  const weekday = get('weekday').toLowerCase();
  const active = new Set(calendar.filter((row) => row.start_date <= date && row.end_date >= date && row[weekday] === '1').map((row) => row.service_id));
  for (const row of exceptions.filter((item) => item.date === date)) {
    if (row.exception_type === '1') active.add(row.service_id); else active.delete(row.service_id);
  }
  return active;
}

function simplify(points: [number, number][]) { return points.filter((_, index) => index % 4 === 0 || index === points.length - 1); }
function color(value: string, fallback: string) { return value ? (value.startsWith('#') ? value : `#${value}`) : fallback; }
function translation(text?: { translation?: { text?: string | null }[] | null } | null) { return text?.translation?.find((item) => item.text)?.text || ''; }
