import { Icon } from '../components/Icon';
import { useShopContact } from '../data/catalog';
import { isDemo } from './mode';

/** The apps' demo line (IzzyClipz/App/DemoMode.swift), and how to book for real. */
export const DEMO_NOTICE = "Demo version: bookings aren't sent to the shop.";

/**
 * "Demo version: bookings aren't sent to the shop. To book for real, call (442) 341-3053." A
 * calm line, only in the demo version, wherever a visitor could take a booking for the real
 * thing: on Home under the Book button, and under "No payment now" on Review and once it's
 * booked, like the apps' demo. On Reviews it says the reviews are samples.
 */
export function DemoNotice({ about = 'booking', onDark = false }: { about?: 'booking' | 'reviews'; onDark?: boolean }) {
  const { phone } = useShopContact();
  if (!isDemo()) return null;
  return (
    <p className={`demo-notice${onDark ? ' demo-notice--on-dark' : ''}`} data-testid="demo-notice">
      <Icon name="info" className="demo-notice__icon" />
      {about === 'reviews' ? (
        <span>Demo version: these reviews are samples, not the shop's. The real site shows the shop's reviews from Google and Yelp.</span>
      ) : (
        <span>
          {DEMO_NOTICE} To book for real, call{' '}
          <a className="nowrap" href={`tel:${phone.e164}`}>
            {phone.display}
          </a>
          .
        </span>
      )}
    </p>
  );
}
