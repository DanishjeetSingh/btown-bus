import type { TransitArrival, TransitRoute, TransitStop, TransitVehicle } from './types';

/** Typical walking pace, in meters per second. */
export const WALK_SPEED = 1.3;
/** Straight lines undercount real sidewalks; pad them a little. */
export const WALK_DETOUR = 1.25;
/** Extra time to cross the street and be at the curb before the bus. */
export const LEAVE_BUFFER_MS = 60_000;
/** How close counts as "at the stop", before GPS accuracy is added. */
export const AT_STOP_RADIUS = 40;

export type LatLng = [number, number];

export function distanceMeters(a: LatLng, b: LatLng) {
  const radians = (value: number) => value * Math.PI / 180;
  const dLat = radians(b[0] - a[0]); const dLng = radians(b[1] - a[1]);
  const value = Math.sin(dLat / 2) ** 2 + Math.cos(radians(a[0])) * Math.cos(radians(b[0])) * Math.sin(dLng / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

export function walkSeconds(distance: number) {
  return Math.round(distance * WALK_DETOUR / WALK_SPEED);
}

export function formatDistance(meters: number) {
  return meters < 160 ? `${Math.round(meters / 10) * 10} m` : `${(meters / 1609.344).toFixed(1)} mi`;
}

/** Within the stop radius, allowing for up to 40 m of reported GPS error. */
export function isAtStop(distance: number, accuracy = 0) {
  return distance <= AT_STOP_RADIUS + Math.min(Math.max(accuracy, 0), 40);
}

/**
 * Stops left before the bus reaches `targetStopId`, counting the target:
 * 1 means your stop is the bus's next stop. Routes are treated as loops.
 */
export function stopsAway(stopIds: string[] | undefined, nextStopId: string | undefined, targetStopId: string) {
  if (!stopIds?.length || !nextStopId) return undefined;
  const n = stopIds.length;
  let best: number | undefined;
  stopIds.forEach((from, i) => {
    if (from !== nextStopId) return;
    stopIds.forEach((to, j) => {
      if (to !== targetStopId) return;
      const gap = (j - i + n) % n;
      if (best == null || gap < best) best = gap;
    });
  });
  return best == null ? undefined : best + 1;
}

export type LeaveState = 'at-stop' | 'leave-now' | 'leave-soon' | 'too-late';
export type LeavePlan = { state: LeaveState; leaveAt: number; minutesUntilLeave: number; label: string };

export function leavePlan(busArrival: number, walkMs: number | undefined, now: number, atStop = false): LeavePlan | undefined {
  if (atStop) return { state: 'at-stop', leaveAt: now, minutesUntilLeave: 0, label: "You're at the stop" };
  if (walkMs == null) return undefined;
  const leaveAt = busArrival - walkMs - LEAVE_BUFFER_MS;
  const minutesUntilLeave = Math.floor((leaveAt - now) / 60_000);
  if (busArrival - walkMs < now) return { state: 'too-late', leaveAt, minutesUntilLeave, label: 'Too late to walk it' };
  if (minutesUntilLeave <= 1) return { state: 'leave-now', leaveAt, minutesUntilLeave, label: 'Leave now' };
  return { state: 'leave-soon', leaveAt, minutesUntilLeave, label: `Leave in ${minutesUntilLeave} min` };
}

export type TrackedTrip = { agency: TransitStop['agency']; routeId: string; stopId: string; vehicleId?: string; startedAt: number };

export type TripStatus = {
  arrival?: TransitArrival;
  vehicle?: TransitVehicle;
  stopsAway?: number;
  minutes?: number;
};

/** Follow the chosen bus while it is still predicted; otherwise the next bus on the route. */
export function resolveTrip(trip: TrackedTrip, arrivals: TransitArrival[], vehicles: TransitVehicle[], route: TransitRoute | undefined, now: number): TripStatus {
  const candidates = arrivals.filter((item) => item.agency === trip.agency && item.stopId === trip.stopId && item.routeId === trip.routeId);
  const arrival = candidates.find((item) => trip.vehicleId && item.vehicleId === trip.vehicleId) ?? candidates[0];
  const vehicle = arrival?.vehicleId ? vehicles.find((item) => item.agency === trip.agency && item.id === arrival.vehicleId) : undefined;
  return {
    arrival, vehicle,
    stopsAway: vehicle ? stopsAway(route?.stopIds, vehicle.nextStopId, trip.stopId) : undefined,
    minutes: arrival ? Math.max(0, Math.ceil((arrival.predictedArrival - now) / 60_000)) : undefined,
  };
}
