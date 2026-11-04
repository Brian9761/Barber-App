// The demo build's backend: vite.config.ts puts this file in place of
// src/api/backend.ts, so every API call is answered in the browser by the demo's
// stand-in for the shop, and nothing is ever sent to /api.

export { demoApi as backend } from './api';
