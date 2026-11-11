import { describe, expect, it } from 'vitest';
import type { LegalDocumentId } from './documents';
import { parseInline, parseMarkdown, plainText, slugify, type Block, type Inline } from './markdown';
import { LEGAL_TEXTS } from './texts';

// The Markdown the legal documents use, read into blocks the page draws: and the four documents
// themselves, read without a stray "**", "|", "#" or "[TO FILL IN" left in their words.

/** A document as docs/legal has it ("privacy.md"), as the site builds it in. */
const read = (file: string) => LEGAL_TEXTS[file.replace(/\.md$/, '') as LegalDocumentId];

describe('blocks', () => {
  it('headings, with ids from their words as GitHub makes them, repeats numbered', () => {
    const blocks = parseMarkdown('# Privacy Policy\n\n## 1. Agreeing to these terms\n\n### On our website\n\n## What we know isn\'t perfect yet\n\n### On our website');
    expect(blocks.map((b) => (b.kind === 'heading' ? [b.level, b.id] : b.kind))).toEqual([
      [1, 'privacy-policy'],
      [2, '1-agreeing-to-these-terms'],
      [3, 'on-our-website'],
      [2, 'what-we-know-isnt-perfect-yet'],
      [3, 'on-our-website-1'],
    ]);
    expect(slugify('Cancelling or changing by phone, and when we cancel')).toBe('cancelling-or-changing-by-phone-and-when-we-cancel');
    expect(slugify('Cancellation & No-Show Policy')).toBe('cancellation--no-show-policy');
  });

  it('paragraphs, their lines joined, and a backslash at the end of a line breaking it', () => {
    const [first, second] = parseMarkdown('**Effective date:** May 1\\\n**Last updated:** May 2\n\nOne line\nand the next.');
    expect(first).toEqual({
      kind: 'paragraph',
      content: [
        { kind: 'strong', children: [{ kind: 'text', text: 'Effective date:' }] },
        { kind: 'text', text: ' May 1' },
        { kind: 'break' },
        { kind: 'strong', children: [{ kind: 'text', text: 'Last updated:' }] },
        { kind: 'text', text: ' May 2' },
      ],
    });
    expect(second).toEqual({ kind: 'paragraph', content: [{ kind: 'text', text: 'One line and the next.' }] });
  });

  it('bulleted lists, nested by indenting', () => {
    const [list] = parseMarkdown('- **First**, with more:\n  - when you add a card;\n  - when photos load.\n- Second\n  carried on.');
    expect(list).toMatchObject({
      kind: 'list',
      items: [
        {
          content: [{ kind: 'strong' }, { kind: 'text', text: ', with more:' }],
          blocks: [{ kind: 'list', items: [{ content: [{ kind: 'text', text: 'when you add a card;' }] }, { content: [{ kind: 'text', text: 'when photos load.' }] }] }],
        },
        { content: [{ kind: 'text', text: 'Second carried on.' }], blocks: [] },
      ],
    });
  });

  it('a block quote indented under a list item, after a blank line, belongs to it', () => {
    const blocks = parseMarkdown('- a notice;\n- the terms. For example:\n\n  > No payment now.\n\nAfter the list.');
    expect(blocks).toMatchObject([
      {
        kind: 'list',
        items: [
          { content: [{ kind: 'text', text: 'a notice;' }], blocks: [] },
          { content: [{ kind: 'text', text: 'the terms. For example:' }], blocks: [{ kind: 'quote', blocks: [{ kind: 'paragraph', content: [{ kind: 'text', text: 'No payment now.' }] }] }] },
        ],
      },
      { kind: 'paragraph', content: [{ kind: 'text', text: 'After the list.' }] },
    ]);
  });

  it('tables, every row as wide as the header', () => {
    const [table] = parseMarkdown('| What | Why |\n|---|---|\n| Your name | So we know who\'s coming. |\n| **Bold** | `code` \\| pipe |\n| Short |');
    expect(table?.kind).toBe('table');
    const { head, rows } = table as Extract<Block, { kind: 'table' }>;
    expect(head.map(plainText)).toEqual(['What', 'Why']);
    expect(rows.map((row) => row.map(plainText))).toEqual([
      ['Your name', "So we know who's coming."],
      ['Bold', 'code | pipe'],
      ['Short', ''],
    ]);
  });
});

