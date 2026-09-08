import type { Freshness } from './types';

export function realtimeFreshness(updatedAt?: number, now = Date.now()): Freshness {
  if (!updatedAt) return 'unavailable';
  return now - updatedAt <= 90_000 ? 'live' : 'stale';
}
