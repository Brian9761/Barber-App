// Izzy Clipz Business's API client: what every Business page calls (`ownerApi`). The
// calls go to the shop's server (./http.ts, through ./backend.ts), or, in the demo
// build, to the demo's stand-in in the browser (src/demo/owner/api.ts), which answers
// the same way.

import { backend } from './backend';

export type { OwnerApi } from './http';
export { OWNER_OFFLINE_MESSAGE, SIGNED_OUT } from './http';

export const ownerApi = backend;
