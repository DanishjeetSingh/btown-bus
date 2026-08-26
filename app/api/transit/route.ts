import { getTransitSnapshot } from '@/src/server/transit';

export const dynamic = 'force-dynamic';

export async function GET() {
  const data = await getTransitSnapshot();
  return Response.json(data, { headers: { 'cache-control': 'public, max-age=5, stale-while-revalidate=20' } });
}
