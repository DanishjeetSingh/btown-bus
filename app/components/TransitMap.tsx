'use client';

import { useEffect, useMemo } from 'react';
import L from 'leaflet';
import { maplibreGL } from '@maplibre/maplibre-gl-leaflet';
import { setWorkerUrl } from 'maplibre-gl';
import { CircleMarker, MapContainer, Marker, Polyline, Popup, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import type { TransitRoute, TransitStop, TransitVehicle } from '@/src/transit/types';

type Props = {
  routes: TransitRoute[];
  stops: TransitStop[];
  vehicles: TransitVehicle[];
  activeRoutes: Set<string>;
  position?: [number, number];
  expanded: boolean;
  onSelectStop: (stop: TransitStop) => void;
};

const key = (agency: string, id: string) => `${agency}:${id}`;

export default function TransitMap({ routes, stops, vehicles, activeRoutes, position, expanded, onSelectStop }: Props) {
  const routeMap = useMemo(() => new Map(routes.map((route) => [key(route.agency, route.id), route])), [routes]);
  const stopMap = useMemo(() => new Map(stops.map((stop) => [key(stop.agency, stop.id), stop])), [stops]);
  const visible = (agency: string, routeId?: string) => Boolean(routeId && activeRoutes.has(key(agency, routeId)));
  return (
    <MapContainer center={[39.1699, -86.5258]} zoom={14} scrollWheelZoom className="transit-map" zoomControl={false}>
      <SimpleBasemap />
      <ResizeMap expanded={expanded} />
      <Recenter position={position} />
      {routes.filter((route) => activeRoutes.has(key(route.agency, route.id))).flatMap((route) =>
        (route.paths ?? []).map((path, index) => <Polyline key={`${key(route.agency, route.id)}:${index}`} positions={path} pathOptions={{ color: route.color || '#315b50', weight: 4, opacity: .72 }} />))}
      {stops.filter((stop) => stop.routeIds?.some((id) => activeRoutes.has(key(stop.agency, id)))).map((stop) => (
        <CircleMarker key={key(stop.agency, stop.id)} center={[stop.lat, stop.lng]} radius={4} pathOptions={{ color: stop.agency === 'iu' ? '#990000' : '#006298', fillColor: '#fffdf7', fillOpacity: 1, weight: 2 }} eventHandlers={{ click: () => onSelectStop(stop) }}>
          <Popup><button className="popup-stop" type="button" onClick={() => onSelectStop(stop)}><strong>{stop.name}</strong><span>{stop.agency === 'iu' ? 'IU Campus Bus' : 'Bloomington Transit'} arrivals</span></button></Popup>
        </CircleMarker>
      ))}
      {vehicles.filter((vehicle) => visible(vehicle.agency, vehicle.routeId)).map((vehicle) => {
        const route = vehicle.routeId ? routeMap.get(key(vehicle.agency, vehicle.routeId)) : undefined;
        return <Marker key={key(vehicle.agency, vehicle.id)} position={[vehicle.lat, vehicle.lng]} icon={vehicleIcon(route?.shortName || '•', route?.color, vehicle.agency, vehicle.freshness, vehicle.heading)}>
          <Popup><VehiclePopup vehicle={vehicle} stopMap={stopMap} /></Popup>
        </Marker>;
      })}
      {position && <CircleMarker center={position} radius={8} pathOptions={{ color: '#fff', fillColor: '#cf3a26', fillOpacity: 1, weight: 3 }} />}
    </MapContainer>
  );
}

function ResizeMap({ expanded }: { expanded: boolean }) {
  const map = useMap();
  useEffect(() => {
    const frame = requestAnimationFrame(() => map.invalidateSize({ pan: false }));
    return () => cancelAnimationFrame(frame);
  }, [expanded, map]);
  return null;
}

function SimpleBasemap() {
  const map = useMap();
  useEffect(() => {
    setWorkerUrl('/maplibre-gl-worker.mjs');
    const attribution = '<a href="https://openfreemap.org/">OpenFreeMap</a> © <a href="https://openmaptiles.org/">OpenMapTiles</a> Data from <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';
    const layer = maplibreGL({
      style: 'https://tiles.openfreemap.org/styles/positron',
      attributionControl: false,
    }).addTo(map);
    map.attributionControl.addAttribution(attribution);

    return () => {
      map.attributionControl.removeAttribution(attribution);
      map.removeLayer(layer);
    };
  }, [map]);
  return null;
}

function Recenter({ position }: { position?: [number, number] }) {
  const map = useMap();
  useEffect(() => { if (position) map.flyTo(position, 15, { duration: .7 }); }, [map, position]);
  return null;
}

function VehiclePopup({ vehicle, stopMap }: { vehicle: TransitVehicle; stopMap: Map<string, TransitStop> }) {
  const occupancy = vehicle.load != null && vehicle.capacity != null
    ? Math.min(100, Math.max(0, (vehicle.load / vehicle.capacity) * 100))
    : undefined;
  const schedule = vehicle.onSchedule == null ? 'Unavailable' : scheduleLabel(vehicle.onSchedule);

  return <div className="vehicle-popup">
    <div className="vehicle-facts">
      <strong className="vehicle-direction">{vehicle.direction || 'Direction unavailable'}</strong>
      <span className="vehicle-fact vehicle-occupancy"><b>Occupancy</b>{occupancy == null ? <em>Unavailable</em> : <span className="occupancy-meter" role="progressbar" aria-label="Bus occupancy" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(occupancy)}><i style={{ width: `${occupancy}%` }} /></span>}</span>
      <span className="vehicle-fact"><b>Schedule</b><strong>{schedule}</strong></span>
    </div>
    {vehicle.nextStops?.length ? <div className="vehicle-next-stops"><b>Next stops</b><ol>{vehicle.nextStops.map((stop, index) => <li key={`${stop.stopId}:${index}`}><span>{stopMap.get(key(vehicle.agency, stop.stopId))?.name || 'Upcoming stop'}</span><em>{formatMinutes(stop.minutes)}</em></li>)}</ol></div> : <p className="vehicle-unavailable">Upcoming stops unavailable</p>}
    {vehicle.freshness !== 'live' && <p className="vehicle-unavailable">Position may be stale</p>}
  </div>;
}

