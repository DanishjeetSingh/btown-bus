type IconProps = { className?: string };
const base = { viewBox: '0 0 24 24', 'aria-hidden': true, fill: 'none', stroke: 'currentColor', strokeWidth: 2.4, strokeLinecap: 'round', strokeLinejoin: 'round' } as const;

export function StarIcon({ className, filled }: IconProps & { filled?: boolean }) {
  return <svg {...base} className={className} fill={filled ? 'currentColor' : 'none'}><path d="m12 3 2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 16.8l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8Z" /></svg>;
}
export function NearbyIcon({ className }: IconProps) {
  return <svg {...base} className={className}><path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11Z" /><circle cx="12" cy="10" r="2.4" /></svg>;
}
export function MapIcon({ className }: IconProps) {
  return <svg {...base} className={className}><path d="m9 4-5 2v14l5-2 6 2 5-2V4l-5 2-6-2Zm0 0v14m6-12v14" /></svg>;
}
export function LocateIcon({ className }: IconProps) {
  return <svg {...base} className={className}><circle cx="12" cy="12" r="5.5" /><path d="M12 2v3M12 19v3M2 12h3M19 12h3" /><circle cx="12" cy="12" r="1.4" fill="currentColor" /></svg>;
}
export function FitIcon({ className }: IconProps) {
  return <svg {...base} className={className}><path d="M8 4H4v4M16 4h4v4M20 16v4h-4M8 20H4v-4" /></svg>;
}
export function CloseIcon({ className }: IconProps) {
  return <svg {...base} className={className}><path d="M6 6l12 12M18 6 6 18" /></svg>;
}
export function WalkIcon({ className }: IconProps) {
  return <svg {...base} className={className}><circle cx="13" cy="4.5" r="1.8" fill="currentColor" stroke="none" /><path d="m10 21 2-6 3 3v3M8 12l2.5-4 3.5 1 2 3.5M10.5 8 9 14" /></svg>;
}
export function BusIcon({ className }: IconProps) {
  return <svg {...base} className={className}><rect x="5" y="3" width="14" height="15" rx="3" /><path d="M5 11h14M8 21v-3M16 21v-3" /><circle cx="8.5" cy="14.5" r=".6" fill="currentColor" /><circle cx="15.5" cy="14.5" r=".6" fill="currentColor" /></svg>;
}
export function RouteIcon({ className }: IconProps) {
  return <svg {...base} className={className}><circle cx="6" cy="6" r="2.5" /><circle cx="18" cy="18" r="2.5" /><path d="M8.5 6H15a3 3 0 0 1 0 6H9a3 3 0 0 0 0 6h6.5" /></svg>;
}
export function PinIcon({ className }: IconProps) {
  return <svg {...base} className={className}><path d="M12 3v4m0 0a5 5 0 1 1 0 10 5 5 0 0 1 0-10Zm0 10v8" /></svg>;
}
export function ChevronIcon({ className }: IconProps) {
  return <svg {...base} className={className}><path d="m9 6 6 6-6 6" /></svg>;
}
export function PeopleIcon({ className }: IconProps) {
  return <svg className={className} viewBox="0 0 24 24" role="img" aria-label="Occupancy"><circle cx="9" cy="8" r="3" fill="currentColor" /><circle cx="16.5" cy="8.5" r="2.5" fill="currentColor" opacity=".8" /><path d="M3 19c0-3.2 2.7-5.5 6-5.5s6 2.3 6 5.5H3Zm11.5 0c0-1.7-.6-3.1-1.7-4.1 1-.9 2.3-1.4 3.7-1.4 2.5 0 4.5 1.7 4.5 4v1.5h-6.5Z" fill="currentColor" /></svg>;
}
