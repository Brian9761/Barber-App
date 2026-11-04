import { describe, expect, it } from 'vitest';
import phoneNumbers from '../../../test/fixtures/phone-numbers.json';
import { displayPhone, emailProblem, formatPhone, nameProblem, noteProblem, parseUSPhone, phoneProblem, toE164 } from './phone';

describe('US phone numbers', () => {
  // The server's normalizeUSPhone and the Kit's PhoneNumber(parsing:) agree on every one of these.
  it.each(phoneNumbers.accepted)('takes %j as %s', (typed, e164) => {
    const digits = parseUSPhone(typed);
    expect(digits).not.toBeNull();
    expect(toE164(digits!)).toBe(e164);
  });

  it.each(phoneNumbers.rejected)('turns down %j', (typed) => {
    expect(parseUSPhone(typed)).toBeNull();
  });

  it('shows a number the way people write it', () => {
    expect(formatPhone('4423413053')).toBe('(442) 341-3053');
    expect(displayPhone('+1 442 341 3053')).toBe('(442) 341-3053');
    expect(displayPhone(' 442.341.3053 ')).toBe('(442) 341-3053');
    expect(displayPhone('call me')).toBe('call me');
  });
});

describe('your details', () => {
  it('ask for a name in the app’s words', () => {
    expect(nameProblem('  ')).toBe("Enter your name so the shop knows who's coming.");
    expect(nameProblem('A'.repeat(61))).toBe('Use 60 characters or fewer.');
    // Characters as people count them: an emoji is one.
    expect(nameProblem('💈'.repeat(60))).toBeNull();
    expect(nameProblem(' Ana Flores ')).toBeNull();
  });

  it('ask for a US mobile number', () => {
    expect(phoneProblem('')).toBe('Enter your mobile number so the shop can reach you.');
    expect(phoneProblem('555-0123')).toBe('Enter a 10-digit US number, like (442) 341-3053.');
    expect(phoneProblem('(442) 555-0123')).toBeNull();
  });

  it('take the email only if it’s one the server takes, and it can be left empty', () => {
    expect(emailProblem('')).toBeNull();
    expect(emailProblem(' ana@example.com ')).toBeNull();
    expect(emailProblem('ana@example')).toBe('Enter an email address like name@example.com, or leave it empty.');
    expect(emailProblem('ana example.com')).not.toBeNull();
  });

  it('keep the note to 300 characters', () => {
    expect(noteProblem('x'.repeat(300))).toBeNull();
    expect(noteProblem('x'.repeat(301))).toBe('Keep the note to 300 characters or fewer.');
  });
});
