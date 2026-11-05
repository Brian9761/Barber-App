import { useRef } from 'react';
import { Link } from 'react-router-dom';
import type { Catalog } from '../api/types';
import { STOREFRONT } from '../assets/images';
import { useNearScreen, useNow } from '../components/hooks';
import { Logo } from '../components/Logo';
import { DemoNotice } from '../demo/DemoNotice';
import { CallLink, Monogram, MoreLink, Photo, Stars } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { useCatalog } from '../data/catalog';
import { FALLBACK_SHOP } from '../data/fallback';
import { useReviews } from '../data/reviews';
import { monogramTone, servicePrice } from '../lib/catalog';
import { hoursSummary, openStatus } from '../lib/shopTime';

export function HomePage() {
  usePageMeta(
    'Izzy Clipz Barbershop in Oceanside',
    'Fresh cuts, booked in seconds. Pick your barber and a time online at Izzy Clipz Barbershop in Oceanside, and pay at the shop.',
  );
  const catalog = useCatalog();

  return (
    <>
      <section className="hero on-dark" aria-labelledby="hero-title">
        <div className="container hero__inner">
          {/* The shop's logo, white on the black hero. The headline and the line under it name the shop. */}
          <Logo height={132} className="hero__logo" />
          {/* While the hours load (or if they can't), the line keeps its place without showing an empty pill. */}
          {catalog ? <OpenToday catalog={catalog} /> : <p className="hero__status hero__status--waiting" aria-hidden="true">&nbsp;</p>}
          <h1 id="hero-title" className="hero__title">
            <span className="hero__line">Fresh cuts.</span> <span className="hero__line">Booked in seconds.</span>
          </h1>
          <p className="hero__lead">
            Izzy Clipz Barbershop in Oceanside. Pick your barber and a time online, and pay at the shop.
          </p>
          <div className="actions actions--center hero__actions">
            <Link className="button button--primary button--large" to="/book">
              Book an appointment
            </Link>
            <MoreLink to="/services" large>
              See services
            </MoreLink>
          </div>
          <DemoNotice onDark />
          <p className="hero__call">
            Prefer to call? <CallLink className="inline-link nowrap" />
          </p>
        </div>
        <div className="container container--wide hero__media">
          <div className="photo hero__photo hero__photo--wide">
            <Photo
              sources={STOREFRONT.sources}
              alt={STOREFRONT.alt}
              width={STOREFRONT.width}
              height={STOREFRONT.height}
              sizes="(min-width: 1100px) 1100px, 100vw"
              eager
            />
          </div>
        </div>
      </section>
      <div className="pole-stripe" aria-hidden="true" />

      {catalog ? <HomeTiles catalog={catalog} /> : null}


      <section className="band band--dark on-dark closing-band" aria-labelledby="ready-title">
        <div className="container closing-band__inner">
          <h2 id="ready-title">Ready for a fresh cut?</h2>
          <p className="lead closing-band__lead">Book online in about a minute. No payment needed. Walk-ins are welcome too.</p>
          <div className="actions actions--center">
            <Link className="button button--primary button--large" to="/book">
              Book an appointment
            </Link>
          </div>
          <p className="closing-band__call">
            Prefer to call? <CallLink className="inline-link nowrap" />
          </p>
        </div>
      </section>
    </>
  );
}

function OpenToday({ catalog }: { catalog: Catalog }) {
  const now = useNow();
  const status = openStatus(catalog.hours, catalog.timeZone, now);
  return (
    <p className="hero__status" data-testid="open-today">
      <span className={`status-dot${status.isOpen ? ' status-dot--open' : ''}`} aria-hidden="true" />
      {status.text}
    </p>
  );
}

