import { StrictMode } from 'react';
import { flushSync } from 'react-dom';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
// Inter, self-hosted: only downloaded where the system font (SF Pro) isn't there.
import '@fontsource-variable/inter/index.css';
import './styles/tokens.css';
import './styles/base.css';
import './styles/components.css';
import './styles/pages.css';
import './styles/app.css';
import type { Catalog } from './api/types';
import { App, loadLegalPage, ROUTER_FUTURE } from './App';
import { asCatalog, CatalogProvider } from './data/catalog';
import { isDemo } from './demo/mode';
import { finishTakingOver, readingPlace, restoreReadingPlace, takeBuildCatalog, takeOverPrerenderedPage } from './legal/takeover';
import { carryAppointments, forgetDemoLeftovers, loadAppointments, pruneAppointments, pruneBusinessSession } from './lib/storage';
import { openOtherSitesOutside } from './pwa/externalLinks';
import { listenForInstallPrompt } from './pwa/installPrompt';
import { markStandalone } from './pwa/platform';
import { checkForUpdatesWhenShown, registerServiceWorker } from './pwa/register';

// Before the page draws: the browser's offer to install can come at any moment, and the styles
// and links need to know whether the site is open as the app.
listenForInstallPrompt();
markStandalone();
openOtherSitesOutside();

// Appointments that ended over 30 days ago go from this browser (the demo's too).
pruneAppointments();
// So does a sign-in to Izzy Clipz Business whose 30 days are up, when a client's page opens
// (Business's own pages say why it went: src/business/session.ts).
if (!window.location.pathname.startsWith('/business')) pruneBusinessSession();
if (!isDemo()) {
  // The real site, where the demo may have been before: the demo's bookings were never the shop's.
  forgetDemoLeftovers();
  // The appointments booked here, ready for an app added to the Home Screen (lib/storage.ts).
  carryAppointments(loadAppointments());
}

const root = document.getElementById('root');
if (!root) throw new Error('The page has no #root element');

/** The site, asking for the shop's catalog itself, or starting with `catalog` when it already has it. */
function site(catalog?: Catalog) {
  return (
    <StrictMode>
      <BrowserRouter future={ROUTER_FUTURE}>
        <CatalogProvider initial={catalog}>
          <App />
        </CatalogProvider>
      </BrowserRouter>
    </StrictMode>
  );
}

if (root.querySelector('[data-prerendered]')) {
  // A policy's plain HTML (tools/prerender.ts), which the reader may have started on: the site
  // draws the same page in its place in one go, with the legal pages' code here first (never
  // "Loading…" in between), and the reader keeps their place (legal/takeover.ts). It draws with
  // the catalog the plain HTML was drawn with, which the page carries, so the nav and the footer
  // (its hours and who runs the shop) are the same from the first draw and nothing jumps.
  const built = asCatalog(takeBuildCatalog());
  void loadLegalPage().then(
    () => {
      const place = readingPlace(root);
      takeOverPrerenderedPage(place.contentsOpen);
      flushSync(() => createRoot(root).render(site(built)));
      // Drawn: the next page opened in the site is drawn as usual, whatever this one was.
      finishTakingOver();
      restoreReadingPlace(root, place);
    },
    // The code didn't come: the page asks for it again itself, and says so if it can't.
    () => createRoot(root).render(site(built)),
  );
} else {
  createRoot(root).render(site());
}

// The service worker, in the built site only (the dev server changes files as they're edited).
// After the page has loaded, so keeping the app's files never slows the first visit down.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    void registerServiceWorker().then((registration) => {
      if (registration) checkForUpdatesWhenShown(registration);
    });
  });
}
