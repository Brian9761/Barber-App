import { Fragment, useEffect, useRef, useState } from 'react';
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useCatalog, useShopContact } from '../data/catalog';
import { LEGAL_DOCUMENTS } from '../legal/documents';
import { takeOverInProgress } from '../legal/takeover';
import { InstallHint } from '../pwa/InstallHint';
import { OfflineNotice } from '../pwa/OfflineNotice';
import { useStandalone } from '../pwa/platform';
import { UpdateBar } from '../pwa/UpdateBar';
import { hoursSummary } from '../lib/shopTime';
import { Icon } from './Icon';
import { Logo } from './Logo';
import { PageErrorBoundary, PageLoadFailed } from './PageError';
import { CallLink } from './ui';
import { legalNameOf, OperatorLines, REFUNDS_HREF, REFUNDS_LABEL } from './OperatorLines';

/**
 * What has done its job once the site is open as the app: drawn always, and hidden then by the
 * styles (app.css), so a policy's plain HTML, drawn before any script, is the same.
 */
export const NOT_IN_APP = 'not-in-app';

/**
 * The nav's pages (the legal pages' plain HTML has them too: src/legal/prerender.tsx), with the class
 * of their list item: "Get the app" isn't shown in the app.
 */
export const NAV_LINKS: readonly { to: string; label: string; itemClass?: string }[] = [
  { to: '/services', label: 'Services' },
  { to: '/barbers', label: 'Barbers' },
  { to: '/reviews', label: 'Reviews' },
  { to: '/visit', label: 'Visit' },
  { to: '/appointments', label: 'My appointments' },
  { to: '/app', label: 'Get the app', itemClass: NOT_IN_APP },
];

/** The footer's site directory, which the plain HTML's "Menu" goes to (src/legal/prerender.tsx). */
export const SITE_DIRECTORY_ID = 'site-directory';

/**
 * The nav's "Menu" on a phone, and the plain HTML's stand-in for it (src/legal/prerender.tsx): one id,
 * so the keyboard on the one is on the other once the site takes over (legal/takeover.ts).
 */
export const MENU_BUTTON_ID = 'globalnav-menu-button';

/** "Book" in the nav: a link with its blue pill (the legal pages' plain HTML has it too: src/legal/prerender.tsx). */
export function NavBookLink() {
  return (
    <Link to="/book" className="globalnav__book" aria-label="Book an appointment">
      <span className="globalnav__book-pill" aria-hidden="true">
        Book
      </span>
    </Link>
  );
}

/** Every page: the global nav, the page, and the footer. */
export function Layout() {
  const { pathname, hash } = useLocation();
  const mainRef = useRef<HTMLElement>(null);
  const firstRender = useRef(true);

  // A new page starts at the top, and screen readers and keyboards start at its content.
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    if (hash) return;
    window.scrollTo(0, 0);
    mainRef.current?.focus({ preventScroll: true });
  }, [pathname, hash]);

  return (
    <>
      <a className="skip-link" href="#main">
        Skip to main content
      </a>
      <GlobalNav />
      <div className="app-ribbons">
        <OfflineNotice />
        <InstallHint />
      </div>
      <main id="main" tabIndex={-1} ref={mainRef}>
        {/* A page that can't be drawn (its script didn't download) says so here, under the nav. */}
        <PageErrorBoundary resetKey={pathname} fallback={(retry) => <PageLoadFailed onRetry={retry} />}>
          <Outlet />
        </PageErrorBoundary>
      </main>
      <Footer />
      <UpdateBar />
    </>
  );
}

