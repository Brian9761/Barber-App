// The build's check of the legal documents (docs/legal at the root of the repository), which the
// site renders as /privacy, /terms, /cancellation-policy and /accessibility. They aren't in effect
// until the shop publishes them: every build is a draft, except a strict one, which publishes
// them as they are and so refuses to build while any "[TO FILL IN: …]" is left, or while the
// shop's catalog doesn't yet say who runs the shop and its email (the footer and "Review and book"
// show them before any card is saved: src/components/OperatorLines.tsx; until then they say only
// what's known, the shop and its address).

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

/**
 * What the shop's catalog (`catalog`, data/catalog.json's text, from the Kit) doesn't say yet of who
 * runs the shop: the LLC's registered name and the shop's email (both "" until the owner gives
 * them), which the footer and "Review and book" show before any card is saved (Business and
 * Professions Code §17538(d)), as "server/data/catalog.json: shop.legalName (…)".
 */
export function unfinishedOperator(catalog: string, file = 'server/data/catalog.json'): string[] {
  const shop = (JSON.parse(catalog) as { shop?: { legalName?: unknown; email?: unknown } }).shop ?? {};
  const given = (value: unknown) => typeof value === 'string' && value.trim() !== '';
  return [
    ...(given(shop.legalName) ? [] : [`${file}: shop.legalName (the LLC's exact registered name, which runs the shop)`]),
    ...(given(shop.email) ? [] : [`${file}: shop.email (the shop's email address)`]),
  ];
}

/** What a strict build says when it stops: which file and line still has a placeholder, and what to do. */
export function strictFailure(left: string[]): string {
  return [
    `The legal documents aren't ready to publish: ${left.length === 1 ? 'a placeholder is' : `${left.length} placeholders are`} still to be filled in.`,
    'This is a strict build (LEGAL_STRICT=1, or VERCEL_ENV=production for the shop’s own site), which publishes the documents as they are.',
    ...left.map((line) => `  ${line}`),
    'Fill them in (docs/legal/OWNER-CHECKLIST.md; who runs the shop and its email go in Packages/IzzyClipzKit/Sources/IzzyClipzKit/IzzyClipzData.swift, exported to server/data/catalog.json as the README says), or build without LEGAL_STRICT for a draft that says it isn’t in effect yet.',
  ].join('\n');
}

/**
 * The build's plugin: a strict build stops at its start, saying which file and line, while any
 * placeholder is left in the documents in `dir`, or the shop's catalog (`catalog`, a path to
 * data/catalog.json) doesn't say who runs the shop and its email. Every other build goes ahead as a
 * draft, where the footer and "Review and book" say only what's known (the shop and its address).
 */
export function legalDocuments({ strict, dir, catalog }: { strict: boolean; dir: string; catalog: string }): Plugin {
  return {
    name: 'izzy-legal-documents',
    buildStart() {
      if (!strict) return;
      const left = [...unfinished(readLegalFiles(dir)), ...unfinishedOperator(readFileSync(catalog, 'utf8'))];
      if (left.length > 0) this.error(strictFailure(left));
    },
  };
}
