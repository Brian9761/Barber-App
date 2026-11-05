// The legal documents' placeholders, like "[TO FILL IN: the shop's email address]": what the
// shop still has to add before the documents can be published. The build (tools/legal.ts)
// refuses to publish the site for real while any is left; until then the pages are drafts and
// show each one as a note ("To be added by the shop: the shop's email address").
//
// No imports: the build reads this file in Node, the site in the browser.

/** How every placeholder starts. */
export const PLACEHOLDER_START = '[TO FILL IN';

export interface Placeholder {
  /** Where it starts, from 1. */
  line: number;
  column: number;
  /** As written: "[TO FILL IN: the same day]". */
  raw: string;
}

/** Every placeholder in `text`, in order, with its line and column. */
export function findPlaceholders(text: string): Placeholder[] {
  const found: Placeholder[] = [];
  text.split(/\r?\n/).forEach((lineText, index) => {
    for (let at = lineText.indexOf(PLACEHOLDER_START); at !== -1; at = lineText.indexOf(PLACEHOLDER_START, at + 1)) {
      const end = lineText.indexOf(']', at);
      found.push({ line: index + 1, column: at + 1, raw: end === -1 ? lineText.slice(at) : lineText.slice(at, end + 1) });
    }
  });
  return found;
}

/** A clause that only points the owner to the checklist ("see section 2 of OWNER-CHECKLIST.md"). */
const CHECKLIST_POINTER = /OWNER-CHECKLIST|\bsee section\b/i;

/**
 * What the placeholder says is still to come, for visitors: "[TO FILL IN: the shop's refund
 * policy for services and for products; see section 2 of OWNER-CHECKLIST.md.]" is "the shop's
 * refund policy for services and for products". Visitors never see the checklist's name, or a
 * "see section…" meant for the owner.
 */
export function placeholderText(raw: string): string {
  const inner = raw
    .replace(/^\[TO FILL IN:?\s*/, '')
    .replace(/\]$/, '')
    // A parenthesis pointing to the checklist goes first...
    .replace(/\s*\(([^)]*)\)/g, (match, inside: string) => (CHECKLIST_POINTER.test(inside) ? '' : match));
  // ...then each clause that does (clauses end at a semicolon, a full stop, or before ", see").
  const parts = inner.split(/(;\s+|\.\s+|,\s+(?=see\b))/i);
  let kept = '';
  for (let i = 0; i < parts.length; i += 2) {
    const clause = parts[i] ?? '';
    if (CHECKLIST_POINTER.test(clause)) continue;
    kept += (kept ? (parts[i - 1] ?? ' ') : '') + clause;
  }
  return kept.trim().replace(/[\s.;,:]+$/, '');
}

/** The note a draft shows in a placeholder's place. */
export function placeholderNote(raw: string): string {
  const what = placeholderText(raw);
  return what ? `To be added by the shop: ${what}` : 'To be added by the shop';
}

/** The lines that date a document; in a draft they read "Not in effect yet". */
const DATE_LINE = /^(\*\*(?:Effective date|Last updated):\*\*\s*)\[TO FILL IN[^\]]*\]/gm;

/** What a draft says instead of the dates it doesn't have yet. */
export const NOT_IN_EFFECT = 'Not in effect yet';

/**
 * A document as a draft shows it: its "Effective date" and "Last updated" read "Not in effect
 * yet" while their dates are still to be filled in. (Its other placeholders stay, for the page to
 * show as notes.)
 */
export function asDraft(text: string): string {
  return text.replace(DATE_LINE, `$1${NOT_IN_EFFECT}`);
}
