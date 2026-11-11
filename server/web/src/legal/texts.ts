// The four documents' words, from docs/legal at the root of the repository, built into the
// legal pages' own script (only those pages load it). In a strict build the build itself first
// checks that no "[TO FILL IN" is left in them (tools/legal.ts).

import accessibility from '../../../../docs/legal/accessibility.md?raw';
import cancellationPolicy from '../../../../docs/legal/cancellation-policy.md?raw';
import privacy from '../../../../docs/legal/privacy.md?raw';
import terms from '../../../../docs/legal/terms.md?raw';
import type { LegalDocumentId } from './documents';

export const LEGAL_TEXTS: Record<LegalDocumentId, string> = {
  privacy,
  terms,
  'cancellation-policy': cancellationPolicy,
  accessibility,
};
