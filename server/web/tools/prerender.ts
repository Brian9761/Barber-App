// The four legal pages as plain HTML at their own addresses (privacy/index.html…), made at the end
// of every build from the built page (index.html) and the pages' own article
// (src/legal/prerender.tsx, loaded with Vite's runner so its TSX and `?raw` imports work as they
// do in the site), so each policy can be read without JavaScript, and by curl, archivers and
// search engines. Each has its own <title> and description, and the legal pages' own styles. When
// the script runs, the site takes the page over as on every other one (createRoot replaces what's
// in #root).
//
// The hosting serves them before its catch-all rewrite to index.html (vercel.json: Vercel looks
// for a file before it applies rewrites, and each page also has a rewrite of its own; the
// end-to-end servers do the same). The service worker doesn't keep them: online it asks the
// network for a legal page first, and offline the app's own page opens it (src/sw/routes.ts).

import type { Plugin, Rollup } from 'vite';
import { LEGAL_FILES } from './legal.js';

/** Where each page is in the build, as the hosting serves it: "privacy/index.html". */
export const LEGAL_PAGE_FILES: readonly string[] = LEGAL_FILES.map((file) => `${file.replace(/\.md$/, '')}/index.html`);

/** One page as src/legal/prerender.tsx draws it. */
export interface LegalPageContent {
  /** "/privacy". */
  path: string;
  /** "privacy/index.html". */
  file: string;
  /** "Privacy Policy · Izzy Clipz Barbershop". */
  title: string;
  description: string;
  /** The page's markup, for #root. */
  body: string;
}

/** What the page links besides the built page's own files. */
export interface LegalPageExtras {
  /** The legal pages' own styles ("/assets/LegalPage-….css"): they come with their script, which plain HTML doesn't run. */
  stylesheets: readonly string[];
  /** Their script, fetched early so the site takes over sooner. */
  preloads: readonly string[];
  /** The site's public address, for the canonical link; empty when it isn't known. */
  origin: string;
}

function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/**
 * The built page (`template`, the site's index.html as the build wrote it) as `page`: its title,
 * description and Open Graph title and description, its markup in #root, and its styles and
 * script linked. Stops, saying what's missing, if the built page doesn't have a part it fills in.
 */
export function legalPageHtml(template: string, page: LegalPageContent, extras: LegalPageExtras): string {
  let html = template;
  const fill = (pattern: RegExp, replacement: string, what: string) => {
    if (!pattern.test(html)) throw new Error(`The built index.html has no ${what}, so ${page.file} can't be made from it.`);
    // A function, so "$" in the documents ("$35") is never read as a pattern.
    html = html.replace(pattern, () => replacement);
  };
  fill(/<title>[^<]*<\/title>/, `<title>${escapeHtml(page.title)}</title>`, '<title>');
  fill(/<meta name="description" content="[^"]*"\s*\/?>/, `<meta name="description" content="${escapeHtml(page.description)}" />`, 'description');
  fill(/<meta property="og:title" content="[^"]*"\s*\/?>/, `<meta property="og:title" content="${escapeHtml(page.title)}" />`, 'og:title');
  fill(/<meta property="og:description" content="[^"]*"\s*\/?>/, `<meta property="og:description" content="${escapeHtml(page.description)}" />`, 'og:description');
  const links = [
    ...extras.stylesheets.map((href) => `<link rel="stylesheet" crossorigin href="${escapeHtml(href)}">`),
    ...extras.preloads.map((href) => `<link rel="modulepreload" crossorigin href="${escapeHtml(href)}">`),
    ...(extras.origin ? [`<link rel="canonical" href="${escapeHtml(extras.origin + page.path)}">`] : []),
  ];
  fill(/\s*<\/head>/, `${links.map((link) => `\n    ${link}`).join('')}\n  </head>`, '</head>');
  fill(/<div id="root"><\/div>/, `<div id="root">${page.body}</div>`, 'empty <div id="root">');
  return html;
}

/** What src/legal/prerender.tsx gives the build. */
interface PrerenderModule {
  renderLegalPages(options: { draft: boolean; demo: boolean }): LegalPageContent[];
}

/**
 * Drawing the pages in Node, their stylesheets mean nothing (the HTML links them instead), and
 * Vite's runner doesn't process CSS: each CSS import is an empty module there.
 */
function withoutStyles(): Plugin {
  const empty = '\0izzy-prerender-no-css';
  return {
    name: 'izzy-prerender-without-styles',
    enforce: 'pre',
    resolveId: (source) => (/\.css(?:\?|$)/.test(source) ? empty : null),
    load: (id) => (id === empty ? 'export {};' : null),
  };
}

/**
 * The build's plugin: once the bundle (and its index.html) is made, the four pages from
 * `entry` (src/legal/prerender.tsx), as drafts unless `draft` is false (a strict build, which
 * the legal documents' own plugin already stopped if anything was left to fill in), written
 * next to it. `legalPage` is the legal pages' module (src/legal/LegalPage.tsx), whose styles
 * and script they link.
 */
export function legalPages(options: { root: string; entry: string; legalPage: string; draft: boolean; demo: boolean; origin: string }): Plugin {
  return {
    name: 'izzy-legal-pages',
    apply: 'build',
    // After Vite has written index.html into the bundle.
    enforce: 'post',
    generateBundle: {
      order: 'post',
      async handler(_output, bundle) {
        const template = bundle['index.html'];
        if (!template || template.type !== 'asset' || typeof template.source !== 'string') {
          return this.error('The legal pages are made from the built index.html, which isn’t in the bundle.');
        }
        const page = template.source;
        const chunk = Object.values(bundle).find(
          (item): item is Rollup.OutputChunk => item.type === 'chunk' && item.facadeModuleId === options.legalPage,
        );
        if (!chunk) return this.error(`The legal pages' script (${options.legalPage}) isn't in the bundle.`);
        const extras: LegalPageExtras = {
          stylesheets: [...(chunk.viteMetadata?.importedCss ?? [])].map((file) => `/${file}`),
          preloads: [`/${chunk.fileName}`],
          origin: options.origin,
        };
        const { runnerImport } = await import('vite');
        const { module } = await runnerImport<PrerenderModule>(options.entry, {
          root: options.root,
          logLevel: 'warn',
          esbuild: { jsx: 'automatic' },
          plugins: [withoutStyles()],
        });
        const pages = module.renderLegalPages({ draft: options.draft, demo: options.demo });
        for (const content of pages) {
          if (!LEGAL_PAGE_FILES.includes(content.file)) return this.error(`Unexpected legal page ${content.file}`);
          this.emitFile({ type: 'asset', fileName: content.file, source: legalPageHtml(page, content, extras) });
        }
      },
    },
  };
}
