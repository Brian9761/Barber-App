// The four legal pages as plain HTML, made when the site is built (tools/prerender.ts), so each
// document can be read without JavaScript, and by anything that reads a page as the server sends
// it. It's the pages' own article (LegalArticle, from the same docs/legal files, a draft or
// published by the same rule), under the site's nav drawn with no script and the site's own
// footer, with the shop's hours and who runs the shop from the catalog this build serves. Once
// the site's script runs, it draws the page in its place, as on every other page, with that same
// catalog (the page carries it), so neither the nav nor the footer moves.

import { renderToStaticMarkup } from 'react-dom/server';
import { Link } from 'react-router-dom';
import { StaticRouter } from 'react-router-dom/server';
import catalogData from '../../../data/catalog.json';
import type { Catalog } from '../api/types';
import { Icon } from '../components/Icon';
import { Footer, NAV_LINKS, NavBookLink, SITE_DIRECTORY_ID } from '../components/Layout';
import { Logo } from '../components/Logo';
import { fullTitle } from '../components/usePageMeta';
import { CatalogProvider } from '../data/catalog';
import { LEGAL_DOCUMENTS, type LegalDocument } from './documents';
import { LegalArticle } from './LegalPage';
import { LEGAL_TEXTS } from './texts';

export interface PrerenderedLegalPage {
  /** Where it's served: "/privacy". */
  path: LegalDocument['path'];
  /** Its file in the build: "privacy/index.html". */
  file: string;
  /** "Privacy Policy · Izzy Clipz Barbershop", as the page itself sets it. */
  title: string;
  description: string;
  /** What goes in the page's #root. */
  body: string;
  /** The catalog it was drawn with, which the page carries for the site's first draw over it (src/main.tsx). */
  catalog: Catalog;
}

/**
 * The global nav as the site draws it (GlobalNav in components/Layout.tsx), so nothing in it moves
 * when the site takes over: the logo home, on a computer the site's pages, Book with its pill, and
 * on a phone "Menu". The site's menu needs the script, so here "Menu" goes to the footer's site
 * directory, which has every page; the site's own Menu button takes its place, the same size.
 */
function StaticNav() {
  return (
    <nav className="globalnav" aria-label="Izzy Clipz">
      <div className="container globalnav__inner">
        <Link to="/" className="globalnav__logo">
          <Logo height={38} label="Izzy Clipz" />
        </Link>
        <ul className="globalnav__links">
          {NAV_LINKS.map((link) => (
            <li key={link.to}>
              <Link to={link.to} className="globalnav__link">
                {link.label}
              </Link>
            </li>
          ))}
        </ul>
        <NavBookLink />
        <a href={`#${SITE_DIRECTORY_ID}`} className="globalnav__menu-standin" aria-label="Menu: the site's pages, at the bottom of this page">
          <Icon name="menu" />
          <span>Menu</span>
        </a>
      </div>
    </nav>
  );
}

/**
 * The shop's catalog as this build has it (the server's data/catalog.json, from the Kit, which the
 * same deployment serves as /api/catalog): the plain pages' footer shows its hours and who runs the
 * shop, as the site's own footer does once its catalog has come.
 */
const BUILD_CATALOG = catalogData as unknown as Catalog;

/** Each legal page as the build writes it: a draft unless the build is strict, the demo's draft saying so. */
export function renderLegalPages({ draft, demo }: { draft: boolean; demo: boolean }): PrerenderedLegalPage[] {
  return LEGAL_DOCUMENTS.map((document) => ({
    path: document.path,
    file: `${document.id}/index.html`,
    title: fullTitle(document.title),
    description: document.description,
    catalog: BUILD_CATALOG,
    body: renderToStaticMarkup(
      <StaticRouter location={document.path}>
        <CatalogProvider initial={BUILD_CATALOG}>
          <a className="skip-link" href="#main">
            Skip to main content
          </a>
          <StaticNav />
          {/* Marked, so a test can tell the site's script drew the page in its place. */}
          <main id="main" tabIndex={-1} data-prerendered="">
            <LegalArticle source={LEGAL_TEXTS[document.id]} draft={draft} demo={demo} />
          </main>
          <Footer />
        </CatalogProvider>
      </StaticRouter>,
    ),
  }));
}
