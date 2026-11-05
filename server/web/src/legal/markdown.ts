// A small Markdown reader for the four legal documents (docs/legal/*.md), for exactly what they
// use: headings (# to ###), paragraphs, **bold**, [links](…), `code`, bulleted lists (nested by
// indenting), tables, block quotes, a backslash at the end of a line for a line break, and the
// shop's placeholders ("[TO FILL IN: …]"). It makes a tree that the page draws as React
// elements, so nothing from the files is ever put in the page as HTML.

import { PLACEHOLDER_START } from './placeholders';

export type Inline =
  | { kind: 'text'; text: string }
  | { kind: 'strong'; children: Inline[] }
  | { kind: 'code'; text: string }
  | { kind: 'link'; href: string; children: Inline[] }
  | { kind: 'placeholder'; raw: string }
  | { kind: 'break' };

export interface ListItem {
  /** The item's own words. */
  content: Inline[];
  /** What's indented under it: a list, a quote, more paragraphs. */
  blocks: Block[];
}

export type Block =
  | { kind: 'heading'; level: 1 | 2 | 3; content: Inline[]; text: string; id: string }
  | { kind: 'paragraph'; content: Inline[] }
  | { kind: 'list'; items: ListItem[] }
  | { kind: 'table'; head: Inline[][]; rows: Inline[][][] }
  | { kind: 'quote'; blocks: Block[] };

/** The document's blocks, top to bottom. Headings get ids from their words, as GitHub makes them. */
export function parseMarkdown(source: string): Block[] {
  const lines = source.replace(/\r\n?/g, '\n').split('\n');
  return parseBlocks(lines, new Map());
}

// ------------------------------------------------------------------- Blocks

const HEADING = /^(#{1,3})[ \t]+(.+?)[ \t]*#*[ \t]*$/;
const LIST_ITEM = /^([ \t]*)[-*+][ \t]+(.*)$/;
const QUOTE = /^[ \t]{0,3}>[ \t]?(.*)$/;
const TABLE_ROW = /^[ \t]*\|.*\|[ \t]*$/;
const TABLE_DELIMITER = /^[ \t]*\|?[ \t]*:?-{3,}:?[ \t]*(\|[ \t]*:?-{3,}:?[ \t]*)*\|?[ \t]*$/;

const isBlank = (line: string) => line.trim() === '';
const indentOf = (line: string) => (/^[ \t]*/.exec(line)?.[0] ?? '').replace(/\t/g, '    ').length;

/** Whether `lines[i]` starts a block other than a paragraph (so it ends the paragraph before it). */
function startsBlock(lines: string[], i: number): boolean {
  const line = lines[i] ?? '';
  return HEADING.test(line) || LIST_ITEM.test(line) || QUOTE.test(line) || (TABLE_ROW.test(line) && TABLE_DELIMITER.test(lines[i + 1] ?? ''));
}

function parseBlocks(lines: string[], slugs: Map<string, number>): Block[] {
  const blocks: Block[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i]!;
    if (isBlank(line)) {
      i += 1;
      continue;
    }

    const heading = HEADING.exec(line);
    if (heading) {
      const content = parseInline(heading[2]!);
      const text = plainText(content);
      blocks.push({ kind: 'heading', level: heading[1]!.length as 1 | 2 | 3, content, text, id: uniqueSlug(text, slugs) });
      i += 1;
      continue;
    }

    if (TABLE_ROW.test(line) && TABLE_DELIMITER.test(lines[i + 1] ?? '')) {
      const head = tableCells(line);
      const rows: Inline[][][] = [];
      i += 2;
      while (i < lines.length && TABLE_ROW.test(lines[i]!)) {
        const cells = tableCells(lines[i]!);
        // Every row has the header's number of cells, as Markdown's tables do.
        rows.push(head.map((_, column) => cells[column] ?? []));
        i += 1;
      }
      blocks.push({ kind: 'table', head, rows });
      continue;
    }

    if (QUOTE.test(line)) {
      const inner: string[] = [];
      while (i < lines.length && QUOTE.test(lines[i]!)) {
        inner.push(QUOTE.exec(lines[i]!)![1]!);
        i += 1;
      }
      blocks.push({ kind: 'quote', blocks: parseBlocks(inner, slugs) });
      continue;
    }

    if (LIST_ITEM.test(line)) {
      const [list, next] = parseList(lines, i, slugs);
      blocks.push(list);
      i = next;
      continue;
    }

    // A paragraph: up to a blank line or the start of another block.
    const paragraph = [line.trim()];
    i += 1;
    while (i < lines.length && !isBlank(lines[i]!) && !startsBlock(lines, i)) {
      paragraph.push(lines[i]!.trim());
      i += 1;
    }
    blocks.push({ kind: 'paragraph', content: parseInline(paragraph.join('\n')) });
  }
  return blocks;
}

/**
 * A bulleted list starting at `lines[start]`: its items at that indent, each with the lines
 * indented under it (a nested list, a quote after a blank line) and any lines that just carry
 * on its words. Returns the list and the line after it.
 */
