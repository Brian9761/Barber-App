// The build's own settings, as the site's code reads them (import.meta.env).

interface ImportMetaEnv {
  /** "1" in the demo version (`npm run build:demo`), which answers its own API calls in the browser. */
  readonly VITE_DEMO_MODE?: string;
}