describe('inline', () => {
  it('bold, links, code and placeholders, nested', () => {
    expect(parseInline('**Email us at [TO FILL IN: the address].** See [our policy](privacy.md#saved-cards) and `izzy_appointments`.')).toEqual<Inline[]>([
      { kind: 'strong', children: [{ kind: 'text', text: 'Email us at ' }, { kind: 'placeholder', raw: '[TO FILL IN: the address]' }, { kind: 'text', text: '.' }] },
      { kind: 'text', text: ' See ' },
      { kind: 'link', href: 'privacy.md#saved-cards', children: [{ kind: 'text', text: 'our policy' }] },
      { kind: 'text', text: ' and ' },
      { kind: 'code', text: 'izzy_appointments' },
      { kind: 'text', text: '.' },
    ]);
  });

  it('a placeholder with quotes and semicolons in it, and brackets that aren’t links', () => {
    expect(parseInline('text us [TO FILL IN: remove "text us"; unless] or [not a link] (or this)')).toEqual<Inline[]>([
      { kind: 'text', text: 'text us ' },
      { kind: 'placeholder', raw: '[TO FILL IN: remove "text us"; unless]' },
      { kind: 'text', text: ' or [not a link] (or this)' },
    ]);
  });

  it('escaped punctuation as it is', () => {
    expect(parseInline('\\*not bold\\* and a \\[bracket\\]')).toEqual<Inline[]>([{ kind: 'text', text: '*not bold* and a [bracket]' }]);
  });
});

/** Every bit of text in the blocks, as a reader would see it. */
function allText(blocks: Block[]): string[] {
  return blocks.flatMap((block): string[] => {
    switch (block.kind) {
      case 'heading':
      case 'paragraph':
        return [plainText(block.content)];
      case 'list':
        return block.items.flatMap((item) => [plainText(item.content), ...allText(item.blocks)]);
      case 'quote':
        return allText(block.blocks);
      case 'table':
        return [...block.head, ...block.rows.flat()].map(plainText);
    }
  });
}

function placeholders(nodes: Inline[]): string[] {
  return nodes.flatMap((node) => (node.kind === 'placeholder' ? [node.raw] : node.kind === 'strong' || node.kind === 'link' ? placeholders(node.children) : []));
}

describe('the four documents', () => {
  for (const [file, title] of [
    ['privacy.md', 'Privacy Policy'],
    ['terms.md', 'Terms of Service'],
    ['cancellation-policy.md', 'Cancellation & No-Show Policy'],
    ['accessibility.md', 'Accessibility Statement'],
  ] as const) {
    it(`${file}: one title, its sections, and no Markdown left in the words`, () => {
      const blocks = parseMarkdown(read(file));
      expect(blocks[0]).toMatchObject({ kind: 'heading', level: 1, text: title });
      expect(blocks.filter((b) => b.kind === 'heading' && b.level === 1)).toHaveLength(1);
      expect(blocks.filter((b) => b.kind === 'heading' && b.level === 2).length).toBeGreaterThan(4);
      const ids = blocks.flatMap((b) => (b.kind === 'heading' ? [b.id] : []));
      expect(new Set(ids).size).toBe(ids.length);
      for (const text of allText(blocks).map((t) => t.replace(/\[TO FILL IN[^\]]*\]/g, ''))) {
        expect(text, text).not.toMatch(/\*\*|^#|\|---|\]\(|`/);
        expect(text, text).not.toContain('TO FILL IN');
      }
    });
  }

  it('privacy.md: its three tables, the nested list about other companies, and its cookie in code', () => {
    const blocks = parseMarkdown(read('privacy.md'));
    const tables = blocks.filter((b): b is Extract<Block, { kind: 'table' }> => b.kind === 'table');
    expect(tables.map((t) => t.head.map(plainText))).toEqual([
      ['What', 'Why'],
      ['What', "When it's removed"],
      ['Information', 'How long we keep it'],
    ]);
    expect(tables[1]!.rows).toHaveLength(7);
    const nested = blocks.find((b) => b.kind === 'list' && b.items.some((item) => item.blocks.some((child) => child.kind === 'list')));
    expect(nested).toBeDefined();
    expect(JSON.stringify(blocks)).toContain('{"kind":"code","text":"izzy_appointments"}');
  });

  it('cancellation-policy.md: the example of the agreed terms as a quote, under its list item', () => {
    const blocks = parseMarkdown(read('cancellation-policy.md'));
    const list = blocks.find((b): b is Extract<Block, { kind: 'list' }> => b.kind === 'list' && b.items.some((item) => item.blocks.some((child) => child.kind === 'quote')));
    expect(list).toBeDefined();
    expect(allText(list!.items[1]!.blocks)).toEqual([expect.stringMatching(/^No payment now\. If you cancel less than 1 hour/)]);
  });

  it('accessibility.md: its placeholders are found inside bold words too', () => {
    const blocks = parseMarkdown(read('accessibility.md'));
    const found = blocks.flatMap((block) =>
      block.kind === 'paragraph' ? placeholders(block.content) : block.kind === 'list' ? block.items.flatMap((item) => placeholders(item.content)) : [],
    );
    expect(found).toContain("[TO FILL IN: the shop's email address]");
    expect(found.length).toBeGreaterThanOrEqual(7);
  });
});
