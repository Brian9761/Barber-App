// Manage tokens and card tokens made in the browser, exactly like the app's
// IzzyAPI.ManageToken: 32 random bytes from the browser's secure random number
// generator, in base64url without padding (43 characters). The server takes
// only that canonical form (the last character's two unused bits are zero).

export const TOKEN_BYTES = 32;
export const TOKEN_LENGTH = 43;

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** Base64url without padding. */
export function base64url(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  for (; i + 2 < bytes.length; i += 3) {
    const n = ((bytes[i] ?? 0) << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
    out += ALPHABET[(n >> 18) & 63]! + ALPHABET[(n >> 12) & 63]! + ALPHABET[(n >> 6) & 63]! + ALPHABET[n & 63]!;
  }
  const rest = bytes.length - i;
  if (rest === 1) {
    const n = (bytes[i] ?? 0) << 16;
    out += ALPHABET[(n >> 18) & 63]! + ALPHABET[(n >> 12) & 63]!;
  } else if (rest === 2) {
    const n = ((bytes[i] ?? 0) << 16) | ((bytes[i + 1] ?? 0) << 8);
    out += ALPHABET[(n >> 18) & 63]! + ALPHABET[(n >> 12) & 63]! + ALPHABET[(n >> 6) & 63]!;
  }
  return out;
}

/** A new token. `random` fills the bytes; tests pass their own. */
export function newToken(random: (bytes: Uint8Array) => Uint8Array = (bytes) => crypto.getRandomValues(bytes)): string {
  return base64url(random(new Uint8Array(TOKEN_BYTES)));
}

/** Whether `value` is exactly what `newToken` makes: 43 base64url characters, the last with its unused bits clear. */
export function isToken(value: unknown): value is string {
  if (typeof value !== 'string' || value.length !== TOKEN_LENGTH) return false;
  for (const char of value) if (!ALPHABET.includes(char)) return false;
  return (ALPHABET.indexOf(value[TOKEN_LENGTH - 1]!) & 0b11) === 0;
}
