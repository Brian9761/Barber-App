import { afterEach } from 'vitest';

// Every page test runs in jsdom. The build's own tools' tests (tools/) run in Node, with no page.
if (typeof window !== 'undefined') {
  const { cleanup } = await import('@testing-library/react');

  // jsdom has no scrolling; pages scroll to the top when they open.
  window.scrollTo = () => undefined;

  afterEach(() => {
    cleanup();
    localStorage.clear();
    sessionStorage.clear();
    // Cookies too (the appointments carried into an app added to the Home Screen).
    for (const pair of document.cookie.split(';')) {
      const name = pair.split('=')[0]?.trim();
      if (name) document.cookie = `${name}=; Path=/; Max-Age=0`;
    }
  });
}
