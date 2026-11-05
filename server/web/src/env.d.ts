// The build's own settings, as the site's code reads them (import.meta.env).

interface ImportMetaEnv {
  /** "1" in the demo version (`npm run build:demo`), which answers its own API calls in the browser. */
  readonly VITE_DEMO_MODE?: string;
  /**
   * "1" in a strict build (LEGAL_STRICT=1, or a production build on Vercel that isn't the demo):
   * the legal documents are published as they are, and the build fails if any placeholder is left.
   */
  readonly VITE_LEGAL_STRICT?: string;
}
