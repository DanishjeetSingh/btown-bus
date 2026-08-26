const feeds = [
  ['Bloomington Transit', 'https://bloomingtontransit.etaspot.net/service.php'],
  ['IU Campus Bus', 'https://iucbs.etaspot.net/service.php'],
];

for (const [label, base] of feeds) {
  const request = async (service, params = '') => {
    const response = await fetch(`${base}?service=${service}${params}`);
    if (!response.ok) throw new Error(`${label} ${service} returned ${response.status}`);
    if (response.headers.get('access-control-allow-origin') !== '*') throw new Error(`${label} ${service} is not browser-readable`);
    return response.json();
  };
  const [routes, stops, vehicles] = await Promise.all([
    request('get_routes'), request('get_stops'), request('get_vehicles', '&includeETAData=1&orderedETAArray=1'),
  ]);
  const routeList = routes.get_routes ?? [];
  const stopList = stops.get_stops ?? [];
  const activeVehicles = (vehicles.get_vehicles ?? []).filter((vehicle) => vehicle.inService !== 0 && vehicle.lat && vehicle.lng);
  const candidateStop = stopList[0];
  const arrivals = candidateStop ? await request('get_stop_etas', `&stopIDs=${encodeURIComponent(candidateStop.id)}`) : { get_stop_etas: [] };
  console.log(label);
  console.log(`- routes: ${routeList.length}`);
  console.log(`- stops: ${new Set(stopList.map((stop) => String(stop.id))).size}`);
  console.log(`- active vehicles: ${activeVehicles.length}`);
  console.log(`- realtime arrivals: ${arrivals.get_stop_etas ? 'working' : 'unavailable'}`);
  console.log('- browser CORS: working');
  console.log('');
}
