import type { Catalog } from '../api/types';
import { LOGO, STOREFRONT } from '../assets/images';
import { CatalogGate } from '../components/CatalogGate';
import { useNow } from '../components/hooks';
import { Icon } from '../components/Icon';
import { Photo } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { openStatus, wallClock, weekRows } from '../lib/shopTime';

export function VisitPage() {
  usePageMeta('Visit', 'Izzy Clipz Barbershop, 1919 Mission Ave, Ste 105, Oceanside: hours, directions in Apple Maps or Google Maps, and the phone number.');
  return (
    <>
      <header className="page-header container">
        <h1>Visit the shop</h1>
        <p className="lead secondary">Walk-ins are welcome, and you can book online any time.</p>
      </header>
      <CatalogGate>{(catalog) => <VisitDetails catalog={catalog} />}</CatalogGate>
    </>
  );
}

function VisitDetails({ catalog }: { catalog: Catalog }) {
  const now = useNow();
  const shop = catalog.shop;
  const status = openStatus(catalog.hours, catalog.timeZone, now);
  const today = wallClock(now, catalog.timeZone).weekday;
  const rows = weekRows(catalog.hours, today);

  return (
    <div className="container visit">
      <div className="visit__top">
        <section className="visit__address card card--gray" aria-labelledby="address-title">
          <p className="eyebrow">{shop.fullName}</p>
          <h2 id="address-title" className="visit__street">
            {shop.address.street}
          </h2>
          <p className="visit__city">{[shop.address.unit, ...shop.address.lines.slice(1)].filter(Boolean).join(', ')}</p>
          <p className="visit__status" data-testid="visit-status">
            <span className={`status-dot${status.isOpen ? ' status-dot--open' : ''}`} aria-hidden="true" />
            {status.text}
          </p>
          <div className="visit__buttons">
            <a className="button button--primary button--block" href={shop.appleMapsDirectionsUrl}>
              <Icon name="pin" className="button__icon" /> Open in Apple Maps
            </a>
            <a className="button button--primary button--block" href={shop.googleMapsDirectionsUrl}>
              <Icon name="pin" className="button__icon" /> Open in Google Maps
            </a>
            <a className="button button--secondary button--block" href={`tel:${shop.phone.e164}`}>
              <Icon name="phone" className="button__icon" /> Call {shop.phone.display}
            </a>
          </div>
        </section>
        <div className="photo visit__photo">
          <Photo
            sources={STOREFRONT.sources}
            alt={STOREFRONT.alt}
            width={STOREFRONT.width}
            height={STOREFRONT.height}
            sizes="(min-width: 960px) 55vw, 100vw"
            eager
          />
          <span className="sticker visit__sticker" aria-hidden="true">
            <img src={LOGO.src} alt="" width={150} height={119} />
          </span>
        </div>
      </div>

      <div className="visit__details">
      <section className="visit__section" aria-labelledby="hours-title">
        <h2 id="hours-title" className="visit__heading">
          Hours
        </h2>
        <table className="hours-table">
          <caption className="visually-hidden">The shop's hours this week, Monday first</caption>
          <tbody>
            {rows.map((row) => (
              <tr key={row.weekday} className={row.isToday ? 'is-today' : undefined} aria-current={row.isToday ? 'date' : undefined}>
                <th scope="row">
                  {row.name}
                  {row.isToday ? <span className="badge hours-table__today">Today</span> : null}
                </th>
                <td className="tabular">{row.label}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="secondary">Pacific Time. Hours may change on holidays.</p>
      </section>

      <section className="visit__section" aria-labelledby="know-title">
        <h2 id="know-title" className="visit__heading">
          Good to know
        </h2>
        <dl className="know-list">
          <div className="know-list__row">
            <dt>What to expect</dt>
            <dd>{shop.highlights.join(' · ')}</dd>
          </div>
          <div className="know-list__row">
            <dt>Payment</dt>
            <dd>{shop.paymentMethods.join(' · ')}. You pay at the shop, never online.</dd>
          </div>
          <div className="know-list__row">
            <dt>Accessibility</dt>
            <dd>{shop.accessibility.join(' · ')}</dd>
          </div>
        </dl>
      </section>
      </div>

      <section className="visit__section visit__about" aria-labelledby="about-title">
        <h2 id="about-title" className="visit__heading">
          The shop
        </h2>
        {shop.about.map((paragraph) => (
          <p key={paragraph} className="lead">
            {paragraph}
          </p>
        ))}
        <p>
          <a className="more-link" href={shop.instagram.url}>
            <Icon name="instagram" className="inline-icon" /> Follow @{shop.instagram.handle} on Instagram
          </a>
        </p>
      </section>
    </div>
  );
}
