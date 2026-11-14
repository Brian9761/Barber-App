// Every failure the site shows: the API's error codes, and an ApiError with a plain
// sentence that says what to do (the Kit's APIError). The shop's server and the
// demo's in-browser stand-in (src/demo/api.ts) both fail with these.

/** Not a code the server sends: the request never got an answer. */
export const OFFLINE = 'offline';

export const OFFLINE_MESSAGE = "We couldn't reach the shop. Check your internet connection and try again.";

/** The API's error codes the site handles by name. */
export const ErrorCode = {
  invalidRequest: 'invalid_request',
  unauthorized: 'unauthorized',
  notFound: 'not_found',
  slotTaken: 'slot_taken',
  notCancellable: 'not_cancellable',
  outsideHours: 'outside_hours',
  tooSoon: 'too_soon',
  tooFar: 'too_far',
  rateLimited: 'rate_limited',
  cardRequired: 'card_required',
  policyChanged: 'policy_changed',
  lateCancelFee: 'late_cancel_fee',
  stripeNotConfigured: 'stripe_not_configured',
  serverError: 'server_error',
} as const;

export class ApiError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, message: string, status: number) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.status = status;
  }

  /** The request never got an answer: the booking may still have gone through. */
  get isOffline(): boolean {
    return this.code === OFFLINE;
  }
}

/** A friendly sentence for a code when the server didn't send one (the Kit's `userMessage`). */
export function defaultMessage(code: string, status: number): string {
  switch (code) {
    case OFFLINE:
      return OFFLINE_MESSAGE;
    case ErrorCode.invalidRequest:
      return "Something in that request wasn't right. Check the details and try again.";
    case ErrorCode.notFound:
      return "We couldn't find that. It may have been removed.";
    case ErrorCode.slotTaken:
      return 'Someone just booked that time. Pick another one.';
    case ErrorCode.notCancellable:
      return "This appointment can't be cancelled anymore. Call the shop if you need to change it.";
    case ErrorCode.rateLimited:
      return "That's a lot of tries in a short time. Wait a little and try again, or call the shop.";
    case ErrorCode.outsideHours:
      return "That time is outside the shop's hours. Pick another time.";
    case ErrorCode.tooSoon:
      return 'That time is too soon to book. Pick a later time.';
    case ErrorCode.tooFar:
      return 'That day is too far ahead to book. Pick an earlier day.';
    case ErrorCode.cardRequired:
      return "Add a card to book this time. You won't be charged now.";
    case ErrorCode.policyChanged:
      return 'The no-show policy for this booking just changed. Check it and book again.';
    default:
      return status >= 500 || status === 0
        ? 'Something went wrong on our side. Try again in a moment, or call the shop.'
        : "Something in that request wasn't right. Check the details and try again.";
  }
}

/** What a response that isn't 2xx becomes: the contract's error envelope when there is one. */
export async function errorFromResponse(response: Response): Promise<ApiError> {
  let code: string | null = null;
  let message = '';
  try {
    const body: unknown = await response.json();
    const error = (body as { error?: { code?: unknown; message?: unknown } } | null)?.error;
    if (typeof error?.code === 'string') code = error.code;
    if (typeof error?.message === 'string') message = error.message.trim().slice(0, 300);
  } catch {
    // Not JSON (a proxy's error page): guessed from the status below.
  }
  if (!code) {
    const status = response.status;
    code =
      status === 404 ? ErrorCode.notFound : status === 401 ? ErrorCode.unauthorized : status === 429 ? ErrorCode.rateLimited : status >= 500 ? ErrorCode.serverError : ErrorCode.invalidRequest;
  }
  return new ApiError(code, message || defaultMessage(code, response.status), response.status);
}

export function isApiError(error: unknown): error is ApiError {
  return error instanceof ApiError;
}

/** The sentence to show for any error. */
export function errorMessage(error: unknown): string {
  return isApiError(error) ? error.message : defaultMessage(ErrorCode.serverError, 500);
}
