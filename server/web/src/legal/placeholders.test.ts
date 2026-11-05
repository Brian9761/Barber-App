import { describe, expect, it } from 'vitest';
import { asDraft, findPlaceholders, isInstruction, NOT_IN_EFFECT, placeholderNote, placeholderText, TO_BE_CONFIRMED } from './placeholders';

// The documents' placeholders: where they are (for the strict build's message), and what a draft
// says in their place, never the owner's checklist.

describe('finding placeholders', () => {
  it('gives each one with its line and column, several on a line too', () => {
    const text = '# Title\n\n**Effective date:** [TO FILL IN: the day]\\\nCall or email [TO FILL IN: the email] or [TO FILL IN: the other].';
    expect(findPlaceholders(text)).toEqual([
      { line: 3, column: 21, raw: '[TO FILL IN: the day]' },
      { line: 4, column: 15, raw: '[TO FILL IN: the email]' },
      { line: 4, column: 42, raw: '[TO FILL IN: the other]' },
    ]);
  });

  it('finds one left open at the end of its line', () => {
    expect(findPlaceholders('Text [TO FILL IN: never closed')).toEqual([{ line: 1, column: 6, raw: '[TO FILL IN: never closed' }]);
  });

  it('finds nothing in a finished document', () => {
    expect(findPlaceholders('# Privacy Policy\n\n**Effective date:** December 1, 2026')).toEqual([]);
  });
});

describe('what a draft shows in its place', () => {
  it('says what the shop will add', () => {
    expect(placeholderNote("[TO FILL IN: the shop's email address]")).toBe("To be added by the shop: the shop's email address");
    expect(placeholderText('[TO FILL IN: the same day]')).toBe('the same day');
  });

  it('never names the owner’s checklist, or a “see section…” meant for the owner', () => {
    expect(placeholderText("[TO FILL IN: the shop's refund policy for services and for products; see section 2 of OWNER-CHECKLIST.md.]")).toBe(
      "the shop's refund policy for services and for products",
    );
    expect(placeholderText('[TO FILL IN: the refund policy (see OWNER-CHECKLIST.md)]')).toBe('the refund policy');
    expect(placeholderText('[TO FILL IN: the hours, see section 4]')).toBe('the hours');
    expect(placeholderText('[TO FILL IN: the hours. See section 4 of the checklist.]')).toBe('the hours');
    expect(placeholderNote('[TO FILL IN: see OWNER-CHECKLIST.md]')).toBe('To be added by the shop');
  });

  it('keeps the rest of the shop’s words, without a full stop at the end', () => {
    expect(
      placeholderText(
        "[TO FILL IN: keep this line only once you've confirmed this number takes texts and someone reads them during opening hours; otherwise delete every mention of texting us in this statement.]",
      ),
    ).toBe("keep this line only once you've confirmed this number takes texts and someone reads them during opening hours; otherwise delete every mention of texting us in this statement");
    expect(placeholderText('[TO FILL IN: remove "text us" unless texts are confirmed]')).toBe('remove "text us" unless texts are confirmed');
  });

  it('ends the sentence a placeholder ended, so the next one doesn’t run on from the note', () => {
    // terms.md: "**Refunds.** [TO FILL IN: …; see section 2 of OWNER-CHECKLIST.md.] Card refunds go back to the card you paid with."
    expect(placeholderNote("[TO FILL IN: the shop's refund policy for services and for products; see section 2 of OWNER-CHECKLIST.md.]")).toBe(
      "To be added by the shop: the shop's refund policy for services and for products.",
    );
    // One inside a sentence stays inside it: "email us at [TO FILL IN: the shop's email address], or visit the shop".
    expect(placeholderNote("[TO FILL IN: the shop's email address]")).toBe("To be added by the shop: the shop's email address");
  });
});

describe('an instruction to the owner, in a draft', () => {
  // accessibility.md's lines about texting the shop: what the owner must do, not something to add.
  const LINE_13 = '[TO FILL IN: remove "text us" unless texts are confirmed]';
  const LINE_52 =
    "[TO FILL IN: keep this line only once you've confirmed this number takes texts and someone reads them during opening hours; otherwise delete every mention of texting us in this statement.]";
  const LINE_62 = '[TO FILL IN: keep this line only if texts are confirmed, as in "Other ways to book and get help"]';

  it('says only that the shop has yet to confirm it, never the instruction itself', () => {
    expect(TO_BE_CONFIRMED).toBe('To be confirmed by the shop');
    // "…call through a relay service by dialing 711, text us [note] or email us…"
    expect(placeholderNote(LINE_13)).toBe('To be confirmed by the shop');
    // "Text us at (442) 341-3053. [note]" ends its sentence.
    expect(placeholderNote(LINE_52)).toBe('To be confirmed by the shop.');
    // "Text: (442) 341-3053 [note]"
    expect(placeholderNote(LINE_62)).toBe('To be confirmed by the shop');
    for (const raw of [LINE_13, LINE_52, LINE_62]) {
      expect(isInstruction(raw), raw).toBe(true);
      expect(placeholderNote(raw)).not.toMatch(/keep|remove|delete|otherwise|you've/i);
    }
  });

  it('tells an instruction from something to add', () => {
    for (const raw of ["[TO FILL IN: the shop's email address]", '[TO FILL IN: the same day]', '[TO FILL IN: the day this statement was last checked against the live website and apps]']) {
      expect(isInstruction(raw), raw).toBe(false);
    }
    for (const raw of ['[TO FILL IN: Delete this line if…]', '[TO FILL IN: replace with the hours]', '[TO FILL IN:choose one]']) {
      expect(isInstruction(raw), raw).toBe(true);
    }
  });
});

describe('a document as a draft', () => {
  it('reads “Not in effect yet” for its effective date and last update', () => {
    const draft = asDraft('# Terms\n\n**Effective date:** [TO FILL IN: the day this version goes live]\\\n**Last updated:** [TO FILL IN: the same day]\n\nText.');
    expect(draft).toBe(`# Terms\n\n**Effective date:** ${NOT_IN_EFFECT}\\\n**Last updated:** ${NOT_IN_EFFECT}\n\nText.`);
  });

  it('leaves its other placeholders for the page to show as notes', () => {
    const text = "**Last reviewed:** [TO FILL IN: the day it was checked]\n\nEmail [TO FILL IN: the shop's email address].";
    expect(asDraft(text)).toBe(text);
  });
});
