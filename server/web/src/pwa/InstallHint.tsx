import { useMemo, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Icon } from '../components/Icon';
import { loadAppointments } from '../lib/storage';
import { useOnline } from './connection';
import { countVisit, dismissHint, hintDismissed, showInstallHint } from './installHint';
import { useInstallPrompt } from './installPrompt';
import { currentPlatform, useStandalone } from './platform';

/**
 * "Add Izzy Clipz to your Home Screen · How", under the nav on phones: after the first booking
 * or from the second visit, never in the app itself, and gone for good once closed, or once the
 * browser says it's installed.
 */
export function InstallHint() {
  const { pathname } = useLocation();
  const standalone = useStandalone();
  const online = useOnline();
  const { installed } = useInstallPrompt();
  const device = useMemo(() => currentPlatform().device, []);
  const [visits] = useState(countVisit);
  const [dismissed, setDismissed] = useState(hintDismissed);
  // Offline, the offline notice has this place.
  if (!online) return null;
  const facts = { device, standalone, dismissed: dismissed || installed, visits, booked: loadAppointments().length > 0, pathname };
  if (!showInstallHint(facts)) return null;
  return (
    <aside className="ribbon install-hint" aria-label="Get the app" data-testid="install-hint">
      <div className="container install-hint__inner">
        <p className="install-hint__text">
          Add Izzy Clipz to your{' '}
          <span className="nowrap">
            Home Screen<span aria-hidden="true"> · </span>
            <Link to="/app" aria-label="How to add Izzy Clipz to your Home Screen">
              How
            </Link>
          </span>
        </p>
        <button
          type="button"
          className="install-hint__close"
          aria-label="Hide this"
          onClick={() => {
            dismissHint();
            setDismissed(true);
          }}
        >
          <Icon name="close" />
        </button>
      </div>
    </aside>
  );
}
