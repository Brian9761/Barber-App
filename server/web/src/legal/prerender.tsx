// The four legal pages as plain HTML, made when the site is built (tools/prerender.ts), so each
// document can be read without JavaScript, and by anything that reads a page as the server sends
// it. It's the pages' own article (LegalArticle, from the same docs/legal files, a draft or
// published by the same rule), under a nav that needs no script and the site's own footer. Once
// the site's script runs, it draws the page in its place, as on every other page.

import { renderToStaticMarkup } from 'react-dom/server';
import { Link } from 'react-router-dom';
import { StaticRouter } from 'react-router-dom/server';
import { Footer, NAV_LINKS } from '../components/Layout';
import { Logo } from '../components/Logo';
import { fullTitle } from '../components/usePageMeta';
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
}

/** The global nav without the phone's menu, which needs the script: the logo home, and on a computer the site's pages. */
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
      </div>
    </nav>
  );
}

/** Each legal page as the build writes it: a draft unless the build is strict, the demo's draft saying so. */
export function renderLegalPages({ draft, demo }: { draft: boolean; demo: boolean }): PrerenderedLegalPage[] {
  return LEGAL_DOCUMENTS.map((document) => ({
    path: document.path,
    file: `${document.id}/index.html`,
    title: fullTitle(document.title),
    description: document.description,
    body: renderToStaticMarkup(
      <StaticRouter location={document.path}>
        <a className="skip-link" href="#main">
          Skip to main content
        </a>
        <StaticNav />
        {/* Marked, so a test can tell the site's script drew the page in its place. */}
        <main id="main" tabIndex={-1} data-prerendered="">
          <LegalArticle source={LEGAL_TEXTS[document.id]} draft={draft} demo={demo} />
        </main>
        <Footer />
      </StaticRouter>,
    ),
  }));
}
