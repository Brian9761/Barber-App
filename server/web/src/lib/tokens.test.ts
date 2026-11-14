import { describe, expect, it, vi } from 'vitest';
import { base64url, isToken, newToken, TOKEN_LENGTH } from './tokens';

describe('manage and card tokens', () => {
  it('are 32 random bytes in base64url without padding: 43 characters', () => {
    const token = newToken();
    expect(token).toHaveLength(TOKEN_LENGTH);
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(isToken(token)).toBe(true);
    expect(newToken()).not.toBe(token);
  });

  it("come from the browser's secure random number generator", () => {
    const spy = vi.spyOn(crypto, 'getRandomValues');
    newToken();
    expect(spy).toHaveBeenCalledOnce();
    expect((spy.mock.calls[0]![0] as Uint8Array).length).toBe(32);
  });

  it('encode exactly like the server (Node’s base64url), in the canonical form', () => {
    for (const fill of [0, 1, 0x3f, 0xfb, 0xff]) {
      const bytes = new Uint8Array(32).fill(fill);
      expect(newToken(() => bytes)).toBe(Buffer.from(bytes).toString('base64url'));
    }
    const counting = Uint8Array.from({ length: 32 }, (_, i) => i * 7);
    const token = newToken(() => counting);
    expect(token).toBe(Buffer.from(counting).toString('base64url'));
    // The server takes only what 32 bytes encode to.
    expect(Buffer.from(token, 'base64url').toString('base64url')).toBe(token);
    // The contract test's card token: 32 bytes of 0x01.
    expect(newToken(() => new Uint8Array(32).fill(1))).toBe('AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE');
  });

  it('base64url-encodes any length like Node does', () => {
    for (const length of [0, 1, 2, 3, 4, 5, 31, 33]) {
      const bytes = Uint8Array.from({ length }, (_, i) => (i * 37 + 11) % 256);
      expect(base64url(bytes)).toBe(Buffer.from(bytes).toString('base64url'));
    }
  });

  it('turn down anything else', () => {
    const good = newToken();
    expect(isToken(good.slice(1))).toBe(false);
    expect(isToken(`${good}A`)).toBe(false);
    expect(isToken(`${good.slice(0, 42)}+`)).toBe(false);
    expect(isToken(`${good.slice(0, 42)}=`)).toBe(false);
    // The last character's two unused bits must be zero: "B" (1) isn't, "E" (4) is.
    expect(isToken(`${good.slice(0, 42)}B`)).toBe(false);
    expect(isToken(`${good.slice(0, 42)}E`)).toBe(true);
    expect(isToken(42)).toBe(false);
    expect(isToken(null)).toBe(false);
  });
});
