import type { Freshness } from './types';

export function realtimeFreshness(updatedAt?: number, now = Date.now()): Freshness {
  if (!updatedAt) return 'unavailable';
  return now - updatedAt <= 90_000 ? 'live' : 'stale';
}

export function toMillis(value: unknown): number | undefined {
  if (value === null || value === undefined) return undefined;
  const number = Number(typeof value === 'object' && value && 'toString' in value ? value.toString() : value);
  if (!Number.isFinite(number)) return undefined;
  return number < 10_000_000_000 ? number * 1000 : number;
}
