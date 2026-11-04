import { isStandalone } from './platform';

/**
 * Opened as the app, there's no browser around the page: a link to another site (maps,
 * Instagram, Google or Yelp) opens outside it, in the browser or that site's own app, and the
 * app stays where it was. `tel:` and `mailto:` links work as they are, and so do the site's own
 * links. In a browser tab, links behave as they always do.
 */
export function openOtherSitesOutside(doc: Document = document, standalone: () => boolean = isStandalone): () => void {
  const onClick = (event: MouseEvent) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (!standalone()) return;
    const link = event.target instanceof Element ? event.target.closest('a[href]') : null;
    if (!(link instanceof HTMLAnchorElement) || link.hasAttribute('download')) return;
    const url = new URL(link.href, doc.baseURI);
    if ((url.protocol !== 'http:' && url.protocol !== 'https:') || url.origin === doc.location.origin) return;
    // Followed after this, as the browser would anyway, but in a window of its own.
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
  };
  doc.addEventListener('click', onClick);
  return () => doc.removeEventListener('click', onClick);
}
