import { useShopContact } from '../data/catalog';
import { isDemo } from '../demo/mode';
import { useOnline } from './connection';

/**
 * "You're offline. To book, call the shop: (442) 341-3053" under the nav, while there's no
 * connection: the pages the app keeps still open, but booking and My appointments need the
 * shop. Its place is always there (empty while online), so screen readers hear it appear.
 *
 * The demo answers in the browser, so it all still works offline, and the line says so.
 */
export function OfflineNotice() {
  const online = useOnline();
  const { phone } = useShopContact();
  return (
    <div className="offline-notice" aria-live="polite" aria-atomic="true" data-testid="offline-notice">
      {online ? null : (
        <p className="ribbon">
          <span className="container ribbon__text">
            {isDemo() ? "You're offline. The demo still works. To book for real, call the shop:" : "You're offline. To book, call the shop:"}{' '}
            <a className="nowrap" href={`tel:${phone.e164}`}>
              {phone.display}
            </a>
          </span>
        </p>
      )}
    </div>
  );
}
