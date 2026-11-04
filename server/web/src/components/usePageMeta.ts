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

/** Each page's own <title>, description and Open Graph tags. */
export function usePageMeta(title: string, description: string): void {
  useEffect(() => {
    // A title that already names the shop (Home's) is used as it is.
    const full = title.includes(SITE_NAME) ? title : `${title} · ${SITE_NAME}`;
    document.title = full;
    setMeta('name', 'description', description);
    setMeta('property', 'og:title', full);
    setMeta('property', 'og:description', description);
    setMeta('property', 'og:url', window.location.origin + window.location.pathname);
  }, [title, description]);
}
