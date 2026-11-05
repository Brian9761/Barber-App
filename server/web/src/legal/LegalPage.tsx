// The four legal pages (/privacy, /terms, /cancellation-policy, /accessibility), drawn from the
// shop's own Markdown files (docs/legal) at a readable measure: the document's title as the
// page's one main heading, its dates, "On this page" with its sections, and its text. Links
// between the documents open their pages here; the shop's number calls it.
//
// Until the shop publishes them (a strict build, see tools/legal.ts), each page is a draft: a
// note at the top says so, the dates read "Not in effect yet", and every placeholder shows as
// "To be added by the shop: …".

import { Fragment, useEffect, useMemo, useState, useSyncExternalStore, type ReactNode } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Icon } from '../components/Icon';
import { Notice } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { isDemo } from '../demo/mode';
import { legalDocument, siteLinkFor, type LegalDocumentId } from './documents';
import { parseMarkdown, plainText, type Block, type Inline } from './markdown';
import { legalDraft } from './mode';
import { asDraft, placeholderNote } from './placeholders';
import { LEGAL_TEXTS } from './texts';
import './legal.css';

/** "Draft: not in effect yet." */
export const DRAFT_TITLE = 'Draft: not in effect yet.';
export const DRAFT_LINE = 'The shop will publish this when online booking opens.';
export const DEMO_DRAFT_LINE = 'This is the demo version of the website.';

export default function LegalPage({ id }: { id: LegalDocumentId }) {
  const document = legalDocument(id);
  usePageMeta(document.title, document.description);
  return <LegalArticle source={LEGAL_TEXTS[id]} draft={legalDraft()} demo={isDemo()} />;
}

/** A document's page from its Markdown: as a draft (with its note), or as published. */
export function LegalArticle({ source, draft, demo }: { source: string; draft: boolean; demo: boolean }) {
  const blocks = useMemo(() => parseMarkdown(draft ? asDraft(source) : source), [source, draft]);
  useScrollToSection(blocks);

  const [title, ...rest] = blocks;
  // The title, then its dates and opening lines, then "On this page" before the first section.
  const firstSection = rest.findIndex((block) => block.kind === 'heading' && block.level === 2);
  const opening = firstSection === -1 ? rest : rest.slice(0, firstSection);
  const sections = firstSection === -1 ? [] : rest.slice(firstSection);
  const contents = sections.filter((block): block is Extract<Block, { kind: 'heading' }> => block.kind === 'heading' && block.level === 2);

  return (
    <div className="legal container" data-testid="legal-page">
      <article className="legal__article" aria-labelledby={title?.kind === 'heading' ? title.id : undefined}>
        {draft ? (
          <Notice tone="info" title={DRAFT_TITLE} testId="legal-draft">
            <p>
              {DRAFT_LINE}
              {demo ? ` ${DEMO_DRAFT_LINE}` : ''}
            </p>
          </Notice>
        ) : null}
        {title ? <BlockView block={title} /> : null}
        {opening.map((block, index) => (
          <BlockView key={index} block={block} dates={index === 0 && isDateLine(block)} />
        ))}
        {contents.length > 0 ? <Contents headings={contents} /> : null}
        {sections.map((block, index) => (
          <BlockView key={index} block={block} />
        ))}
      </article>
    </div>
  );
}

/** The paragraph of dates under the title ("Effective date: …"). */
function isDateLine(block: Block): boolean {
  return block.kind === 'paragraph' && block.content[0]?.kind === 'strong' && /^Effective date:/.test(plainText(block.content[0].children));
}

function subscribeWide(listener: () => void): () => void {
  if (typeof window.matchMedia !== 'function') return () => undefined;
  const query = window.matchMedia(WIDE);
  query.addEventListener?.('change', listener);
  return () => query.removeEventListener?.('change', listener);
}

const WIDE = '(min-width: 1024px)';

/** A computer's screen: "On this page" starts open there, and closed on a phone, where it'd fill the first screen. */
function useWide(): boolean {
  return useSyncExternalStore(
    subscribeWide,
    () => typeof window.matchMedia === 'function' && window.matchMedia(WIDE).matches,
    () => false,
  );
}

/** "On this page": the document's sections, each a link to its heading. */
function Contents({ headings }: { headings: Extract<Block, { kind: 'heading' }>[] }) {
  const wide = useWide();
  const [open, setOpen] = useState(wide);
  useEffect(() => setOpen(wide), [wide]);
  return (
    <nav className="legal-toc" aria-label="On this page" data-testid="legal-contents">
      <details open={open} onToggle={(event) => setOpen(event.currentTarget.open)}>
        <summary className="legal-toc__summary">
          <span>On this page</span>
          <Icon name="chevronRight" className="legal-toc__chevron" />
        </summary>
        <ol className="legal-toc__list">
          {headings.map((heading) => (
            <li key={heading.id}>
              <a className="legal-toc__link" href={`#${heading.id}`}>
                {heading.text}
              </a>
            </li>
          ))}
        </ol>
      </details>
    </nav>
  );
}

/**
 * Opened at a section (/privacy#saved-cards, or a section of "On this page"): that section's
 * heading comes into view below the nav, and screen readers and the keyboard go on from it.
 */
