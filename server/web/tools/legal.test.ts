// @vitest-environment node
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { loadEnv, type ConfigEnv, type UserConfig } from 'vite';
import { LEGAL_FILES, legalDocuments, legalStrict, readLegalFiles, strictFailure, unfinished } from './legal.js';

// A strict build publishes the legal documents as they are, so it stops while any placeholder
// is left in them, saying which file and line; every other build is a draft. Checked on the
// documents as they are today, and on a copy with every placeholder filled in.

const DOCS = fileURLToPath(new URL('../../../docs/legal', import.meta.url));

/** What the shop might write in each placeholder's place. */
function filledIn(text: string): string {
  return text.replace(/\[TO FILL IN:([^\]]*)\]/g, (_, what: string) => {
    if (/email/.test(what)) return 'hello@izzyclipz.example';
    if (/\bday\b/.test(what)) return 'December 1, 2026';
    // The owner's instructions ("keep this line only if…") just go.
    return '';
  });
}

/** The build's plugin at the start of a build: the message it stops with, or null when it goes ahead. */
function buildStart(strict: boolean, dir: string): string | null {
  const hook = legalDocuments({ strict, dir }).buildStart as (this: { error(message: string): never }) => void;
  try {
    hook.call({
      error(message: string): never {
        throw new Error(message);
      },
    });
    return null;
  } catch (error) {
    return (error as Error).message;
  }
}

let copy: string | null = null;

afterEach(() => {
  if (copy) rmSync(copy, { recursive: true, force: true });
  copy = null;
});

describe('which builds are strict', () => {
  it('a build asked to be (LEGAL_STRICT=1), or the shop’s own site in production on Vercel', () => {
    expect(legalStrict({ LEGAL_STRICT: '1' }, false)).toBe(true);
    expect(legalStrict({ LEGAL_STRICT: '1' }, true)).toBe(true);
    expect(legalStrict({ VERCEL_ENV: 'production' }, false)).toBe(true);
  });

  it('not the demo, previews, local or CI builds', () => {
    expect(legalStrict({ VERCEL_ENV: 'production' }, true)).toBe(false);
    expect(legalStrict({ VERCEL_ENV: 'preview' }, false)).toBe(false);
    expect(legalStrict({}, false)).toBe(false);
    expect(legalStrict({ CI: 'true' }, false)).toBe(false);
    expect(legalStrict({ LEGAL_STRICT: '0' }, false)).toBe(false);
  });
});

describe('a strict build', () => {
  it('stops on the documents as they are today, naming each file and line still to fill in', () => {
    const message = buildStart(true, DOCS);
    expect(message).not.toBeNull();
    expect(message).toContain("The legal documents aren't ready to publish");
    expect(message).toContain('LEGAL_STRICT=1');
    for (const file of LEGAL_FILES) expect(message).toContain(`docs/legal/${file}:3: [TO FILL IN: the day this version goes live]`);
    expect(message).toContain("docs/legal/privacy.md:15: [TO FILL IN: the shop's email address]");
    expect(message).toContain('docs/legal/terms.md:58: [TO FILL IN: the shop');
    expect(message).toContain('docs/legal/accessibility.md:5: [TO FILL IN: the day this statement was last checked');
    // Every placeholder, each on its own line.
    const left = unfinished(readLegalFiles(DOCS));
    expect(left.length).toBeGreaterThanOrEqual(LEGAL_FILES.length * 2);
    expect(message!.split('\n').filter((line) => line.startsWith('  docs/legal/'))).toHaveLength(left.length);
  });

  it('goes ahead once every placeholder is filled in', () => {
    copy = mkdtempSync(join(tmpdir(), 'izzy-legal-'));
    for (const file of LEGAL_FILES) writeFileSync(join(copy, file), filledIn(readFileSync(join(DOCS, file), 'utf8')));
    expect(unfinished(readLegalFiles(copy))).toEqual([]);
    expect(buildStart(true, copy)).toBeNull();
  });

  it('stops for a single placeholder left anywhere, at its line', () => {
    copy = mkdtempSync(join(tmpdir(), 'izzy-legal-'));
    for (const file of LEGAL_FILES) writeFileSync(join(copy, file), filledIn(readFileSync(join(DOCS, file), 'utf8')));
    const terms = readFileSync(join(copy, 'terms.md'), 'utf8').split('\n');
    terms[57] = '- **Refunds.** [TO FILL IN: the refund policy]';
    writeFileSync(join(copy, 'terms.md'), terms.join('\n'));
    const message = buildStart(true, copy);
    expect(message).toContain('a placeholder is still to be filled in');
    expect(message).toContain('docs/legal/terms.md:58: [TO FILL IN: the refund policy]');
  });
});

describe('every other build', () => {
  it('goes ahead as a draft, placeholders and all', () => {
    expect(buildStart(false, DOCS)).toBeNull();
  });
});

describe('the message', () => {
  it('says how many are left and what to do', () => {
    const message = strictFailure(['docs/legal/privacy.md:3: [TO FILL IN: x]', 'docs/legal/terms.md:4: [TO FILL IN: y]']);
    expect(message.split('\n')).toEqual([
      "The legal documents aren't ready to publish: 2 placeholders are still to be filled in.",
      expect.stringContaining('strict build'),
      '  docs/legal/privacy.md:3: [TO FILL IN: x]',
      '  docs/legal/terms.md:4: [TO FILL IN: y]',
      expect.stringContaining('Fill them in'),
    ]);
  });
});

describe('how the build tells the pages', () => {
  // The pages read import.meta.env.VITE_LEGAL_STRICT (src/legal/mode.ts; tested there): the build's
  // config sets it from LEGAL_STRICT and VERCEL_ENV, and Vite hands every VITE_ variable to the site.
  async function strictFor(env: { LEGAL_STRICT?: string; VERCEL_ENV?: string }, mode = 'production'): Promise<string | undefined> {
    vi.stubEnv('LEGAL_STRICT', env.LEGAL_STRICT ?? '');
    vi.stubEnv('VERCEL_ENV', env.VERCEL_ENV ?? '');
    vi.stubEnv('VITE_DEMO_MODE', '');
    vi.stubEnv('VITE_LEGAL_STRICT', '');
    const { default: config } = await import('../vite.config.js');
    (config as (env: ConfigEnv) => UserConfig)({ mode, command: 'build' });
    return loadEnv(mode, fileURLToPath(new URL('..', import.meta.url)), 'VITE_').VITE_LEGAL_STRICT;
  }

  it('a strict build says so to the site; every other build doesn’t', async () => {
    expect(await strictFor({ LEGAL_STRICT: '1' })).toBe('1');
    expect(await strictFor({ VERCEL_ENV: 'production' })).toBe('1');
    expect(await strictFor({ VERCEL_ENV: 'production' }, 'demo')).toBe('');
    expect(await strictFor({ VERCEL_ENV: 'preview' })).toBe('');
    expect(await strictFor({})).toBe('');
  });
});