export function GlobalNav() {
  const { pathname } = useLocation();
  // The page the menu was opened on: going to another page closes it in that same render, so the
  // page under it is reachable again (not inert) by the time Layout moves focus to the new page.
  const [openOn, setOpenOn] = useState<string | null>(null);
  const menuOpen = openOn === pathname;
  const setMenuOpen = (open: boolean) => setOpenOn(open ? pathname : null);
  const buttonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!menuOpen) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setOpenOn(null);
        buttonRef.current?.focus();
      }
    };
    document.addEventListener('keydown', onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    // The page under the open menu can't be reached (Tab, a screen reader's cursor) while it's covered.
    const covered = [
      document.getElementById('main'),
      document.querySelector('.globalfooter'),
      document.querySelector('.skip-link'),
      document.querySelector('.app-ribbons'),
      document.querySelector('.update-bar'),
    ].filter(
      (element): element is HTMLElement => element instanceof HTMLElement,
    );
    for (const element of covered) element.setAttribute('inert', '');
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = overflow;
      for (const element of covered) element.removeAttribute('inert');
    };
  }, [menuOpen]);

  return (
    <nav className="globalnav" aria-label="Izzy Clipz">
      <div className="container globalnav__inner">
        <AppBack />
        {/* As on apple.com, the logo is the link home, and its name, "Izzy Clipz", is the link's. */}
        <Link to="/" className="globalnav__logo">
          <Logo height={38} label="Izzy Clipz" />
        </Link>
        <ul className="globalnav__links">
          {NAV_LINKS.map((link) => (
            <li key={link.to} className={link.itemClass}>
              <NavLink to={link.to} className="globalnav__link">
                {link.label}
              </NavLink>
            </li>
          ))}
        </ul>
        <NavBookLink />
        <button
          ref={buttonRef}
          id={MENU_BUTTON_ID}
          type="button"
          className="globalnav__menu-button"
          aria-expanded={menuOpen}
          aria-controls="globalnav-menu"
          onClick={() => setMenuOpen(!menuOpen)}
        >
          <Icon name={menuOpen ? 'close' : 'menu'} />
          <span>{menuOpen ? 'Close' : 'Menu'}</span>
        </button>
      </div>
      {menuOpen ? (
        <div id="globalnav-menu" className="globalnav__menu-panel">
          <div className="container">
            <ul className="globalnav__menu-list">
              <li>
                <NavLink to="/" end className="globalnav__menu-link">
                  Home
                </NavLink>
              </li>
              {NAV_LINKS.map((link) => (
                <li key={link.to} className={link.itemClass}>
                  <NavLink to={link.to} className="globalnav__menu-link">
                    {link.label}
                  </NavLink>
                </li>
              ))}
              <li>
                <NavLink to="/book" className="globalnav__menu-link">
                  Book an appointment
                </NavLink>
              </li>
            </ul>
            <p className="globalnav__menu-call">
              Prefer to call?
              <br />
              <CallLink />
            </p>
          </div>
        </div>
      ) : null}
    </nav>
  );
}

/**
 * Opened as the app there's no browser Back button, so the nav has one, on every page but Home
 * and the booking steps (which have their own), once there's somewhere to go back to. Not on a
 * policy the site has just drawn over its plain HTML (legal/takeover.ts), which has none (it's
 * drawn before any script), until the reader goes on to another page: reloaded in the app, say,
 * nothing in the nav moves when the site takes over.
 */
function AppBack() {
  const standalone = useStandalone();
  const navigate = useNavigate();
  const { pathname, key } = useLocation();
  // The page the site drew over the plain HTML, while the reader is still on it; once they've gone
  // on (even back to it later), Back is as on every other page.
  const [drawnOver, setDrawnOver] = useState(() => (takeOverInProgress() ? key : null));
  if (drawnOver !== null && drawnOver !== key) setDrawnOver(null);
  const index = (window.history.state as { idx?: number } | null)?.idx ?? 0;
  if (!standalone || drawnOver === key || index === 0 || pathname === '/' || pathname.startsWith('/book')) return null;
  return (
    <button type="button" className="globalnav__back" onClick={() => navigate(-1)}>
      <Icon name="chevronLeft" />
      <span>Back</span>
    </button>
  );
}

