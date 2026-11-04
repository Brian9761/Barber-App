import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

// jsdom has no scrolling; pages scroll to the top when they open.
window.scrollTo = () => undefined;

afterEach(() => {
  cleanup();
  localStorage.clear();
  sessionStorage.clear();
});
