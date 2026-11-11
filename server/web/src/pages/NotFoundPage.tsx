import { CallLink, MoreLink } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';

export function NotFoundPage() {
  usePageMeta('Page not found', "This page isn't here. Book an appointment, see the services or find the shop.");
  return (
    <section className="band not-found" aria-labelledby="not-found-title">
      <div className="container container--narrow not-found__inner">
        <p className="eyebrow">Page not found</p>
        <h1 id="not-found-title">This page isn't here.</h1>
        <p className="lead secondary">It may have moved, or the link has a typo. Here's where most people are headed:</p>
        <ul className="not-found__links">
          <li>
            <MoreLink to="/book" large>
              Book an appointment
            </MoreLink>
          </li>
          <li>
            <MoreLink to="/services" large>
              See services and prices
            </MoreLink>
          </li>
          <li>
            <MoreLink to="/visit" large>
              Hours and directions
            </MoreLink>
          </li>
          <li>
            <MoreLink to="/" large>
              Home page
            </MoreLink>
          </li>
        </ul>
        <p className="secondary">
          Or call the shop at <CallLink className="inline-link nowrap" />.
        </p>
      </div>
    </section>
  );
}
