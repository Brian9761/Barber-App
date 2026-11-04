/**
 * An expected sentence with the site's time labels as they are rendered: "10 AM" is
 * "10 AM" (a space that doesn't break, so "AM" never sits alone on a line).
 */
export function times(text: string): string {
  return text.replace(/(\d) (AM|PM)\b/g, '$1 $2');
}
