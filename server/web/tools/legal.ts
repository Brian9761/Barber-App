// The build's check of the legal documents (docs/legal at the root of the repository), which the
// site renders as /privacy, /terms, /cancellation-policy and /accessibility. They aren't in effect
// until the shop publishes them: every build is a draft, except a strict one, which publishes
// them as they are and so refuses to build while any "[TO FILL IN: …]" is left.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { Plugin } from 'vite';
import { findPlaceholders } from '../src/legal/placeholders.js';

/** The four documents the site publishes, as docs/legal names them. */
export const LEGAL_FILES = ['privacy.md', 'terms.md', 'cancellation-policy.md', 'accessibility.md'] as const;

/**
 * Whether this build publishes the documents as they are: when asked (LEGAL_STRICT=1), or for
 * the shop's own site in production on Vercel (VERCEL_ENV=production). The demo stays a draft
 * unless asked: it's never the shop's site.
 */
export function legalStrict(env: Record<string, string | undefined>, demo: boolean): boolean {
  return env.LEGAL_STRICT === '1' || (env.VERCEL_ENV === 'production' && !demo);
}

/**
 * Every placeholder left in the documents, as "docs/legal/terms.md:58: [TO FILL IN: …]".
 * `read` gives a file's text by its name (the files in docs/legal, unless a test says otherwise).
 */
export function unfinished(read: (file: (typeof LEGAL_FILES)[number]) => string, folder = 'docs/legal'): string[] {
  return LEGAL_FILES.flatMap((file) => findPlaceholders(read(file)).map((placeholder) => `${folder}/${file}:${placeholder.line}: ${placeholder.raw}`));
}

/** The documents in `dir`, read from disk. */
export function readLegalFiles(dir: string): (file: (typeof LEGAL_FILES)[number]) => string {
  return (file) => readFileSync(join(dir, file), 'utf8');
}

/** What a strict build says when it stops: which file and line still has a placeholder, and what to do. */
export function strictFailure(left: string[]): string {
  return [
    `The legal documents aren't ready to publish: ${left.length === 1 ? 'a placeholder is' : `${left.length} placeholders are`} still to be filled in.`,
    'This is a strict build (LEGAL_STRICT=1, or VERCEL_ENV=production for the shop’s own site), which publishes the documents as they are.',
    ...left.map((line) => `  ${line}`),
    'Fill them in (docs/legal/OWNER-CHECKLIST.md), or build without LEGAL_STRICT for a draft that says it isn’t in effect yet.',
  ].join('\n');
}

/**
 * The build's plugin: a strict build stops at its start, saying which file and line, while any
 * placeholder is left in the documents in `dir`. Every other build goes ahead as a draft.
 */
export function legalDocuments({ strict, dir }: { strict: boolean; dir: string }): Plugin {
  return {
    name: 'izzy-legal-documents',
    buildStart() {
      if (!strict) return;
      const left = unfinished(readLegalFiles(dir));
      if (left.length > 0) this.error(strictFailure(left));
    },
  };
}
