// The client's name, number and email, checked the way the app and the server
// check them, so the site never lets through something the server turns down.

/**
 * A US number typed any common way ("(442) 341-3053", "442.341.3053",
 * "+1 442 341 3053", "14423413053") as its 10 digits, or null. Exactly the
 * server's `normalizeUSPhone` (and the Kit's `PhoneNumber(parsing:)`): an area
 * code and exchange that start with 2–9 and aren't N11 codes; letters,
 * extensions and other symbols are turned down rather than guessed at.
 */
export function parseUSPhone(input: string): string | null {
  const text = input.trim();
  if (!/^\+?[\d\s().-]+$/.test(text)) return null;
  let digits = text.replace(/\D/g, '');
  if (text.startsWith('+')) {
    if (!digits.startsWith('1')) return null;
    digits = digits.slice(1);
  } else if (digits.length === 11 && digits.startsWith('1')) {
    digits = digits.slice(1);
  }
  if (!/^[2-9]\d{2}[2-9]\d{6}$/.test(digits)) return null;
  if (/^.11/.test(digits) || /^.11/.test(digits.slice(3))) return null;
  return digits;
}

/** "(442) 341-3053" for 10 digits. */
export function formatPhone(digits: string): string {
  return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6, 10)}`;
}

/** "+14423413053": the form the server stores. */
export function toE164(digits: string): string {
  return `+1${digits}`;
}

/** The number tidied for display, "(442) 341-3053", or as typed when it isn't one. */
export function displayPhone(input: string): string {
  const digits = parseUSPhone(input);
  return digits ? formatPhone(digits) : input.trim();
}

/** "tel:+14423413053". */
export function telLink(e164: string): string {
  return `tel:${e164}`;
}

export const MAX_NAME_LENGTH = 60;
export const MAX_NOTE_LENGTH = 300;
const MAX_EMAIL_LENGTH = 254;

/** Characters as people count them (code points, like the server), so an emoji counts once. */
export function charLength(text: string): number {
  return [...text].length;
}

/** What's wrong with the name, in the app's words, or null. */
export function nameProblem(name: string): string | null {
  const trimmed = name.trim();
  if (trimmed === '') return "Enter your name so the shop knows who's coming.";
  if (charLength(trimmed) > MAX_NAME_LENGTH) return `Use ${MAX_NAME_LENGTH} characters or fewer.`;
  return null;
}

/** What's wrong with the number, in the app's words, or null. */
export function phoneProblem(phone: string): string | null {
  if (phone.trim() === '') return 'Enter your mobile number so the shop can reach you.';
  if (!parseUSPhone(phone)) return 'Enter a 10-digit US number, like (442) 341-3053.';
  return null;
}

// The server's own rule (src/validation.ts).
const EMAIL_RE =
  /^[^\s@<>()[\]\\,;:"]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$/;

/** The email is optional; one that's there must be one the server takes. */
export function emailProblem(email: string): string | null {
  const trimmed = email.trim();
  if (trimmed === '') return null;
  if (trimmed.length > MAX_EMAIL_LENGTH || !EMAIL_RE.test(trimmed)) {
    return 'Enter an email address like name@example.com, or leave it empty.';
  }
  return null;
}

export function noteProblem(note: string): string | null {
  return charLength(note.trim()) > MAX_NOTE_LENGTH ? `Keep the note to ${MAX_NOTE_LENGTH} characters or fewer.` : null;
}
