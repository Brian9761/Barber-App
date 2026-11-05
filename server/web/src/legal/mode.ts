/**
 * Whether the legal pages are drafts: in every build but a strict one (LEGAL_STRICT=1, or a
 * production build on Vercel that isn't the demo; see tools/legal.ts), which the build only
 * lets through once no placeholder is left. A draft says it isn't in effect yet, its dates read
 * "Not in effect yet", and each placeholder shows as a note. Decided when the site is built.
 */
export function legalDraft(): boolean {
  return import.meta.env.VITE_LEGAL_STRICT !== '1';
}
