// What a vercel.json's rewrites do with a path, for the end-to-end servers (e2e/serve.ts and
// e2e/serve-demo.ts), which host the build the way Vercel does: a file of the build first ("the
// filesystem takes precedence over rewrites", Vercel's documentation says), then the first rewrite
// whose source matches, in order. Sources are written as Vercel reads them: a path, with
// ":name*" for the rest of it ("/business/:path*"), or a regular expression in parentheses
// ("/((?!api/|assets/).*)").

export interface Rewrite {
  source: string;
  destination: string;
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
