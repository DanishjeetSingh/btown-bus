const base = process.env.TRANSIT_API_URL || 'http://localhost:3000';
const response = await fetch(`${base.replace(/\/$/, '')}/api/transit`);
if (!response.ok) throw new Error(`Tracker API returned ${response.status}`);
const data = await response.json();

for (const [id, label] of [['bt', 'Bloomington Transit'], ['iu', 'IU Campus Bus']]) {
  const stops = data.stops.filter((item) => item.agency === id);
  let arrivalStatus = 'unavailable';
  for (let index = 0; index < Math.min(stops.length, 64) && arrivalStatus !== 'working'; index += 8) {
    const candidates = stops.slice(index, index + 8).map((stop) => `${id}:${stop.id}`).join(',');
    const result = await fetch(`${base.replace(/\/$/, '')}/api/arrivals?stops=${encodeURIComponent(candidates)}`);
    const arrivals = result.ok ? (await result.json()).arrivals : [];
    if (arrivals.some((item) => item.source === 'realtime')) arrivalStatus = 'working';
  }
  console.log(label);
  console.log(`- routes: ${data.routes.filter((item) => item.agency === id).length}`);
  console.log(`- stops: ${stops.length}`);
  console.log(`- active vehicles: ${data.vehicles.filter((item) => item.agency === id).length}`);
  console.log(`- realtime arrivals: ${arrivalStatus}`);
  console.log('');
}
