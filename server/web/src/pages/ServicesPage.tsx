import { Link } from 'react-router-dom';
import type { Catalog } from '../api/types';
import { CatalogGate } from '../components/CatalogGate';
import { CallLink, PreferToCall } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { barbersForService, categories, serviceDuration, servicePrice } from '../lib/catalog';
import { list, plural } from '../lib/format';

export function ServicesPage() {
  usePageMeta(
    'Services and prices',
    'Every service at Izzy Clipz Barbershop in Oceanside, with its price and how long it takes: haircuts, beard work, shaves, color and more.',
  );
  return (
    <>
      <header className="page-header container">
        <h1>Services and prices</h1>
        <p className="lead secondary">Every service on the menu, with its price and how long it takes. Each barber sets their own prices.</p>
        <PreferToCall className="page-header__call" />
      </header>
      <CatalogGate>{(catalog) => <ServicesMenu catalog={catalog} />}</CatalogGate>
    </>
  );
}

function ServicesMenu({ catalog }: { catalog: Catalog }) {
  const groups = categories(catalog);
  return (
    <div className="container services">
      <nav className="jump-links" aria-label="Service categories">
        <ul>
          {groups.map((group) => (
            <li key={group.anchor}>
              <a className="jump-link" href={`#${group.anchor}`}>
                {group.title}
              </a>
            </li>
          ))}
        </ul>
      </nav>
      {groups.map((group) => (
        <section key={group.anchor} id={group.anchor} className="service-section" aria-labelledby={`${group.anchor}-title`}>
          <div className="service-section__header">
            <h2 id={`${group.anchor}-title`} className="service-section__title">
              {group.title}
            </h2>
            <p className="secondary">{plural(group.services.length, 'service')}</p>
          </div>
          <ul className="service-list">
            {group.services.map((service) => {
              const barbers = barbersForService(catalog, service.id).map((b) => b.name);
              return (
                <li key={service.id} className="service-card">
                  <div className="service-card__main">
                    <h3 className="service-card__name">{service.name}</h3>
                    {service.description ? <p className="service-card__description">{service.description}</p> : null}
                    <p className="service-card__barbers secondary">
                      {barbers.length === 1 ? `Only ${barbers[0]} offers it.` : `With ${list(barbers, 'and')}.`}
                    </p>
                  </div>
                  <div className="service-card__side">
                    <p className="service-card__price">{servicePrice(catalog, service.id)}</p>
                    <p className="service-card__duration secondary">{serviceDuration(catalog, service.id)}</p>
                    <Link
                      className="button button--primary service-card__book"
                      to={`/book?service=${encodeURIComponent(service.id)}`}
                      aria-label={`Book ${service.name}`}
                    >
                      Book
                    </Link>
                  </div>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
      <div className="services__footnote">
        <p className="secondary">Prices are from the shop's booking menu and can differ by barber. You pay at the shop.</p>
        <p className="secondary">
          Don't see what you need? Call <CallLink className="inline-link nowrap" /> and the shop can tell you if they do it.
        </p>
      </div>
    </div>
  );
}