export function Footer() {
  const catalog = useCatalog();
  const contact = useShopContact();
  const year = new Date().getFullYear();
  return (
    <footer className="globalfooter">
      <div className="container">
        <div className="globalfooter__top">
          <Logo height={48} className="globalfooter__logo" />
          <p className="globalfooter__call">
            Prefer to call? <CallLink /> · Walk-ins welcome.
          </p>
        </div>
        <nav id={SITE_DIRECTORY_ID} className="globalfooter__directory" aria-label="Site directory">
          <div>
            <h2 className="globalfooter__heading">Explore</h2>
            <ul className="globalfooter__list">
              <li>
                <Link to="/">Home</Link>
              </li>
              <li>
                <Link to="/services">Services and prices</Link>
              </li>
              <li>
                <Link to="/barbers">Barbers</Link>
              </li>
              <li>
                <Link to="/reviews">Reviews</Link>
              </li>
            </ul>
          </div>
          <div>
            <h2 className="globalfooter__heading">Book</h2>
            <ul className="globalfooter__list">
              <li>
                <Link to="/book">Book an appointment</Link>
              </li>
              <li>
                <Link to="/appointments">My appointments</Link>
              </li>
              {/* Opened as the app, it has done its job, here as in the nav (hidden by the styles). */}
              <li className={NOT_IN_APP}>
                <Link to="/app">Get the app</Link>
              </li>
            </ul>
          </div>
          <div>
            <h2 className="globalfooter__heading">Visit the shop</h2>
            <address className="globalfooter__address">
              <Link to="/visit">
                {contact.addressLines.map((line) => (
                  <span key={line}>{line}</span>
                ))}
              </Link>
            </address>
            {catalog ? (
              <ul className="globalfooter__list globalfooter__hours" aria-label="Hours">
                {hoursSummary(catalog.hours).map((line) => (
                  <li key={line}>{line}</li>
                ))}
              </ul>
            ) : null}
          </div>
          <div>
            <h2 className="globalfooter__heading">For the shop</h2>
            <ul className="globalfooter__list">
              <li>
                {/*
                  A page of its own (its own manifest and icons), opened as one, as its link back here is: its
                  page starts afresh, with the focus on its content (src/business/components/Frame.tsx).
                */}
                <a href="/business/">Izzy Clipz Business</a>
              </li>
              <li>
                <a href={contact.instagram.url}>Instagram @{contact.instagram.handle}</a>
              </li>
            </ul>
          </div>
        </nav>
        {/*
          The shop's policies (Privacy first) on a row of their own, then who runs the shop and where, and the copyright:
          all at the size of the booking pages' words, never smaller (OWNER-CHECKLIST §3 item 20).
        */}
        <div className="globalfooter__legal">
          <nav className="globalfooter__policies" aria-label="Legal">
            <ul>
              {LEGAL_DOCUMENTS.map((document) => (
                <Fragment key={document.id}>
                  <li>
                    <Link to={document.path}>{document.title}</Link>
                  </li>
                  {/* The refund policy, next to the Cancellation & No-Show Policy (OWNER-CHECKLIST §3 item 20). */}
                  {document.id === 'cancellation-policy' ? (
                    <li>
                      <Link to={REFUNDS_HREF}>{REFUNDS_LABEL}</Link>
                    </li>
                  ) : null}
                </Fragment>
              ))}
            </ul>
          </nav>
          {/* Who runs the shop and where, at the size of the booking pages' words (OWNER-CHECKLIST §3 item 20). */}
          {catalog ? <OperatorLines shop={catalog.shop} className="globalfooter__operator" testId="footer-operator" /> : null}
          <p className="globalfooter__copyright">
            Copyright © {year} {(catalog && legalNameOf(catalog.shop)) ?? contact.fullName}. All rights reserved.
          </p>
        </div>
      </div>
    </footer>
  );
}
