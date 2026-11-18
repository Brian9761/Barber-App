import { useEffect } from 'react';

/** The site's name after each page's own title. */
export const SITE_NAME = 'Izzy Clipz Barbershop';

function setMeta(attribute: 'name' | 'property', key: string, content: string): void {
  let element = document.head.querySelector<HTMLMetaElement>(`meta[${attribute}="${key}"]`);
  if (!element) {
    element = document.createElement('meta');
    element.setAttribute(attribute, key);
    document.head.append(element);
  }
  element.setAttribute('content', content);
}

/** A page's whole title: "Privacy Policy · Izzy Clipz Barbershop". A title that already names the shop (Home's) is used as it is. */
export function fullTitle(title: string): string {
  return title.includes(SITE_NAME) ? title : `${title} · ${SITE_NAME}`;
}

/**
 * The canonical link, on the page the reader is on. Only a policy's plain HTML has one
 * (tools/prerender.ts, with the site's public address): once the site has taken that page over,
 * each page opened in it names its own address there, at the same public address, never the
 * policy's ("/privacy" on Home).
 */
export function keepCanonicalOnThisPage(): void {
  const link = document.head.querySelector<HTMLLinkElement>('link[rel="canonical"]');
  if (!link) return;
  try {
    link.href = new URL(window.location.pathname, link.href).href;
  } catch {
    link.remove();
  }
}

/** Each page's own <title>, description and Open Graph tags (and the canonical link, where there is one). */
export function usePageMeta(title: string, description: string): void {
  useEffect(() => {
    const full = fullTitle(title);
    document.title = full;
    setMeta('name', 'description', description);
    setMeta('property', 'og:title', full);
    setMeta('property', 'og:description', description);
    setMeta('property', 'og:url', window.location.origin + window.location.pathname);
    keepCanonicalOnThisPage();
  }, [title, description]);
}
