import type { Deps } from './deps.js';
import { ApiError, apiPath, errorResponse } from './http.js';

export interface Context {
  request: Request;
  url: URL;
  params: Record<string, string>;
  deps: Deps;
}

export type Handler = (ctx: Context) => Promise<Response>;

interface Route {
  method: string;
  pattern: RegExp;
  keys: string[];
  handler: Handler;
}

/** A tiny method + path router for the single Vercel function. */
export class Router {
  private readonly routes: Route[] = [];

  on(method: string, path: string, handler: Handler): this {
    const keys: string[] = [];
    const source = path
      .split('/')
      .map((part) => {
        if (part.startsWith(':')) {
          keys.push(part.slice(1));
          return '([^/]+)';
        }
        return part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      })
      .join('/');
    this.routes.push({ method, pattern: new RegExp(`^${source}$`), keys, handler });
    return this;
  }

  async handle(request: Request, deps: Deps): Promise<Response> {
    let url: URL;
    try {
      url = new URL(request.url);
    } catch {
      return errorResponse(new ApiError('invalid_request', 'Bad URL.'));
    }
    const path = apiPath(url);
    const allowed = new Set<string>();
    try {
      for (const route of this.routes) {
        const match = route.pattern.exec(path);
        if (!match) continue;
        if (route.method !== request.method) {
          allowed.add(route.method);
          continue;
        }
        const params: Record<string, string> = {};
        route.keys.forEach((key, i) => {
          params[key] = decodeURIComponent(match[i + 1] ?? '');
        });
        return await route.handler({ request, url, params, deps });
      }
      if (allowed.size > 0) {
        const allow = [...allowed].sort().join(', ');
        throw new ApiError('invalid_request', `This endpoint doesn't support ${request.method}. Use ${allow}.`, {
          status: 405,
          headers: { allow },
        });
      }
      throw new ApiError('not_found', "There's nothing here.");
    } catch (error) {
      if (error instanceof ApiError) return errorResponse(error);
      if (error instanceof URIError) return errorResponse(new ApiError('not_found', "There's nothing here."));
      deps.log.error('Unhandled error', {
        method: request.method,
        path,
        error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
        code: typeof error === 'object' && error !== null && 'code' in error ? String(error.code) : undefined,
      });
      return errorResponse(new ApiError('server_error', 'Something went wrong on our side. Please try again.'));
    }
  }
}