function parseList(lines: string[], start: number, slugs: Map<string, number>): [Block, number] {
  const indent = indentOf(lines[start]!);
  const items: ListItem[] = [];
  let i = start;
  while (i < lines.length) {
    const marker = LIST_ITEM.exec(lines[i]!);
    if (!marker || indentOf(lines[i]!) !== indent) break;
    // What's under the item is indented at least as far as its words start ("- " is 2 more).
    const contentIndent = indent + lines[i]!.trimStart().length - marker[2]!.length;
    const own = [marker[2]!];
    i += 1;
    while (i < lines.length) {
      const next = lines[i]!;
      if (isBlank(next)) {
        // After a blank line the item goes on only where the next words are indented into it.
        let j = i;
        while (j < lines.length && isBlank(lines[j]!)) j += 1;
        if (j < lines.length && indentOf(lines[j]!) >= contentIndent) {
          for (; i < j; i += 1) own.push('');
          continue;
        }
        break;
      }
      if (indentOf(next) >= contentIndent) {
        own.push(next.replace(/^[ \t]*/, (spaces) => spaces.replace(/\t/g, '    ').slice(contentIndent)));
        i += 1;
        continue;
      }
      // Another item (of this list or one around it), or another block, ends this item.
      if (LIST_ITEM.test(next) || startsBlock(lines, i)) break;
      own.push(next.trim());
      i += 1;
    }
    // Its own words run up to a blank line or a block (a nested list, a quote); the rest are blocks.
    let end = 1;
    while (end < own.length && !isBlank(own[end]!) && !startsBlock(own, end)) end += 1;
    items.push({ content: parseInline(own.slice(0, end).join('\n')), blocks: parseBlocks(own.slice(end), slugs) });
    // Items with blank lines between them are still one list.
    let j = i;
    while (j < lines.length && isBlank(lines[j]!)) j += 1;
    if (j > i && j < lines.length && LIST_ITEM.test(lines[j]!) && indentOf(lines[j]!) === indent) i = j;
  }
  return [{ kind: 'list', items }, i];
}

/** A table row's cells: between the pipes, trimmed ("\|" is a pipe in a cell). */
function tableCells(line: string): Inline[][] {
  const inner = line.trim().replace(/^\|/, '').replace(/\|$/, '');
  const cells: string[] = [];
  let cell = '';
  for (let i = 0; i < inner.length; i += 1) {
    const ch = inner[i]!;
    if (ch === '\\' && inner[i + 1] === '|') {
      cell += '|';
      i += 1;
    } else if (ch === '|') {
      cells.push(cell);
      cell = '';
    } else {
      cell += ch;
    }
  }
  cells.push(cell);
  return cells.map((text) => parseInline(text.trim()));
}

// ------------------------------------------------------------------ Inlines

/** Punctuation a backslash can escape, as in CommonMark. */
const ESCAPABLE = /[!-/:-@[-`{-~]/;

/** A paragraph's (or cell's, or heading's) words: lines joined with "\n", which reads as a space. */
export function parseInline(text: string): Inline[] {
  const out: Inline[] = [];
  let buffer = '';
  const flush = () => {
    if (buffer) out.push({ kind: 'text', text: buffer });
    buffer = '';
  };
  let i = 0;
  while (i < text.length) {
    const ch = text[i]!;
    if (ch === '\\') {
      const next = text[i + 1];
      // A backslash at the end of a line breaks the line there (at the very end, it does nothing).
      if (next === '\n' || next === undefined) {
        flush();
        if (next === '\n') out.push({ kind: 'break' });
        i += 2;
        continue;
      }
      if (ESCAPABLE.test(next)) {
        buffer += next;
        i += 2;
        continue;
      }
    }
    if (ch === '\n') {
      buffer += ' ';
      i += 1;
      continue;
    }
    if (ch === '`') {
      const end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        out.push({ kind: 'code', text: text.slice(i + 1, end) });
        i = end + 1;
        continue;
      }
    }
    if (text.startsWith('**', i)) {
      const end = text.indexOf('**', i + 2);
      if (end > i + 2) {
        flush();
        out.push({ kind: 'strong', children: parseInline(text.slice(i + 2, end)) });
        i = end + 2;
        continue;
      }
    }
    if (text.startsWith(PLACEHOLDER_START, i)) {
      const end = text.indexOf(']', i);
      if (end !== -1) {
        flush();
        out.push({ kind: 'placeholder', raw: text.slice(i, end + 1).replace(/\s*\n\s*/g, ' ') });
        i = end + 1;
        continue;
      }
    }
    if (ch === '[') {
      const close = closingBracket(text, i);
      if (close !== -1 && text[close + 1] === '(') {
        const end = text.indexOf(')', close + 2);
        if (end !== -1) {
          flush();
          out.push({ kind: 'link', href: text.slice(close + 2, end).trim(), children: parseInline(text.slice(i + 1, close)) });
          i = end + 1;
          continue;
        }
      }
    }
    buffer += ch;
    i += 1;
  }
  flush();
  return out;
}

/** The "]" that closes the "[" at `open`, brackets inside counted; -1 if none. */
function closingBracket(text: string, open: number): number {
  let depth = 0;
  for (let i = open; i < text.length; i += 1) {
    if (text[i] === '\\') {
      i += 1;
    } else if (text[i] === '[') {
      depth += 1;
    } else if (text[i] === ']') {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/** The words alone, without their formatting. */
export function plainText(content: Inline[]): string {
  return content
    .map((node) => {
      switch (node.kind) {
        case 'text':
        case 'code':
          return node.text;
        case 'strong':
        case 'link':
          return plainText(node.children);
        case 'placeholder':
          return node.raw;
        case 'break':
          return ' ';
      }
    })
    .join('');
}

/** A heading's id, as GitHub makes them: lowercase, punctuation dropped, spaces as hyphens. */
export function slugify(text: string): string {
  return text
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, '')
    .replace(/ /g, '-');
}

/** The heading's id, with "-1", "-2"… after a repeat, as GitHub does. */
function uniqueSlug(text: string, slugs: Map<string, number>): string {
  const slug = slugify(text) || 'section';
  const seen = slugs.get(slug);
  slugs.set(slug, (seen ?? 0) + 1);
  return seen === undefined ? slug : `${slug}-${seen}`;
}