function useScrollToSection(blocks: Block[]): void {
  const { hash } = useLocation();
  useEffect(() => goToSection(hash), [hash, blocks]);
  // A link within the page changes only the address's #section: the browser scrolls, this moves the focus.
  useEffect(() => {
    const onHashChange = () => goToSection(window.location.hash);
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);
}

function goToSection(hash: string): void {
  if (!hash) return;
  let id = hash.slice(1);
  try {
    id = decodeURIComponent(id);
  } catch {
    // Not encoded: as it is.
  }
  const target = document.getElementById(id);
  if (!target || !target.closest('.legal')) return;
  target.scrollIntoView?.({ block: 'start' });
  target.focus({ preventScroll: true });
}

function BlockView({ block, dates = false }: { block: Block; dates?: boolean }) {
  switch (block.kind) {
    case 'heading': {
      const content = <Inlines nodes={block.content} />;
      if (block.level === 1) {
        return (
          <h1 id={block.id} className="legal__title">
            {content}
          </h1>
        );
      }
      // Focusable from a link to the section (not with Tab), so the reading goes on from there.
      return block.level === 2 ? (
        <h2 id={block.id} className="legal__h2" tabIndex={-1}>
          {content}
        </h2>
      ) : (
        <h3 id={block.id} className="legal__h3" tabIndex={-1}>
          {content}
        </h3>
      );
    }
    case 'paragraph':
      return (
        <p className={dates ? 'legal__dates' : undefined} data-testid={dates ? 'legal-dates' : undefined}>
          <Inlines nodes={block.content} />
        </p>
      );
    case 'list':
      return (
        <ul className="legal__list">
          {block.items.map((item, index) => (
            <li key={index}>
              <Inlines nodes={item.content} />
              {item.blocks.map((child, childIndex) => (
                <BlockView key={childIndex} block={child} />
              ))}
            </li>
          ))}
        </ul>
      );
    case 'quote':
      return (
        <blockquote className="legal__quote">
          {block.blocks.map((child, index) => (
            <BlockView key={index} block={child} />
          ))}
        </blockquote>
      );
    case 'table':
      return (
        <div className="legal__table-wrap">
          <table className="legal__table">
            <thead>
              <tr>
                {block.head.map((cell, index) => (
                  <th key={index} scope="col">
                    <Inlines nodes={cell} />
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {block.rows.map((row, rowIndex) => (
                <tr key={rowIndex}>
                  {row.map((cell, index) =>
                    // The first column names what the row is about.
                    index === 0 ? (
                      <th key={index} scope="row">
                        <Inlines nodes={cell} />
                      </th>
                    ) : (
                      <td key={index}>
                        <Inlines nodes={cell} />
                      </td>
                    ),
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
  }
}

/** Inline words, each knowing the words before it in its paragraph, list item or cell (`before`). */
function Inlines({ nodes, inLink = false, before = '' }: { nodes: Inline[]; inLink?: boolean; before?: string }) {
  let preceding = before;
  return (
    <>
      {nodes.map((node, index) => {
        const view = <InlineView key={index} node={node} inLink={inLink} before={preceding} />;
        preceding += plainText([node]);
        return view;
      })}
    </>
  );
}

function InlineView({ node, inLink, before }: { node: Inline; inLink: boolean; before: string }) {
  switch (node.kind) {
    case 'text':
      return <>{inLink ? node.text : linkified(node.text, before)}</>;
    case 'strong':
      return (
        <strong>
          <Inlines nodes={node.children} inLink={inLink} before={before} />
        </strong>
      );
    case 'code':
      return <code className="legal__code">{node.text}</code>;
    case 'break':
      return <br />;
    case 'placeholder':
      return <mark className="legal__placeholder">{placeholderNote(node.raw)}</mark>;
    case 'link': {
      const children = <Inlines nodes={node.children} inLink />;
      const route = siteLinkFor(node.href);
      return route ? <Link to={route}>{children}</Link> : <a href={node.href}>{children}</a>;
    }
  }
}

/** "(442) 341-3053" and an email address: the number calls (or texts), the address writes. */
const CALLABLE = /\((\d{3})\) (\d{3})-(\d{4})|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+/g;

/** A number offered for texts ("Text us at (442) 341-3053", "Text: (442) 341-3053") opens a new text message, not a call. */
const TEXT_US = /\btext(?: us(?: at)?|:)\s*$/i;

/** Where a number in the documents goes: a call, or a text where the words just before it offer texts. */
export function numberHref(digits: string, before: string): string {
  return `${TEXT_US.test(before) ? 'sms' : 'tel'}:+1${digits}`;
}

function linkified(text: string, before = ''): ReactNode {
  const parts: ReactNode[] = [];
  let last = 0;
  for (const match of text.matchAll(CALLABLE)) {
    const at = match.index;
    if (at > last) parts.push(text.slice(last, at));
    const [whole, area, exchange, line] = match;
    parts.push(
      <a key={at} className="nowrap" href={area ? numberHref(`${area}${exchange}${line}`, before + text.slice(0, at)) : `mailto:${whole}`}>
        {whole}
      </a>,
    );
    last = at + whole.length;
  }
  if (last === 0) return text;
  if (last < text.length) parts.push(text.slice(last));
  return parts.map((part, index) => <Fragment key={index}>{part}</Fragment>);
}
