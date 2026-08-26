'use client';

import { useEffect, useMemo } from 'react';
import L from 'leaflet';
import { CircleMarker, MapContainer, Marker, Polyline, Popup, TileLayer, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import type { TransitRoute, TransitStop, TransitVehicle } from '@/src/transit/types';

type Props = {
  routes: TransitRoute[];
  stops: TransitStop[];
  vehicles: TransitVehicle[];
  activeRoutes: Set<string>;
  position?: [number, number];
  onSelectStop: (stop: TransitStop) => void;
};

const key = (agency: string, id: string) => `${agency}:${id}`;

export default function TransitMap({ routes, stops, vehicles, activeRoutes, position, onSelectStop }: Props) {
  const routeMap = useMemo(() => new Map(routes.map((route) => [key(route.agency, route.id), route])), [routes]);
  const visible = (agency: string, routeId?: string) => Boolean(routeId && activeRoutes.has(key(agency, routeId)));
  return (
    <MapContainer center={[39.1699, -86.5258]} zoom={14} scrollWheelZoom className="transit-map" zoomControl={false}>
      <TileLayer attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
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
        return <Marker key={key(vehicle.agency, vehicle.id)} position={[vehicle.lat, vehicle.lng]} icon={vehicleIcon(route?.shortName || '•', vehicle.agency, vehicle.freshness)}>
          <Popup><strong>{vehicle.agency === 'iu' ? 'IU' : 'BT'} {route?.shortName || 'bus'}</strong><br />{vehicle.freshness === 'live' ? 'Live position' : 'Position may be stale'}</Popup>
        </Marker>;
      })}
      {position && <CircleMarker center={position} radius={8} pathOptions={{ color: '#fff', fillColor: '#cf3a26', fillOpacity: 1, weight: 3 }} />}
    </MapContainer>
  );
}

function Recenter({ position }: { position?: [number, number] }) {
  const map = useMap();
  useEffect(() => { if (position) map.flyTo(position, 15, { duration: .7 }); }, [map, position]);
  return null;
}

function vehicleIcon(label: string, agency: string, freshness: string) {
  return L.divIcon({
    className: '', iconSize: [42, 42], iconAnchor: [21, 21],
    html: `<div class="bus-marker ${agency} ${freshness}"><b>${escapeHtml(label)}</b><small>${agency.toUpperCase()}</small></div>`,
  });
}

function escapeHtml(value: string) { return value.replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char]!); }
