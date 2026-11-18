import { renderHook } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { keepCanonicalOnThisPage, usePageMeta } from './usePageMeta';

// The canonical link: only a policy's plain HTML has one (tools/prerender.ts), naming the site's
// public address. Once the site takes that page over, each page opened in it names its own
// address there, at that public address, so Home and Services never claim to be /privacy.

const canonical = () => document.head.querySelector<HTMLLinkElement>('link[rel="canonical"]');

afterEach(() => {
  canonical()?.remove();
  window.history.replaceState(null, '', '/');
});

describe('the canonical link', () => {
  it('follows the page the reader is on, at the public address the plain HTML gave', () => {
    const link = document.createElement('link');
    link.rel = 'canonical';
    link.href = 'https://izzy-clipz.vercel.app/privacy';
    document.head.append(link);

    window.history.replaceState(null, '', '/privacy');
    renderHook(() => usePageMeta('Privacy Policy', 'What Izzy Clipz Barbershop collects.'));
    expect(canonical()?.href).toBe('https://izzy-clipz.vercel.app/privacy');

    // Home, then Services, opened in the site after the policy.
    window.history.pushState(null, '', '/');
    renderHook(() => usePageMeta('Izzy Clipz Barbershop', 'Home.'));
    expect(canonical()?.href).toBe('https://izzy-clipz.vercel.app/');
    window.history.pushState(null, '', '/services?from=nav');
    renderHook(() => usePageMeta('Services and prices', 'The menu.'));
    expect(canonical()?.href).toBe('https://izzy-clipz.vercel.app/services');
    expect(document.head.querySelectorAll('link[rel="canonical"]')).toHaveLength(1);
  });

  it('is never added to a page that didn’t come with one', () => {
    window.history.replaceState(null, '', '/services');
    renderHook(() => usePageMeta('Services and prices', 'The menu.'));
    keepCanonicalOnThisPage();
    expect(canonical()).toBeNull();
  });
});
