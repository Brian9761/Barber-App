import type { Deps } from './deps.js';
import { json } from './http.js';
import { Router } from './router.js';
import { VERSION } from './version.js';

/** The routes of API v1 (the contract is summarized in README.md). */
export function createRouter(): Router {
  return (
    new Router()
      // Public
      .on('GET', '/api/health', async () => json({ ok: true, version: VERSION }))
  );
}

export interface App {
  fetch(request: Request): Promise<Response>;
}

export function createApp(deps: Deps): App {
  const router = createRouter();
  return { fetch: (request) => router.handle(request, deps) };
}
