// Taking over a policy's plain HTML (tools/prerender.ts). Opened at its address, a legal page
// comes as plain HTML first, which can be read, scrolled and tabbed through before the site's
// script arrives (on a slow connection, for seconds). The site then draws the same page in its
// place, in one go (main.tsx), and the reader keeps their place: the section they were reading,
// the link the keyboard was on, and "On this page" open or closed as it was.

/** While the site draws over a policy's plain HTML: whether its "On this page" was open. */
let takingOver: { contentsOpen: boolean } | null = null;

/**
 * Just before the site first draws over a policy's plain HTML. The page's first draw
 * (LegalPage.tsx) keeps "On this page" open or closed as it was, and leaves the reader where they
 * are (the browser already went to any #section in the plain HTML), so nothing on screen moves.
 */
export function takeOverPrerenderedPage(contentsOpen: boolean): void {
  takingOver = { contentsOpen };
}

/** What the legal page's first draw reads. */
export function takeOverInProgress(): { contentsOpen: boolean } | null {
  return takingOver;
}

/** Once the legal page has drawn: the next one opened in the site is drawn as usual. */
export function finishTakingOver(): void {
  takingOver = null;
}

/** Where the reader is in the plain HTML, read just before the site draws over it. */
export interface ReadingPlace {
  scrollY: number;
  /** The first heading still on the screen or below it (by its id), and how far down the screen it was. */
  anchor: { id: string; top: number } | null;
  /** What the keyboard was on: its id, its address for a link, and its words. */
  focus: { tag: string; id: string | null; href: string | null; text: string } | null;
  /** Whether "On this page" was open. */
  contentsOpen: boolean;
  /** The address's #section ("#saved-cards"), or "". */
  hash: string;
}

function words(element: Element): string {
  return (element.textContent ?? '').replace(/\s+/g, ' ').trim();
}

/** Where the reader is in `root`'s plain HTML. */
export function readingPlace(root: HTMLElement, view: Window = window): ReadingPlace {
  const headings = Array.from(root.querySelectorAll<HTMLElement>('main h1[id], main h2[id], main h3[id]'));
  // The reader is in the section before it, or at it.
  const next = headings.find((heading) => heading.getBoundingClientRect().bottom > 0) ?? null;
  const active = root.ownerDocument.activeElement;
  const focus =
    active instanceof HTMLElement && active !== root && root.contains(active)
      ? { tag: active.tagName.toLowerCase(), id: active.id || null, href: active.getAttribute('href'), text: words(active) }
      : null;
  return {
    scrollY: view.scrollY,
    anchor: next ? { id: next.id, top: next.getBoundingClientRect().top } : null,
    focus,
    contentsOpen: root.querySelector('.legal-toc details')?.hasAttribute('open') ?? false,
    hash: view.location.hash,
  };
}

/** The heading an address's #section names, inside the page's document. */
function sectionHeading(root: HTMLElement, hash: string): HTMLElement | null {
  if (!hash) return null;
  let id = hash.slice(1);
  try {
    id = decodeURIComponent(id);
  } catch {
    // Not encoded: as it is.
  }
  const heading = root.ownerDocument.getElementById(id);
  return heading && root.contains(heading) && heading.closest('.legal') ? heading : null;
}

/** The element in the site's page that stands for what the keyboard was on in the plain HTML. */
function sameElement(root: HTMLElement, focus: NonNullable<ReadingPlace['focus']>): HTMLElement | null {
  if (focus.id) {
    const byId = root.ownerDocument.getElementById(focus.id);
    if (byId && root.contains(byId)) return byId;
  }
  const candidates = Array.from(root.querySelectorAll<HTMLElement>(focus.tag)).filter(
    (element) => focus.href === null || element.getAttribute('href') === focus.href,
  );
  return candidates.find((element) => words(element) === focus.text) ?? (focus.href !== null ? (candidates[0] ?? null) : null);
}

/**
 * Right after the site has drawn over the plain HTML, before anything is painted: the section the
 * reader was in back where it was on the screen (whatever moved above it), and the keyboard back
 * on the same link. Opened at a #section with the keyboard on nothing yet, the keyboard goes on
 * from that section's heading, as when the site opens a section itself (LegalPage.tsx), without
 * scrolling.
 */
export function restoreReadingPlace(root: HTMLElement, place: ReadingPlace, view: Window = window): void {
  if (place.scrollY > 0) {
    const anchor = place.anchor ? root.ownerDocument.getElementById(place.anchor.id) : null;
    if (anchor && place.anchor) view.scrollBy({ top: anchor.getBoundingClientRect().top - place.anchor.top, behavior: 'instant' });
    else view.scrollTo({ top: place.scrollY, behavior: 'instant' });
  }
  const target = place.focus ? sameElement(root, place.focus) : sectionHeading(root, place.hash);
  target?.focus({ preventScroll: true });
}
