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
 * Stops left before the bus reaches `target`, counting the target (1 = it's the bus's next stop).
 * Undefined when the bus's position can't be pinned down; the arrival time is still shown.
 */
export function vehicleStopsAway(route: TransitRoute | undefined, vehicle: TransitVehicle, target: string) {
  const visits = upcomingVisits(route, vehicle);
  const index = visits?.indexOf(target) ?? -1;
  if (index >= 0) return index + 1;
  // The feed's short list can run past the end of the pattern data we have.
  const direct = vehicle.nextStops?.findIndex((stop) => stop.stopId === target) ?? -1;
  return direct >= 0 ? direct + 1 : undefined;
}

/**
 * The stops this bus will visit next, in order, starting with its next stop.
 *
 * The route's combined stop list mixes directions and branches, so it can't be used for this. Instead:
 * find the bus in its current pattern (a stop it passes twice is told apart by the stop it just left),
 * walk forward, wrap around loops, and carry on into the pattern its next trip runs. Every candidate must
 * agree with the feed's own list of next stops. Undefined if that leaves more than one answer.
 * Same rules as `TripMath.upcomingVisits` in the iOS app.
 */
export function upcomingVisits(route: TransitRoute | undefined, vehicle: TransitVehicle, limit = 80): string[] | undefined {
  const patterns = route?.patterns ?? [];
  const current = patterns.find((pattern) => pattern.id === vehicle.patternId);
  const onCurrent = current && visitsOn(current, patterns, vehicle, limit);
  if (onCurrent) return onCurrent;
  // The reported pattern can lag a turnaround. Accept exactly one other pattern that fits the live stops.
  if ((vehicle.nextStops?.length ?? 0) < 2) return undefined;
  const fits = patterns.filter((pattern) => pattern.id !== vehicle.patternId)
    .map((pattern) => visitsOn(pattern, patterns, vehicle, limit)).filter((visits): visits is string[] => Boolean(visits));
  return fits.length === 1 ? fits[0] : undefined;
}

type Pattern = NonNullable<TransitRoute['patterns']>[number];

function visitsOn(pattern: Pattern, patterns: Pattern[], vehicle: TransitVehicle, limit: number) {
  const live = vehicle.nextStops?.map((stop) => stop.stopId) ?? [];
  const next = vehicle.nextStopId ?? live[0];
  if (!next) return undefined;
  const stops = [...pattern.stopIds];
  if (pattern.loops && stops.length > 1 && stops[0] === stops.at(-1)) stops.pop();
  if (!stops.length) return undefined;

  let positions = stops.flatMap((stop, index) => stop === next ? [index] : []);
  if (vehicle.lastStopId) {
    const matching = positions.filter((index) => (index > 0 ? stops[index - 1] : pattern.loops ? stops.at(-1) : undefined) === vehicle.lastStopId);
    if (matching.length) positions = matching;
  }

  const results: string[][] = [];
  for (const index of positions) {
    let sequence: string[];
    if (pattern.loops) {
      const lap = [...stops.slice(index), ...stops.slice(0, index)];
      sequence = [...lap, ...lap];
    } else {
      sequence = stops.slice(index);
      // After the last stop, the bus starts its next trip: a pattern that begins where this one ends.
      const joins = patterns.filter((other) => other.id !== pattern.id && other.stopIds[0] === stops.at(-1))
        .map((other) => [...sequence, ...other.stopIds.slice(1)]).filter((joined) => agrees(joined, live));
      if (joins.length === 1) sequence = joins[0];
      else if (joins.length > 1) {
        // Several next trips fit; keep only the stops they share.
        let shared = 0;
        while (shared < joins[0].length && joins.every((joined) => joined[shared] === joins[0][shared])) shared++;
        if (shared > sequence.length) sequence = joins[0].slice(0, shared);
      }
    }
    if (agrees(sequence, live)) results.push(sequence.slice(0, limit));
  }
  const [first] = results;
  return first && results.every((result) => result.join() === first.join()) ? first : undefined;
}

/** The feed's next stops must match the start of the sequence (as far as the sequence goes). */
function agrees(sequence: string[], live: string[]) {
  return live.every((id, offset) => offset >= sequence.length || sequence[offset] === id);
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
    stopsAway: vehicle ? vehicleStopsAway(route, vehicle, trip.stopId) : undefined,
    minutes: arrival ? Math.max(0, Math.ceil((arrival.predictedArrival - now) / 60_000)) : undefined,
  };
}
