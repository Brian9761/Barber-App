import { SKIP_WAITING } from '../sw/routes';
import { offerUpdate } from './updates';

/** How long Reload waits for the new version to take over before reloading anyway. */
const TAKE_OVER_WAIT_MS = 4000;

/**
 * Registers the service worker (/sw.js, for the whole site), and offers each new version once
 * it has installed: the page shows "A new version is ready · Reload", and only a tap on Reload
 * makes the new version take over and reloads the page. Nothing reloads by itself. The site
 * works the same where there's no service worker.
 */
export async function registerServiceWorker(
  container: ServiceWorkerContainer | undefined = navigator.serviceWorker,
  reload: () => void = () => window.location.reload(),
): Promise<ServiceWorkerRegistration | null> {
  if (!container) return null;
  const startedWithWorker = container.controller !== null;
  let reloadAsked = false;

  container.addEventListener('controllerchange', () => {
    if (reloadAsked) reload();
    // Reload was tapped in another tab: this one still shows the old version, so it offers it too.
    else if (startedWithWorker) offerUpdate(reload);
  });

  const offer = (worker: ServiceWorker) =>
    offerUpdate(() => {
      reloadAsked = true;
      worker.postMessage({ type: SKIP_WAITING });
      setTimeout(reload, TAKE_OVER_WAIT_MS);
    });

  let registration: ServiceWorkerRegistration;
  try {
    registration = await container.register('/sw.js', { scope: '/' });
  } catch {
    return null;
  }
  // The first version installs for next time, and isn't "new": only one installed while a version is in use is.
  if (registration.waiting && container.controller) offer(registration.waiting);
  registration.addEventListener('updatefound', () => {
    const installing = registration.installing;
    installing?.addEventListener('statechange', () => {
      if (installing.state === 'installed' && container.controller) offer(installing);
    });
  });
  return registration;
}

/** An app left open for days still hears about new versions: it looks again whenever it comes back on screen. */
export function checkForUpdatesWhenShown(registration: Pick<ServiceWorkerRegistration, 'update'>, doc: Document = document): void {
  doc.addEventListener('visibilitychange', () => {
    if (doc.visibilityState === 'visible') registration.update().catch(() => undefined);
  });
}
