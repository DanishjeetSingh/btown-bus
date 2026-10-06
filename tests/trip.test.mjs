import assert from 'node:assert/strict';
import { test } from 'node:test';
import { isAtStop, leavePlan, resolveTrip, upcomingVisits, vehicleStopsAway } from '../src/transit/trip.ts';

const loop = ['42', '43', '44', '45', '46', '47'];

const bus = (patternId, nextStopId, { last, upcoming = [] } = {}) =>
  ({ patternId, nextStopId, lastStopId: last, nextStops: upcoming.map((stopId) => ({ stopId, minutes: 1 })) });
const pattern = (id, stopIds, loops = false) => ({ id, name: id, stopIds, loops });

test('counts along the bus\'s own direction and into its next trip', () => {
  // Bloomington Transit style: one-way patterns; Outbound ends where Inbound begins.
  const route = { stopIds: ['a', 'b', 'c', 'd', 'end', 'hub'], patterns: [
    pattern('out', ['hub', 'a', 'b', 'end']), pattern('in', ['end', 'c', 'd', 'hub']),
  ] };
  assert.equal(vehicleStopsAway(route, bus('out', 'a'), 'b'), 2);
  assert.equal(vehicleStopsAway(route, bus('out', 'a'), 'a'), 1);
  assert.equal(vehicleStopsAway(route, bus('out', 'b'), 'd'), 4);
  assert.deepEqual(upcomingVisits(route, bus('out', 'b')), ['b', 'end', 'c', 'd', 'hub']);
  assert.equal(vehicleStopsAway(route, bus('out', 'end', { upcoming: ['end', 'c', 'd'] }), 'd'), 3);
  // The reported pattern lags a turnaround: the live stops only fit Inbound.
  assert.equal(vehicleStopsAway(route, bus('out', 'c', { upcoming: ['c', 'd'] }), 'hub'), 3);
  assert.equal(vehicleStopsAway(route, bus(undefined, 'a'), 'd'), undefined);
  assert.equal(vehicleStopsAway(undefined, bus(undefined, 'a', { upcoming: ['a', 'b'] }), 'b'), 2);
});

test('when two next trips fit, only their shared stops count', () => {
  const route = { stopIds: [], patterns: [
    pattern('out', ['hub', 'a', 'b', 'end']), pattern('in', ['end', 'c', 'd', 'hub']), pattern('in2', ['end', 'c', 'x']),
  ] };
  assert.equal(vehicleStopsAway(route, bus('out', 'b'), 'c'), 3);
  assert.equal(vehicleStopsAway(route, bus('out', 'b'), 'd'), undefined);
  assert.equal(vehicleStopsAway(route, bus('out', 'end', { upcoming: ['end', 'c', 'd'] }), 'd'), 3);
});

test('loops that pass a stop twice use the stop the bus just left', () => {
  const route = { stopIds: [], patterns: [pattern('loop', ['1', '2', '3', '1', '4', '5', '1'], true)] };
  assert.equal(vehicleStopsAway(route, bus('loop', '1', { last: '3' }), '5'), 3);
  assert.equal(vehicleStopsAway(route, bus('loop', '1', { last: '5' }), '5'), 6);
  assert.equal(vehicleStopsAway(route, bus('loop', '1'), '5'), undefined);
  assert.equal(vehicleStopsAway(route, bus('loop', '5'), '2'), 3);
});

test('at-stop allows for GPS accuracy but caps it', () => {
  assert.equal(isAtStop(35, 5), true);
  assert.equal(isAtStop(70, 35), true);
  assert.equal(isAtStop(90, 500), false);
});

test('leave plan counts back from the bus with walking time and a buffer', () => {
  const now = 0;
  assert.equal(leavePlan(10 * 60_000, 3 * 60_000, now).label, 'Leave in 6 min');
  assert.equal(leavePlan(4 * 60_000, 3 * 60_000, now).state, 'leave-now');
  assert.equal(leavePlan(2 * 60_000, 3 * 60_000, now).state, 'too-late');
  assert.equal(leavePlan(2 * 60_000, 3 * 60_000, now, true).state, 'at-stop');
  assert.equal(leavePlan(2 * 60_000, undefined, now), undefined);
});

test('a tracked trip follows its bus, then falls back to the next one on the route', () => {
  const trip = { agency: 'iu', routeId: '32', stopId: '45', vehicleId: '668', startedAt: 0 };
  const arrivals = [
    { agency: 'iu', routeId: '32', stopId: '45', vehicleId: '667', predictedArrival: 120_000, freshness: 'live' },
    { agency: 'iu', routeId: '32', stopId: '45', vehicleId: '668', predictedArrival: 300_000, freshness: 'live' },
  ];
  const vehicles = [{ agency: 'iu', id: '668', patternId: 'p', nextStopId: '43', lat: 0, lng: 0, updatedAt: 0, freshness: 'live' }];
  const route = { agency: 'iu', id: '32', shortName: 'B', stopIds: loop, patterns: [{ id: 'p', name: 'B', stopIds: loop, loops: true }] };
  const followed = resolveTrip(trip, arrivals, vehicles, route, 0);
  assert.equal(followed.arrival.vehicleId, '668');
  assert.equal(followed.stopsAway, 3);
  assert.equal(followed.minutes, 5);
  assert.equal(resolveTrip(trip, arrivals.slice(0, 1), vehicles, route, 0).arrival.vehicleId, '667');
});
