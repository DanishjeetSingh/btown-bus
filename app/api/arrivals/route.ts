import { getTransitArrivals } from '@/src/server/transit';
import type { AgencyId } from '@/src/transit/types';

export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const raw = new URL(request.url).searchParams.get('stops') || '';
  const stops = raw.split(',').slice(0, 8).flatMap((item) => {
    const [agency, ...id] = item.split(':');
    return (agency === 'bt' || agency === 'iu') && id.length ? [{ agency: agency as AgencyId, id: id.join(':') }] : [];
  });
  if (!stops.length) return Response.json({ arrivals: [] });
  return Response.json({ arrivals: await getTransitArrivals(stops), generatedAt: Date.now() },
    { headers: { 'cache-control': 'public, max-age=10, stale-while-revalidate=20' } });
}
