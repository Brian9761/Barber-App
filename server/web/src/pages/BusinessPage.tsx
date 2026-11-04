import { Link } from 'react-router-dom';
import { Logo } from '../components/Logo';
import { usePageMeta } from '../components/usePageMeta';

/** The shop's own area. A later step builds it here; for now it says what's coming. */
export function BusinessPage() {
  usePageMeta('Izzy Clipz Business', 'Izzy Clipz Business on your computer is coming next: the shop’s schedule, checkout and sales.');
  return (
    <section className="band business" aria-labelledby="business-title">
      <div className="container container--narrow business__inner">
        <Logo height={128} className="business__logo" />
        <p className="eyebrow">For the shop</p>
        <h1 id="business-title">Izzy Clipz Business on your computer — coming next</h1>
        <p className="lead secondary">
          Soon the shop will see its schedule, check clients out and follow its sales here, on a computer. Until then, use the
          Izzy Clipz Business app on the shop's iPhone.
        </p>
        <div className="actions actions--center">
          <Link className="button button--secondary" to="/">
            Back to the home page
          </Link>
        </div>
      </div>
    </section>
  );
}
