import { afterEach } from 'vitest';

// Every page test runs in jsdom. The build's own tools' tests (tools/) run in Node, with no page.
if (typeof window !== 'undefined') {
  const { cleanup, configure } = await import('@testing-library/react');

  // A test waits up to 3 seconds for what it looks for (findBy…, waitFor): a whole page can take
  // more than the default second to render on a busy computer. Found sooner, it goes on sooner.
  configure({ asyncUtilTimeout: 3000 });

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
