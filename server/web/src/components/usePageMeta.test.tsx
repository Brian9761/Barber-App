import { renderHook } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { canonicalPath, keepCanonicalOnThisPage, usePageMeta } from './usePageMeta';

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

  it('names the page without a trailing slash, as its plain HTML does, and so does og:url', () => {
    const link = document.createElement('link');
    link.rel = 'canonical';
    link.href = 'https://izzy-clipz.vercel.app/privacy';
    document.head.append(link);
    const ogUrl = () => document.head.querySelector('meta[property="og:url"]')?.getAttribute('content');

    // A policy opened at its address with a trailing slash ("/privacy/", which the hosting serves too).
    window.history.replaceState(null, '', '/privacy/');
    renderHook(() => usePageMeta('Privacy Policy', 'What Izzy Clipz Barbershop collects.'));
    expect(canonical()?.href).toBe('https://izzy-clipz.vercel.app/privacy');
    expect(ogUrl()).toBe(`${window.location.origin}/privacy`);
    window.history.pushState(null, '', '/terms//?from=footer#refunds');
    renderHook(() => usePageMeta('Terms of Service', 'The terms.'));
    expect(canonical()?.href).toBe('https://izzy-clipz.vercel.app/terms');
    expect(ogUrl()).toBe(`${window.location.origin}/terms`);
    // Home stays "/".
    window.history.pushState(null, '', '/');
    renderHook(() => usePageMeta('Izzy Clipz Barbershop', 'Home.'));
    expect(canonical()?.href).toBe('https://izzy-clipz.vercel.app/');
    expect(ogUrl()).toBe(`${window.location.origin}/`);
  });

  it('strips only trailing slashes', () => {
    expect(['/', '//', '/privacy', '/privacy/', '/privacy//', '/book/time/', ''].map(canonicalPath)).toEqual([
      '/',
      '/',
      '/privacy',
      '/privacy',
      '/privacy',
      '/book/time',
      '/',
    ]);
  });

  it('is never added to a page that didn’t come with one', () => {
    window.history.replaceState(null, '', '/services');
    renderHook(() => usePageMeta('Services and prices', 'The menu.'));
    keepCanonicalOnThisPage();
    expect(canonical()).toBeNull();
  });
});
