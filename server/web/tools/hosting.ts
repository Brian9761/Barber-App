// What a vercel.json's redirects and rewrites do with a path, for the end-to-end servers
// (e2e/serve.ts and e2e/serve-demo.ts), which host the build the way Vercel does: a redirect first
// (Vercel applies them before anything else), then a file of the build ("the filesystem takes
// precedence over rewrites", Vercel's documentation says), then the first rewrite whose source
// matches, in order. Sources are written as Vercel reads them: a path, with
// ":name*" for the rest of it ("/business/:path*"), or a regular expression in parentheses
// ("/((?!api/|assets/).*)").

export interface Rewrite {
  source: string;
  destination: string;
}

/** A vercel.json redirect: Vercel applies these before it looks for a file. */
export interface Redirect extends Rewrite {
  /** 308 when true, 307 otherwise (Vercel's defaults). */
  permanent?: boolean;
}

/** A vercel.json `source` as a regular expression for the whole path. */
export function sourcePattern(source: string): RegExp {
  let pattern = '';
  let depth = 0;
  for (let i = 0; i < source.length; i += 1) {
    const char = source[i]!;
    if (depth === 0) {
      // "/:path*": the rest of the path, if any; "/:id": one segment.
      const param = /^\/:\w+(\*)?/.exec(source.slice(i));
      if (param) {
        pattern += param[1] ? '(?:/.*)?' : '/[^/]+';
        i += param[0].length - 1;
        continue;
      }
    }
    if (char === '(') depth += 1;
    pattern += depth > 0 ? char : char.replace(/[.*+?^${}|[\]\\]/g, '\\$&');
    if (char === ')') depth -= 1;
  }
  return new RegExp(`^${pattern}$`);
}

/** The rewrites in `hosting` (a vercel.json's text), ready to match. */
export function rewritesOf(hosting: string): { pattern: RegExp; destination: string }[] {
  const rewrites = (JSON.parse(hosting) as { rewrites?: Rewrite[] }).rewrites ?? [];
  return rewrites.map((rule) => ({ pattern: sourcePattern(rule.source), destination: rule.destination }));
}

/** Where the first matching rewrite sends `pathname`, or null when none does. */
export function rewriteFor(rewrites: readonly { pattern: RegExp; destination: string }[], pathname: string): string | null {
  return rewrites.find((rule) => rule.pattern.test(pathname))?.destination ?? null;
}

/** The redirects in `hosting` (a vercel.json's text), ready to match. */
export function redirectsOf(hosting: string): { pattern: RegExp; destination: string; status: 307 | 308 }[] {
  const redirects = (JSON.parse(hosting) as { redirects?: Redirect[] }).redirects ?? [];
  return redirects.map((rule) => ({ pattern: sourcePattern(rule.source), destination: rule.destination, status: rule.permanent === false ? 307 : 308 }));
}

/** Where the first matching redirect sends `pathname`, with its status, or null when none does. */
export function redirectFor(
  redirects: readonly { pattern: RegExp; destination: string; status: 307 | 308 }[],
  pathname: string,
): { destination: string; status: 307 | 308 } | null {
  const rule = redirects.find((candidate) => candidate.pattern.test(pathname));
  return rule ? { destination: rule.destination, status: rule.status } : null;
}
