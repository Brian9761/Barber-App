// The site's API client: what every page calls (`api`) and the errors it can fail
// with. The calls go to the shop's server (./http.ts, through ./backend.ts), or,
// in the demo build, to the demo's stand-in in the browser (src/demo/api.ts),
// which answers the same way.

import { backend } from './backend';

export {
  ApiError,
  defaultMessage,
  ErrorCode,
  errorFromResponse,
  errorMessage,
  isApiError,
  OFFLINE,
  OFFLINE_MESSAGE,
} from './errors';
export type { Api } from './http';

export const api = backend;
