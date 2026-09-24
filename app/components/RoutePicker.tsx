import type { AgencyId, TransitRoute } from '@/src/transit/types';
import { agencyName, routeKey, routeStyle } from '../lib/ui';
import { CloseIcon } from './icons';

type Props = {
  routes: TransitRoute[];
  active: Set<string>;
  onToggle: (route: TransitRoute) => void;
  onSetAgency: (agency: AgencyId, on: boolean) => void;
  onClose: () => void;
};

export default function RoutePicker({ routes, active, onToggle, onSetAgency, onClose }: Props) {
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <section className="route-picker" role="dialog" aria-modal="true" aria-labelledby="route-picker-title" onClick={(event) => event.stopPropagation()}>
        <header>
          <div><h2 id="route-picker-title">Your routes</h2><p>Picked routes show up on the map and in Nearby. Saved on this device.</p></div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close routes"><CloseIcon /></button>
        </header>
        {(['iu', 'bt'] as AgencyId[]).map((agency) => {
          const list = routes.filter((route) => route.agency === agency);
          if (!list.length) return null;
          const allOn = list.every((route) => active.has(routeKey(route.agency, route.id)));
          return <div className="agency-group" key={agency}>
            <div className="agency-head"><h3><i className={`agency-dot ${agency}`} />{agencyName(agency)}</h3><button type="button" onClick={() => onSetAgency(agency, !allOn)}>{allOn ? 'None' : 'All'}</button></div>
            <div className="route-grid">{list.map((route) => {
              const on = active.has(routeKey(route.agency, route.id));
              return <button key={route.id} type="button" className={`route-toggle ${on ? 'on' : ''}`} aria-pressed={on} style={routeStyle(route, route.agency)} onClick={() => onToggle(route)}>
                <b>{route.shortName.trim()}</b><span>{route.longName?.replace(/^_/, '') || ''}</span>
              </button>;
            })}</div>
          </div>;
        })}
        <button className="primary-button" type="button" onClick={onClose}>Done</button>
      </section>
    </div>
  );
}
