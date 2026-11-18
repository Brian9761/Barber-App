import { act, screen, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { loadLegalPage } from '../App';
import { renderApp } from '../test/api';
import { finishTakingOver, readingPlace, restoreReadingPlace, takeOverInProgress, takeOverPrerenderedPage, type ReadingPlace } from './takeover';

// A policy opened at its address comes as plain HTML first (tools/prerender.ts), which can be read,
// scrolled and tabbed through before the site's script arrives. The site then draws the same page
// in its place in one go, never "Loading…" in between (main.tsx), with "On this page" as it was,
// and the reader keeps their place: the section they were in, where it was on the screen, and the
// link the keyboard was on.

/** A computer's screen (or a phone's), as "On this page" asks for it. */
function screenIsWide(wide: boolean): void {
  vi.stubGlobal('matchMedia', (query: string) => ({ matches: wide, media: query, addEventListener: () => undefined, removeEventListener: () => undefined }));
}

/** A window that records where it's asked to scroll. */
function fakeWindow(scrollY: number, hash = ''): Window & { scrolled: { by?: number; to?: number } } {
  const scrolled: { by?: number; to?: number } = {};
  return {
    scrollY,
    location: { hash },
    scrollBy: ({ top }: ScrollToOptions) => {
      scrolled.by = top;
    },
    scrollTo: ({ top }: ScrollToOptions) => {
      scrolled.to = top;
    },
    scrolled,
  } as unknown as Window & { scrolled: { by?: number; to?: number } };
}

/** Where `element` is on the screen, from its top. */
function placeAt(element: Element, top: number): void {
  element.getBoundingClientRect = () => ({ top, bottom: top + 30, left: 0, right: 0, width: 0, height: 30, x: 0, y: top, toJSON: () => ({}) });
}

/** A policy's plain HTML, as the build writes it into #root. */
function plainPage(): HTMLElement {
  const root = document.createElement('div');
  root.innerHTML = `
    <a class="skip-link" href="#main">Skip to main content</a>
    <main id="main" data-prerendered="">
      <article class="legal">
        <h1 id="privacy-policy">Privacy Policy</h1>
        <nav class="legal-toc"><details><summary>On this page</summary><a href="#who-we-share">Who we share</a></details></nav>
        <h2 id="what-we-collect" tabindex="-1">What we collect</h2>
        <p>Words.</p>
        <h2 id="who-we-share" tabindex="-1">Who we share</h2>
        <p>More words, with <a href="/terms">our Terms</a>.</p>
      </article>
    </main>`;
  document.body.append(root);
  return root;
}

afterEach(() => {
  finishTakingOver();
  vi.unstubAllGlobals();
  document.body.innerHTML = '';
});

describe('where the reader is in the plain HTML', () => {
  let root: HTMLElement;
  beforeEach(() => {
    root = plainPage();
  });

  it('is the first section heading still on the screen, how far down it was, the keyboard’s link and “On this page”', () => {
    const [title, collect, share] = root.querySelectorAll('h1, h2');
    placeAt(title!, -900);
    placeAt(collect!, -400);
    placeAt(share!, 120);
    root.querySelector('details')!.setAttribute('open', '');
    root.querySelector<HTMLAnchorElement>('a[href="/terms"]')!.focus();
    const place = readingPlace(root, fakeWindow(2400, '#who-we-share'));
    expect(place).toEqual({
      scrollY: 2400,
      anchor: { id: 'who-we-share', top: 120 },
      focus: { tag: 'a', id: null, href: '/terms', text: 'our Terms' },
      contentsOpen: true,
      hash: '#who-we-share',
    });
  });

  it('at the top, with nothing focused: nothing to keep but “On this page” closed', () => {
    for (const heading of root.querySelectorAll('h1, h2')) placeAt(heading, 200);
    const place = readingPlace(root, fakeWindow(0));
    expect(place.scrollY).toBe(0);
    expect(place.focus).toBeNull();
    expect(place.contentsOpen).toBe(false);
  });
});

describe('the site’s page, right after it’s drawn over the plain HTML', () => {
  it('puts the reader’s section back where it was on the screen, whatever moved above it, and the keyboard on the same link', () => {
    const root = plainPage();
    const place: ReadingPlace = {
      scrollY: 2400,
      anchor: { id: 'who-we-share', top: 120 },
      focus: { tag: 'a', id: null, href: '/terms', text: 'our Terms' },
      contentsOpen: false,
      hash: '',
    };
    // The site's page has its own nav above: the heading is now 64px further down.
    placeAt(root.querySelector('#who-we-share')!, 184);
    const view = fakeWindow(2400);
    restoreReadingPlace(root, place, view);
    expect(view.scrolled).toEqual({ by: 64 });
    expect(document.activeElement).toBe(root.querySelector('a[href="/terms"]'));
  });

  it('without a heading to go by, goes back to the same scroll; at the top, doesn’t scroll at all', () => {
    const root = plainPage();
    const lost = fakeWindow(5000);
    restoreReadingPlace(root, { scrollY: 5000, anchor: { id: 'gone', top: 10 }, focus: null, contentsOpen: false, hash: '' }, lost);
    expect(lost.scrolled).toEqual({ to: 5000 });
    const top = fakeWindow(0);
    restoreReadingPlace(root, { scrollY: 0, anchor: null, focus: null, contentsOpen: false, hash: '' }, top);
    expect(top.scrolled).toEqual({});
  });

  it('opened at a #section with the keyboard on nothing yet, the keyboard goes on from that section’s heading, without scrolling', () => {
    const root = plainPage();
    const heading = root.querySelector<HTMLElement>('#who-we-share')!;
    const focus = vi.spyOn(heading, 'focus');
    restoreReadingPlace(root, { scrollY: 0, anchor: null, focus: null, contentsOpen: false, hash: '#who-we-share' }, fakeWindow(0));
    expect(focus).toHaveBeenCalledWith({ preventScroll: true });
    expect(document.activeElement).toBe(heading);
  });
});

describe('drawing over a policy’s plain HTML', () => {
  it('draws the page in the first draw once its code is here, never “Loading…”, with “On this page” as the plain HTML had it', async () => {
    screenIsWide(true);
    await loadLegalPage();
    takeOverPrerenderedPage(false);
    expect(takeOverInProgress()).toEqual({ contentsOpen: false });
    renderApp('/privacy');
    // No waiting: the first draw is the page.
    expect(screen.getByRole('heading', { level: 1, name: 'Privacy Policy' })).toBeTruthy();
    expect(screen.queryByText('Loading…')).toBeNull();
    // Closed, as it was, even on a computer's screen, where the site would open it.
    const contents = screen.getByTestId('legal-contents');
    expect(contents.querySelector('details')?.open).toBe(false);
    // Once drawn, the next page opened in the site is drawn as usual.
    expect(takeOverInProgress()).toBeNull();
  });

  it('leaves the reader where they are when opened at a #section: the browser already went there', async () => {
    await loadLegalPage();
    takeOverPrerenderedPage(false);
    const scrollIntoView = vi.fn();
    Element.prototype.scrollIntoView = scrollIntoView;
    renderApp('/privacy#saved-cards');
    await act(async () => undefined);
    expect(screen.getByRole('heading', { level: 3, name: 'Saved cards' })).toBeTruthy();
    expect(scrollIntoView).not.toHaveBeenCalled();
  });

  it('opened in the site itself, a policy is drawn as usual: “On this page” open on a computer, and a #section scrolled to', async () => {
    screenIsWide(true);
    await loadLegalPage();
    const scrollIntoView = vi.fn();
    Element.prototype.scrollIntoView = scrollIntoView;
    renderApp('/privacy#saved-cards');
    const heading = await screen.findByRole('heading', { level: 3, name: 'Saved cards' });
    await act(async () => undefined);
    expect(within(screen.getByTestId('legal-contents')).getByText('On this page').closest('details')?.open).toBe(true);
    expect(scrollIntoView).toHaveBeenCalled();
    expect(document.activeElement).toBe(heading);
  });
});
