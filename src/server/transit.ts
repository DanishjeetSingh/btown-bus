import { getBtArrivals, getBtSnapshot } from '../transit/adapters/bt';
import { getIuArrivals, getIuSnapshot } from '../transit/adapters/iu';
import type { AgencyId, TransitArrival, TransitSnapshot } from '../transit/types';

let snapshotCache: { expires: number; value: Promise<TransitSnapshot> } | undefined;

export function getTransitSnapshot() {
  if (!snapshotCache || snapshotCache.expires < Date.now()) {
    snapshotCache = { expires: Date.now() + 12_000, value: buildSnapshot() };
  }
  return snapshotCache.value;
}

async function buildSnapshot(): Promise<TransitSnapshot> {
  const results = await Promise.allSettled([getBtSnapshot(), getIuSnapshot()]);
  const good = results.flatMap((result) => result.status === 'fulfilled' ? [result.value] : []);
  const agencies: AgencyId[] = ['bt', 'iu'];
  const sources = results.flatMap((result, index) => result.status === 'fulfilled'
    ? result.value.sources
    : [{ agency: agencies[index], ok: false, updatedAt: Date.now(), message: safeMessage(result.reason) }]);
  return {
    routes: good.flatMap((item) => item.routes), stops: good.flatMap((item) => item.stops),
    vehicles: good.flatMap((item) => item.vehicles), alerts: good.flatMap((item) => item.alerts),
    sources, generatedAt: Date.now(),
  };
}

export async function getTransitArrivals(requested: { agency: AgencyId; id: string }[]): Promise<TransitArrival[]> {
  const bt = requested.filter((stop) => stop.agency === 'bt').map((stop) => stop.id);
  const iu = requested.filter((stop) => stop.agency === 'iu').map((stop) => stop.id);
  const tasks: Promise<TransitArrival[]>[] = [];
  if (bt.length) tasks.push(getBtArrivals(bt));
  if (iu.length) tasks.push(getIuArrivals(iu));
  const results = await Promise.allSettled(tasks);
  return results.flatMap((result) => result.status === 'fulfilled' ? result.value : [])
    .sort((a, b) => a.predictedArrival - b.predictedArrival);
}

function safeMessage(reason: unknown) {
  return reason instanceof Error ? reason.message.replace(/https?:\/\/\S+/g, 'upstream service') : 'Upstream feed is unavailable';
}
