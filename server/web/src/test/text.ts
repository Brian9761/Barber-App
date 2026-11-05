/**
 * An expected sentence with the site's time labels as they are rendered: "10 AM" is
 * "10 AM" (a space that doesn't break, so "AM" never sits alone on a line).
 */
export function times(text: string): string {
  return text.replace(/(\d) (AM|PM)\b/g, '$1 $2');
}

/** What an element shows on screen: its text without what's only for screen readers (".visually-hidden"). */
export function visibleText(element: Element): string {
  const copy = element.cloneNode(true) as Element;
  for (const hidden of copy.querySelectorAll('.visually-hidden')) hidden.remove();
  return copy.textContent ?? '';
}