function vehicleIcon(label: string, routeColor: string | undefined, agency: string, freshness: string, heading?: number) {
  const hasHeading = Number.isFinite(heading);
  const rotation = hasHeading ? ((heading! % 360) + 360) % 360 : 0;
  const labelOffset = 2;
  const labelX = -Math.sin(rotation * Math.PI / 180) * labelOffset;
  const labelY = Math.cos(rotation * Math.PI / 180) * labelOffset;
  const color = /^#[0-9a-f]{3,8}$/i.test(routeColor || '') ? routeColor : agency === 'iu' ? '#990000' : '#006298';
  return L.divIcon({
    className: '', iconSize: [46, 46], iconAnchor: [23, 23],
    html: `<div class="bus-marker ${agency} ${freshness} ${hasHeading ? 'has-heading' : 'no-heading'}">
      <span class="bus-body" style="--bus-color: ${color}; transform: rotate(${rotation}deg)"><span class="bus-windshield"></span><span class="bus-headlights"></span></span>
      <b style="transform: translate(${labelX.toFixed(2)}px, ${labelY.toFixed(2)}px)">${escapeHtml(label)}</b>
    </div>`,
  });
}

function scheduleLabel(value: number) {
  if (value >= 0) return 'On time';
  return Math.abs(value) <= 5 ? 'Slightly delayed' : 'Delayed';
}

function formatMinutes(value: number) { return value <= 0 ? 'Now' : `${value} min`; }

function escapeHtml(value: string) { return value.replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char]!); }
