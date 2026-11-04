import { Link } from 'react-router-dom';
import type { Catalog } from '../api/types';
import { CatalogGate } from '../components/CatalogGate';
import { Icon } from '../components/Icon';
import { Monogram } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { monogramTone, offeringsForBarber, serviceById } from '../lib/catalog';
import { durationLabel } from '../lib/format';

export function BarbersPage() {
  usePageMeta('Barbers', 'Meet the barbers at Izzy Clipz Barbershop in Oceanside: Izzy, Carlos, Flowxbori, Cristian and Julian. Book with the one you like.');
  return (
    <>
      <header className="page-header container">
        <h1>Meet the barbers</h1>
        <p className="lead secondary">Five barbers, each with their own menu and prices. Book with the one you like, or with whoever is free first.</p>
      </header>
      <CatalogGate>{(catalog) => <BarberList catalog={catalog} />}</CatalogGate>
    </>
  );
}

function BarberList({ catalog }: { catalog: Catalog }) {
  return (
    <div className="container barbers">
      <ul className="barber-list">
        {catalog.barbers.map((barber) => {
          const offerings = offeringsForBarber(catalog, barber.id);
          return (
            <li key={barber.id} className="barber-card">
              <div className="barber-card__intro">
                <Monogram letters={barber.monogram} tone={monogramTone(catalog, barber.id)} size="large" />
                <div className="barber-card__who">
                  <p className="barber-card__title secondary">{barber.title}</p>
                  <h2 id={`barber-${barber.id}`} className="barber-card__name">
                    {barber.name}
                  </h2>
                </div>
              </div>
              <p className="barber-card__bio">{barber.bio}</p>
              {barber.specialties.length > 0 ? (
                <p className="barber-card__specialties">
                  <span className="barber-card__label">Specialties: </span>
                  {barber.specialties.join(' · ')}
                </p>
              ) : null}
              <div className="barber-card__menu">
                <h3 className="barber-card__menu-title">What {barber.name} offers</h3>
                <ul className="menu-lines">
                  {offerings.map((offering) => (
                    <li key={offering.id} className="menu-lines__row">
                      <span className="menu-lines__name">{serviceById(catalog, offering.serviceId)?.name ?? 'Appointment'}</span>
                      <span className="menu-lines__detail">
                        <span className="menu-lines__price">{offering.priceLabel}</span>
                        <span className="secondary"> · {durationLabel(offering.durationMinutes)}</span>
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
              <div className="barber-card__actions">
                <Link className="button button--primary" to={`/book?barber=${encodeURIComponent(barber.id)}`}>
                  Book with {barber.name}
                </Link>
                {barber.instagram ? (
                  <a className="more-link" href={barber.instagram.url}>
                    <Icon name="instagram" className="inline-icon" /> @{barber.instagram.handle}
                  </a>
                ) : null}
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
