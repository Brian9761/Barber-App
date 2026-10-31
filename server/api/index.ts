import { createApp, type App } from '../src/app.js';
import { productionDeps } from '../src/production.js';

// The one Vercel Function. vercel.json rewrites /api/* here; src/router.ts routes by path.
let app: App | undefined;

export default {
  fetch(request: Request): Promise<Response> {
    app ??= createApp(productionDeps());
    return app.fetch(request);
  },
};
