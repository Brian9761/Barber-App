/**
 * Whether this is the demo version: built with `npm run build:demo` (VITE_DEMO_MODE=1), it
 * answers its own API calls in the browser (src/demo/api.ts) and says so where someone could
 * take a booking for the real thing. Decided when the site is built, never by the visitor.
 */
export function isDemo(): boolean {
  return import.meta.env.VITE_DEMO_MODE === '1';
}
