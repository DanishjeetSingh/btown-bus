import type { AgencyId, TransitArrival, TransitRoute, TransitStop } from '@/src/transit/types';

export const routeKey = (agency: string, id: string) => `${agency}:${id}`;
export const stopKey = (stop: Pick<TransitStop, 'agency' | 'id'>) => `${stop.agency}:${stop.id}`;
export const agencyName = (agency: AgencyId) => agency === 'iu' ? 'IU Campus Bus' : 'Bloomington Transit';
export const agencyColor = (agency: AgencyId) => agency === 'iu' ? '#990000' : '#006298';

export function minutesUntil(time: number, now: number) {
  return Math.max(0, Math.ceil((time - now) / 60_000));
}

export function routeStyle(route: TransitRoute | undefined, agency: AgencyId) {
  const color = route?.color && /^#[0-9a-f]{3,8}$/i.test(route.color) ? route.color : agencyColor(agency);
  return { '--route': color, '--route-ink': readableInk(color) } as React.CSSProperties;
}

/** Black or white text, whichever reads better on the route color. */
function readableInk(hex: string) {
  const value = hex.replace('#', '');
  const full = value.length === 3 ? value.split('').map((char) => char + char).join('') : value.slice(0, 6);
  const [r, g, b] = [0, 2, 4].map((offset) => parseInt(full.slice(offset, offset + 2), 16) / 255)
    .map((channel) => channel <= .03928 ? channel / 12.92 : ((channel + .055) / 1.055) ** 2.4);
  return .2126 * r + .7152 * g + .0722 * b > .4 ? '#15130f' : '#ffffff';
}

export function arrivalsForStop(arrivals: TransitArrival[], stop: Pick<TransitStop, 'agency' | 'id'>) {
  return arrivals.filter((arrival) => arrival.agency === stop.agency && arrival.stopId === stop.id);
}

export function clockTime(time: number) {
  return new Date(time).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

/** Short clock time ("7:05a") for arrivals an hour or more away. */
export function shortClock(time: number) {
  const date = new Date(time);
  const hours = date.getHours();
  return `${hours % 12 || 12}:${String(date.getMinutes()).padStart(2, '0')}${hours < 12 ? 'a' : 'p'}`;
}
