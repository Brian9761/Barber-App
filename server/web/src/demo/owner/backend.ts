// The demo build's owner backend: vite.config.ts puts this file in place of
// src/business/api/backend.ts, so every call Izzy Clipz Business makes is answered
// in the browser by the demo's stand-in for the shop, and nothing is ever sent to /api.

export { demoOwnerApi as backend } from './api';
