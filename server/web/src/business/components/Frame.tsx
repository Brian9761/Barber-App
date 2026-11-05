// Izzy Clipz Business's frame, like apple.com's product pages: a thin black bar with the
// shop's logo and the red "Business" pill (as on the app's icon), then a local nav that
// stays at the top, "Izzy Clipz Business" at left with Today · Analytics · Products ·
// Settings and Sign out at right. On a phone the four become tabs across the screen, and
// Sign out sits in the black bar. In the demo, a line under the nav says it's the demo.

import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Link, NavLink, useLocation } from 'react-router-dom';
import { isApiError } from '../../api/errors';
import { Dialog } from '../../components/Dialog';
import { Icon } from '../../components/Icon';
import { Logo } from '../../components/Logo';
import { useShopContact } from '../../data/catalog';
import { useOnline } from '../../pwa/connection';
import { UpdateBar } from '../../pwa/UpdateBar';
import { ownerApi } from '../api/client';
import { APP_NAME, DEMO_LINE, demo } from '../hooks';
import { session } from '../session';

const LINKS = [
  { to: '/business/today', label: 'Today' },
  { to: '/business/analytics', label: 'Analytics' },
  { to: '/business/products', label: 'Products' },
  { to: '/business/settings', label: 'Settings' },
];

/** "Sign out": asks first (a new code from the iPhone is needed to sign in again), then signs this computer out. */
export function useSignOut() {
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const signOut = async () => {
    setBusy(true);
    try {
      await ownerApi.signOut();
      session.signOut();
    } catch (error) {
      // Signed out here all the same: the token is gone from this computer.
      const unreachable = isApiError(error) && error.isOffline;
      session.signOut(
        unreachable
          ? "We couldn't reach the server to end this computer's session, so it ends by itself within 30 days. To end it now, sign it out in the iPhone app: Settings → Use on a computer."
          : null,
      );
    } finally {
      setBusy(false);
      setAsking(false);
    }
  };
  const dialog = (
    <Dialog
      open={asking}
      title="Sign out on this computer?"
      onClose={() => setAsking(false)}
      testId="sign-out-dialog"
      actions={
        <>
          <button type="button" className="button button--secondary" onClick={() => setAsking(false)} disabled={busy}>
            Stay signed in
          </button>
          <button type="button" className="button button--primary" onClick={() => void signOut()} disabled={busy}>
            {busy ? 'Signing out…' : 'Sign out'}
          </button>
        </>
      }
    >
      <p>{demo() ? 'You can open the demo again with one click.' : "To sign in again, you'll need a new code from Izzy Clipz Business on your iPhone."}</p>
    </Dialog>
  );
  return { ask: () => setAsking(true), dialog };
}

function GlobalBar({ signedIn, onSignOut }: { signedIn: boolean; onSignOut: () => void }) {
  return (
    <header className="biz-globalbar">
      <div className="container container--wide biz-globalbar__inner">
        <Link to={signedIn ? '/business/today' : '/business'} className="biz-globalbar__home" aria-label={signedIn ? `${APP_NAME}: Today` : APP_NAME}>
          <Logo height={34} />
          <span className="biz-pill" aria-hidden="true">
            Business
          </span>
        </Link>
        {signedIn ? (
          <button type="button" className="biz-globalbar__signout" onClick={onSignOut}>
            Sign out
          </button>
        ) : null}
      </div>
    </header>
  );
}

function LocalNav({ onSignOut }: { onSignOut: () => void }) {
  return (
    <nav className="biz-localnav" aria-label={APP_NAME}>
      <div className="container container--wide biz-localnav__inner">
        <p className="biz-localnav__title">{APP_NAME}</p>
        <ul className="biz-localnav__links">
          {LINKS.map((link) => (
            <li key={link.to}>
              <NavLink to={link.to} className="biz-localnav__link">
                {link.label}
              </NavLink>
            </li>
          ))}
        </ul>
        <button type="button" className="biz-localnav__signout" onClick={onSignOut}>
          Sign out
        </button>
      </div>
    </nav>
  );
}

/** "You're offline", under the nav, while there's no connection: the demo still works, the real thing needs the server. */
function OfflineLine() {
  const online = useOnline();
  return (
    <div className="offline-notice" aria-live="polite" aria-atomic="true" data-testid="biz-offline">
      {online ? null : (
        <p className="ribbon">
          <span className="container container--wide ribbon__text">
            {demo()
              ? "You're offline. The demo still works: everything stays in this browser."
              : "You're offline. Izzy Clipz Business needs the internet to show the shop's schedule and sales. Check your connection."}
          </span>
        </p>
      )}
    </div>
  );
}

function DemoLine() {
  if (!demo()) return null;
  return (
    <p className="ribbon biz-demo-line" data-testid="biz-demo-notice">
      <span className="container container--wide ribbon__text">
        <Icon name="info" className="biz-demo-line__icon" />
        {DEMO_LINE}
      </span>
    </p>
  );
}

/** The frame around every Business page. */
export function Frame({ signedIn, children }: { signedIn: boolean; children: ReactNode }) {
  const { pathname } = useLocation();
  const mainRef = useRef<HTMLElement>(null);
  const firstRender = useRef(true);
  const signOut = useSignOut();
  const { phone, fullName } = useShopContact();

  // A new page starts at the top, and screen readers and keyboards start at its content.
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    window.scrollTo(0, 0);
    mainRef.current?.focus({ preventScroll: true });
  }, [pathname]);

  return (
    <div className="biz">
      <a className="skip-link" href="#main">
        Skip to main content
      </a>
      <GlobalBar signedIn={signedIn} onSignOut={signOut.ask} />
      {signedIn ? <LocalNav onSignOut={signOut.ask} /> : null}
      <div className="app-ribbons">
        <OfflineLine />
        {/* Signed out, the sign-in page says it's the demo itself, next to its one button. */}
        {signedIn ? <DemoLine /> : null}
      </div>
      <main id="main" tabIndex={-1} ref={mainRef} className="biz-main">
        {children}
      </main>
      <footer className="biz-footer">
        <div className="container container--wide biz-footer__inner">
          <p>
            {APP_NAME} for {fullName}. Clients book on{' '}
            <a href="/" className="inline-link">
              the shop's website
            </a>
            .
          </p>
          <p>
            The shop's phone: <a href={`tel:${phone.e164}`}>{phone.display}</a>
          </p>
        </div>
      </footer>
      <UpdateBar />
      {signOut.dialog}
    </div>
  );
}
