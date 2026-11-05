// The shop's four legal documents, as the site links them: each one's address, its page title
// and the name its links use. Their words are in docs/legal/*.md, read only by the pages
// themselves (./texts.ts), so the rest of the site never carries them.

export type LegalDocumentId = 'privacy' | 'terms' | 'cancellation-policy' | 'accessibility';

export interface LegalDocument {
  id: LegalDocumentId;
  /** "/privacy". */
  path: `/${LegalDocumentId}`;
  /** Its file in docs/legal: "privacy.md". */
  file: `${LegalDocumentId}.md`;
  /** The page's title, and what links to it say: "Privacy Policy". */
  title: string;
  description: string;
}

function describe(id: LegalDocumentId, title: string, description: string): LegalDocument {
  return { id, path: `/${id}`, file: `${id}.md`, title, description };
}

/** In the order the footer lists them. */
export const LEGAL_DOCUMENTS: readonly LegalDocument[] = [
  describe(
    'privacy',
    'Privacy Policy',
    "What Izzy Clipz Barbershop collects through its website and apps, why, who else receives it, how long it's kept, and your choices.",
  ),
  describe(
    'terms',
    'Terms of Service',
    'The rules for using the Izzy Clipz Barbershop website and apps, and for booking appointments through them.',
  ),
  describe(
    'cancellation-policy',
    'Cancellation & No-Show Policy',
    'How to cancel an appointment at Izzy Clipz Barbershop, and when a fee may be charged for cancelling late or not coming.',
  ),
  describe(
    'accessibility',
    'Accessibility',
    "Izzy Clipz Barbershop's accessibility statement: what it's done so far, what isn't perfect yet, and other ways to book and get help.",
  ),
];

export function legalDocument(id: LegalDocumentId): LegalDocument {
  return LEGAL_DOCUMENTS.find((document) => document.id === id)!;
}

/**
 * Where a link in the documents goes on this site: "cancellation-policy.md" (or
 * "./privacy.md#saved-cards") is that document's page, its section's anchor kept. Null for
 * any other link, which stays as it is.
 */
export function siteLinkFor(href: string): string | null {
  const match = /^(?:\.\/)?([a-z-]+)\.md(#[^\s]*)?$/.exec(href);
  if (!match) return null;
  const found = LEGAL_DOCUMENTS.find((document) => document.file === `${match[1]}.md`);
  return found ? `${found.path}${match[2] ?? ''}` : null;
}
