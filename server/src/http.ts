/** Error codes from the API contract, with their HTTP status. */
export const ERROR_STATUS = {
  invalid_request: 400,
  unauthorized: 401,
  not_found: 404,
  slot_taken: 409,
  not_cancellable: 409,
  outside_hours: 422,
  too_soon: 422,
  too_far: 422,
  rate_limited: 429,
  stripe_not_configured: 503,
  owner_not_configured: 503,
  server_error: 500,
} as const;

export type ErrorCode = keyof typeof ERROR_STATUS;

/** An error the client should see, in the contract's `{ error: { code, message } }` shape. */
export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly status: number;
  readonly headers: Record<string, string>;

  constructor(code: ErrorCode, message: string, options: { status?: number; headers?: Record<string, string> } = {}) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.status = options.status ?? ERROR_STATUS[code];
    this.headers = options.headers ?? {};
  }
}

const BASE_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  // Nothing from this API may be cached: availability is live, and Google's
  // terms forbid caching review content.
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
};

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...BASE_HEADERS, ...headers } });
}

export function noContent(): Response {
  return new Response(null, { status: 204, headers: { 'cache-control': 'no-store' } });
}

export function errorResponse(error: ApiError): Response {
  return json({ error: { code: error.code, message: error.message } }, error.status, error.headers);
}

/** The API path, whether Vercel passes the original URL or the rewritten `/api?path=…` one. */
export function apiPath(url: URL): string {
  let path = url.pathname;
  if (path === '/api' || path === '/api/') {
    const rewritten = url.searchParams.get('path');
    path = rewritten ? `/api/${rewritten.replace(/^\/+/, '')}` : '/api';
  }
  // One canonical form: no trailing slash, no doubled slashes.
  path = path.replace(/\/{2,}/g, '/');
  if (path.length > 1 && path.endsWith('/')) path = path.slice(0, -1);
  return path;
}

async function readLimited(request: Request, maxBytes: number): Promise<Uint8Array> {
  const declared = request.headers.get('content-length');
  if (declared !== null && /^\d+$/.test(declared) && Number(declared) > maxBytes) {
    throw tooLarge(maxBytes);
  }
  if (!request.body) return new Uint8Array(0);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => undefined);
      throw tooLarge(maxBytes);
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

function tooLarge(maxBytes: number): ApiError {
  const size = maxBytes >= 1024 * 1024 ? `${Math.round(maxBytes / (1024 * 1024))} MB` : `${Math.round(maxBytes / 1024)} KB`;
  return new ApiError('invalid_request', `That's too much data. The limit is ${size}.`, { status: 413 });
}

export const MAX_JSON_BYTES = 16 * 1024;

/** The media type of `Content-Type`, lowercased and without parameters ("application/json"). */
export function mediaType(request: Request): string {
  return (request.headers.get('content-type') ?? '').split(';')[0]?.trim().toLowerCase() ?? '';
}

/**
 * Reads a JSON object body. It must be sent as `Content-Type: application/json`
 * (415 otherwise): a web page can only send that cross-site after a CORS
 * preflight, which this API never allows, so no other site can make its
 * visitors' browsers book. Anything that isn't a JSON object is a 400.
 */
export async function readJsonObject(request: Request, maxBytes = MAX_JSON_BYTES): Promise<Record<string, unknown>> {
  if (mediaType(request) !== 'application/json') {
    throw new ApiError('invalid_request', 'Send the request body as JSON (Content-Type: application/json).', { status: 415 });
  }
  const bytes = await readLimited(request, maxBytes);
  let text: string;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new ApiError('invalid_request', 'The request body must be UTF-8 JSON.');
  }
  if (text.trim() === '') throw new ApiError('invalid_request', 'The request needs a JSON body.');
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new ApiError('invalid_request', "The request body isn't valid JSON.");
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new ApiError('invalid_request', 'The request body must be a JSON object.');
  }
  return parsed as Record<string, unknown>;
}

export async function readBytes(request: Request, maxBytes: number): Promise<Uint8Array> {
  return readLimited(request, maxBytes);
}

export async function readText(request: Request, maxBytes: number): Promise<string> {
  const bytes = await readLimited(request, maxBytes);
  return new TextDecoder('utf-8').decode(bytes);
}
