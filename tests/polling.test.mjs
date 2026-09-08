import assert from 'node:assert/strict';
import { test } from 'node:test';
import { startPolling } from '../src/transit/polling.ts';
import { realtimeFreshness } from '../src/transit/freshness.ts';

const flush = async () => { await Promise.resolve(); await Promise.resolve(); };

test('failed polls back off to a cap and successful empty results reset the delay', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let calls = 0;
  const stop = startPolling(async () => { calls++; return calls >= 4; }, { interval: 15, maxInterval: 60, isVisible: () => true });
  t.after(stop);
  for (const delay of [0, 30, 60, 60, 15]) {
    const before = calls;
    if (delay) { t.mock.timers.tick(delay - 1); await flush(); assert.equal(calls, before); }
    t.mock.timers.tick(delay ? 1 : 0); await flush();
    assert.equal(calls, before + 1);
  }
});

test('slow polls do not overlap and cleanup prevents late work from restarting polling', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let calls = 0, finish, signal;
  const stop = startPolling((currentSignal) => {
    signal = currentSignal; calls++;
    return new Promise((resolve) => { finish = resolve; });
  }, { interval: 15, isVisible: () => true });
  t.mock.timers.tick(0); await flush();
  t.mock.timers.tick(1000); await flush();
  assert.equal(calls, 1);
  stop(); assert.equal(signal.aborted, true);
  finish(true); await flush();
  t.mock.timers.tick(1000); await flush();
  assert.equal(calls, 1);
});

test('hidden pages skip requests and rejected requests can recover', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let visible = false, calls = 0;
  const stop = startPolling(async () => { calls++; if (calls === 1) throw Error('offline'); }, {
    interval: 25, maxInterval: 60, isVisible: () => visible,
  });
  t.after(stop);
  t.mock.timers.tick(0); await flush();
  assert.equal(calls, 0);
  visible = true;
  t.mock.timers.tick(25); await flush(); assert.equal(calls, 1);
  t.mock.timers.tick(49); await flush(); assert.equal(calls, 1);
  t.mock.timers.tick(1); await flush(); assert.equal(calls, 2);
  t.mock.timers.tick(25); await flush(); assert.equal(calls, 3);
});

test('cleanup before the initial tick cancels all work', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let calls = 0;
  const stop = startPolling(async () => { calls++; }, { interval: 15, isVisible: () => true });
  stop();
  t.mock.timers.tick(100); await flush();
  assert.equal(calls, 0);
});

test('unchanged data becomes stale as the clock advances', () => {
  const receivedAt = 1_700_000_000_000;
  assert.equal(realtimeFreshness(receivedAt, receivedAt + 90_000), 'live');
  assert.equal(realtimeFreshness(receivedAt, receivedAt + 90_001), 'stale');
  assert.equal(realtimeFreshness(undefined, receivedAt), 'unavailable');
});
