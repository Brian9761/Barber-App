// Where the site's API calls go: the shop's server, over the network (/api on this
// origin). The demo build (`npm run build:demo`) answers them in the browser
// instead: vite.config.ts swaps this file for src/demo/backend.ts when it builds,
// so the demo has no code that calls /api at all.

export { httpApi as backend } from './http';
