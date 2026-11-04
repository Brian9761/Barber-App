import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
// Inter, self-hosted: only downloaded where the system font (SF Pro) isn't there.
import '@fontsource-variable/inter/index.css';
import './styles/tokens.css';
import './styles/base.css';
import './styles/components.css';
import './styles/pages.css';
import './styles/app.css';
import { App, ROUTER_FUTURE } from './App';
import { CatalogProvider } from './data/catalog';
import { isDemo } from './demo/mode';
import { carryAppointments, forgetDemoLeftovers, loadAppointments } from './lib/storage';
import { openOtherSitesOutside } from './pwa/externalLinks';
import { listenForInstallPrompt } from './pwa/installPrompt';
import { markStandalone } from './pwa/platform';
import { checkForUpdatesWhenShown, registerServiceWorker } from './pwa/register';

// Before the page draws: the browser's offer to install can come at any moment, and the styles
// and links need to know whether the site is open as the app.
listenForInstallPrompt();
markStandalone();
openOtherSitesOutside();

if (!isDemo()) {
  // The real site, where the demo may have been before: the demo's bookings were never the shop's.
  forgetDemoLeftovers();
  // The appointments booked here, ready for an app added to the Home Screen (lib/storage.ts).
  carryAppointments(loadAppointments());
}

const root = document.getElementById('root');
if (!root) throw new Error('The page has no #root element');

createRoot(root).render(
  <StrictMode>
    <BrowserRouter future={ROUTER_FUTURE}>
      <CatalogProvider>
        <App />
      </CatalogProvider>
    </BrowserRouter>
  </StrictMode>,
);

// The service worker, in the built site only (the dev server changes files as they're edited).
// After the page has loaded, so keeping the app's files never slows the first visit down.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    void registerServiceWorker().then((registration) => {
      if (registration) checkForUpdatesWhenShown(registration);
    });
  });
}