function HomeTiles({ catalog }: { catalog: Catalog }) {
  const popular = catalog.services.filter((s) => s.popular);
  const now = useNow();
  const status = openStatus(catalog.hours, catalog.timeZone, now);
  return (
    <section className="home-tiles" aria-label="Explore the shop">
      <div className="container container--wide tile-grid">
        <article className="tile" aria-labelledby="tile-services">
          <h2 id="tile-services" className="tile__title">
            Services
          </h2>
          <p className="tile__text">Haircuts, beard work, shaves and color. Each barber sets their own prices.</p>
          <div className="actions actions--center tile__links">
            <MoreLink to="/services">See all services</MoreLink>
            <MoreLink to="/book">Book</MoreLink>
          </div>
          <div className="tile__body">
            <ul className="price-list" aria-label="Popular services">
              {popular.map((service) => (
                <li key={service.id} className="price-list__row">
                  <Link to={`/book?service=${encodeURIComponent(service.id)}`} className="price-list__link">
                    <span className="price-list__name">{service.name}</span>
                    <span className="price-list__price">{servicePrice(catalog, service.id)}</span>
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        </article>

        <article className="tile tile--dark on-dark" aria-labelledby="tile-barbers">
          <h2 id="tile-barbers" className="tile__title">
            Meet the barbers
          </h2>
          <p className="tile__text">Five barbers, each with their own menu. Pick one, or take whoever is free first.</p>
          <div className="actions actions--center tile__links">
            <MoreLink to="/barbers">Meet the barbers</MoreLink>
            <MoreLink to="/book">Book</MoreLink>
          </div>
          <div className="tile__body">
            <ul className="crew-row">
              {catalog.barbers.map((barber) => (
                <li key={barber.id} className="crew-row__item">
                  <Monogram letters={barber.monogram} tone={monogramTone(catalog, barber.id)} size="medium" />
                  <span className="crew-row__name">{barber.name}</span>
                </li>
              ))}
            </ul>
          </div>
        </article>

        <ReviewsTile />

        <article className="tile" aria-labelledby="tile-visit">
          <h2 id="tile-visit" className="tile__title">
            Visit the shop
          </h2>
          <p className="tile__text">
            {catalog.shop.address.lines.map((line) => (
              <span key={line} className="tile__line">
                {line}
              </span>
            ))}
          </p>
          <div className="actions actions--center tile__links">
            <MoreLink to="/visit">Hours and directions</MoreLink>
            <MoreLink href={`tel:${catalog.shop.phone.e164}`}>Call</MoreLink>
          </div>
          <div className="tile__body visit-tile">
            <p className="visit-tile__status">
              <span className={`status-dot${status.isOpen ? ' status-dot--open' : ''}`} aria-hidden="true" />
              {status.text}
            </p>
            <ul className="visit-tile__hours" aria-label="Hours">
              {hoursSummary(catalog.hours).map((line) => (
                <li key={line}>{line}</li>
              ))}
            </ul>
            <Logo height={120} className="visit-tile__logo" />
          </div>
        </article>
      </div>
    </section>
  );
}

/** The rating from Google (and Yelp), loaded when the tile comes near the screen; quiet when it can't be shown. */
function ReviewsTile() {
  const ref = useRef<HTMLElement>(null);
  const near = useNearScreen(ref);
  const reviews = useReviews(near);
  const google = reviews.status === 'ready' && reviews.reviews.google.available ? reviews.reviews.google : null;
  const yelp = reviews.status === 'ready' && reviews.reviews.yelp.available ? reviews.reviews.yelp : null;
  return (
    <article ref={ref} className="tile tile--dark on-dark" aria-labelledby="tile-reviews">
      <h2 id="tile-reviews" className="tile__title">
        What clients say
      </h2>
      <p className="tile__text">Reviews from Google and Yelp, in their own words.</p>
      <div className="actions actions--center tile__links">
        <MoreLink to="/reviews">Read reviews</MoreLink>
      </div>
      <div className="tile__body rating-tile" aria-live="polite">
        {google?.rating == null && yelp?.rating == null ? (
          <div className="rating-tile__links">
            <span className="rating-tile__quote" aria-hidden="true">
              “
            </span>
            <p>Read them where clients wrote them.</p>
            <div className="actions actions--center">
              <a className="button button--secondary" href={reviews.status === 'ready' ? reviews.reviews.google.url : FALLBACK_SHOP.googleMapsUrl}>
                Google reviews
              </a>
              <a className="button button--secondary" href={reviews.status === 'ready' ? reviews.reviews.yelp.url : FALLBACK_SHOP.yelpUrl}>
                Yelp reviews
              </a>
            </div>
          </div>
        ) : null}
        {google?.rating != null ? (
          <div className="rating-tile__score" data-testid="home-rating">
            <span className="rating-tile__number">{google.rating.toFixed(1)}</span>
            <Stars rating={google.rating} size={22} />
            <span className="rating-tile__count">
              {google.count != null ? `${google.count} reviews on Google` : 'On Google'}
            </span>
          </div>
        ) : null}
        {yelp?.rating != null ? (
          <p className="rating-tile__yelp">
            {yelp.rating.toFixed(1)} on Yelp{yelp.count != null ? ` · ${yelp.count} reviews` : ''}
          </p>
        ) : null}
      </div>
    </article>
  );
}
