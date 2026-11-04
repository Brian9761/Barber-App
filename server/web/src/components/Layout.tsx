import { useEffect, useRef, useState } from 'react';
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useCatalog, useShopContact } from '../data/catalog';
import { InstallHint } from '../pwa/InstallHint';
import { OfflineNotice } from '../pwa/OfflineNotice';
import { useStandalone } from '../pwa/platform';
import { UpdateBar } from '../pwa/UpdateBar';
import { hoursSummary } from '../lib/shopTime';
import { Icon } from './Icon';
import { Logo } from './Logo';
import { CallLink } from './ui';

const NAV_LINKS = [
  { to: '/services', label: 'Services' },
  { to: '/barbers', label: 'Barbers' },
  { to: '/reviews', label: 'Reviews' },
  { to: '/visit', label: 'Visit' },
  { to: '/appointments', label: 'My appointments' },
  { to: '/app', label: 'Get the app' },
];

/** The nav's links. Opened as the app, "Get the app" has done its job. */
function useNavLinks() {
  const standalone = useStandalone();
  return standalone ? NAV_LINKS.filter((link) => link.to !== '/app') : NAV_LINKS;
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
        <Outlet />
      </main>
      <Footer />
      <UpdateBar />
    </>
  );
}

export function GlobalNav() {
  const { pathname } = useLocation();
  const links = useNavLinks();
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
          {links.map((link) => (
            <li key={link.to}>
              <NavLink to={link.to} className="globalnav__link">
                {link.label}
              </NavLink>
            </li>
          ))}
        </ul>
        <Link to="/book" className="globalnav__book" aria-label="Book an appointment">
          <span className="globalnav__book-pill" aria-hidden="true">
            Book
          </span>
        </Link>
        <button
          ref={buttonRef}
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
              {links.map((link) => (
                <li key={link.to}>
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
 * and the booking steps (which have their own), once there's somewhere to go back to.
 */
function AppBack() {
  const standalone = useStandalone();
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const index = (window.history.state as { idx?: number } | null)?.idx ?? 0;
  if (!standalone || index === 0 || pathname === '/' || pathname.startsWith('/book')) return null;
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
  // Opened as the app, "Get the app" has done its job, here as in the nav.
  const standalone = useStandalone();
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
        <nav className="globalfooter__directory" aria-label="Site directory">
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
              {standalone ? null : (
                <li>
                  <Link to="/app">Get the app</Link>
                </li>
              )}
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
                <Link to="/business">Izzy Clipz Business</Link>
              </li>
              <li>
                <a href={contact.instagram.url}>Instagram @{contact.instagram.handle}</a>
              </li>
            </ul>
          </div>
        </nav>
        <div className="globalfooter__legal">
          <p>
            Copyright © {year} {contact.fullName}. All rights reserved.
          </p>
          <p>{contact.addressLines.join(', ')}</p>
        </div>
      </div>
    </footer>
  );
}
