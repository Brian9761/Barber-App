import { z } from 'zod';
import { ApiError } from './http.js';
import { isDate, parseInstant } from './time.js';

// Input rules shared by the public and owner endpoints. Messages are written for
// the person using the app, since the apps show them as is.

const CONTROL_CHARS = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;
const CONTROL_CHARS_EXCEPT_NEWLINES = /[\u0000-\u0009\u000b\u000c\u000e-\u001f\u007f-\u009f\u2028\u2029]/;
const EMAIL_RE = /^[^\s@<>()[\]\\,;:"]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$/;

/** Length in characters as people count them (code points, so emoji count once). */
export function charLength(text: string): number {
  return [...text].length;
}

/**
 * A US mobile or landline number in E.164 ("+14423413053"), or null if it
 * isn't one. Accepts the usual ways of typing it: "(442) 341-3053",
 * "442.341.3053", "+1 442 341 3053", "1-442-341-3053".
 */
export function normalizeUSPhone(input: string): string | null {
  const text = input.trim();
  if (!/^\+?[\d\s().-]+$/.test(text)) return null;
  let digits = text.replace(/\D/g, '');
  if (text.startsWith('+')) {
    if (!digits.startsWith('1')) return null;
    digits = digits.slice(1);
  } else if (digits.length === 11 && digits.startsWith('1')) {
    digits = digits.slice(1);
  }
  // NANP: NXX-NXX-XXXX, where N is 2-9. N11 codes (411, 911…) aren't area codes or exchanges.
  if (!/^[2-9]\d{2}[2-9]\d{6}$/.test(digits)) return null;
  if (/^.11/.test(digits) || /^.11/.test(digits.slice(3))) return null;
  return `+1${digits}`;
}

/** Trimmed, 1–60 characters, one line. */
export const personName = z
  .string({ error: 'Enter your name.' })
  .trim()
  .refine((v) => v.length > 0, { error: 'Enter your name.' })
  .refine((v) => charLength(v) <= 60, { error: 'Keep the name to 60 characters or fewer.' })
  .refine((v) => !CONTROL_CHARS.test(v), { error: 'The name has characters we can’t use.' });

export const usPhone = z
  .string({ error: 'Enter a US mobile number.' })
  .transform((v, ctx) => {
    const phone = normalizeUSPhone(v);
    if (!phone) {
      ctx.addIssue({ code: 'custom', message: 'Enter a US mobile number, like (442) 341-3053.' });
      return z.NEVER;
    }
    return phone;
  });

/** Optional text: empty or missing becomes null. */
function optionalText(max: number, tooLong: string, label: string) {
  return z
    .string({ error: `The ${label} must be text.` })
    .nullish()
    .transform((v) => {
      const t = v?.trim() ?? '';
      return t === '' ? null : t;
    })
    .refine((v) => v === null || charLength(v) <= max, { error: tooLong })
    .refine((v) => v === null || !CONTROL_CHARS_EXCEPT_NEWLINES.test(v), { error: `The ${label} has characters we can’t use.` });
}

export const note = optionalText(300, 'Keep the note to 300 characters or fewer.', 'note');

export const email = z
  .string({ error: 'Enter a valid email address.' })
  .nullish()
  .transform((v) => {
    const t = v?.trim() ?? '';
    return t === '' ? null : t;
  })
  .refine((v) => v === null || (v.length <= 254 && EMAIL_RE.test(v)), { error: 'Enter a valid email address.' });

export const instant = z
  .string({ error: 'Times must be ISO 8601, like 2026-11-02T18:00:00Z.' })
  .transform((v, ctx) => {
    const date = parseInstant(v);
    if (!date) {
      ctx.addIssue({ code: 'custom', message: 'Times must be ISO 8601, like 2026-11-02T18:00:00Z.' });
      return z.NEVER;
    }
    return date;
  });

export const calendarDate = z
  .string({ error: 'Dates must look like 2026-11-02.' })
  .refine(isDate, { error: 'Dates must look like 2026-11-02.' });

export const shortId = z.string({ error: 'An id is missing.' }).min(1, { error: 'An id is missing.' }).max(200);

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Parses `input` or throws a 400 with the first problem in plain words. */
export function parse<S extends z.ZodType>(schema: S, input: unknown): z.output<S> {
  const result = schema.safeParse(input);
  if (result.success) return result.data;
  throw new ApiError('invalid_request', describeIssue(result.error.issues[0]));
}

function describeIssue(issue: z.core.$ZodIssue | undefined): string {
  if (!issue) return "Something in the request isn't right.";
  const field = issue.path.map(String).join('.');
  // Our own messages are sentences ending in a period; zod's defaults don't, and get the field name in front.
  if (issue.code === 'custom' || issue.message.endsWith('.')) return issue.message;
  if (issue.code === 'unrecognized_keys') return `Unexpected field${issue.keys.length > 1 ? 's' : ''}: ${issue.keys.join(', ')}.`;
  if (issue.code === 'invalid_type' && /received undefined$/.test(issue.message)) return `${field || 'A field'} is missing.`;
  return field ? `${field}: ${issue.message}.` : `${issue.message}.`;
}
