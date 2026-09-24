import assert from 'node:assert/strict';
import { test } from 'node:test';
import { isAtStop, leavePlan, resolveTrip, stopsAway } from '../src/transit/trip.ts';

const loop = ['42', '43', '44', '45', '46', '47'];

test('stops away counts forward along the route, including the target', () => {
  assert.equal(stopsAway(loop, '44', '44'), 1);
  assert.equal(stopsAway(loop, '43', '47'), 5);
  // Loops wrap around past the end of the list.
  assert.equal(stopsAway(loop, '46', '43'), 4);
  assert.equal(stopsAway(loop, '99', '43'), undefined);
  assert.equal(stopsAway(undefined, '42', '43'), undefined);
});

test('stops away picks the nearest occurrence when a stop repeats', () => {
  assert.equal(stopsAway(['1', '2', '3', '2', '4'], '3', '2'), 2);
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
  const vehicles = [{ agency: 'iu', id: '668', nextStopId: '43', lat: 0, lng: 0, updatedAt: 0, freshness: 'live' }];
  const route = { agency: 'iu', id: '32', shortName: 'B', stopIds: loop };
  const followed = resolveTrip(trip, arrivals, vehicles, route, 0);
  assert.equal(followed.arrival.vehicleId, '668');
  assert.equal(followed.stopsAway, 3);
  assert.equal(followed.minutes, 5);
  assert.equal(resolveTrip(trip, arrivals.slice(0, 1), vehicles, route, 0).arrival.vehicleId, '667');
});
