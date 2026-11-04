// Renders every logo image in both apps from izzy-logo-white.svg, the vector tracing of the logo
// the shop sent, straight into the asset catalogs. Playwright's Chromium draws them; on Linux,
// running it again reproduces the committed files byte for byte.
//
//   cd design
//   npm install                        # Playwright 1.63.0, once
//   npx playwright install chromium    # its Chromium, once
//   node render-logo.js
//
// The owner app icon's "Business" mark is set in Inter ExtraBold, so Inter must be installed
// (https://rsms.me/inter); the script stops if it isn't. A new size is a new line in `jobs`.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.join(__dirname, '..');
const LOGO = fs.readFileSync(path.join(__dirname, 'izzy-logo-white.svg'), 'utf8');
const [, , viewBoxWidth, viewBoxHeight] = LOGO.match(/viewBox="([^"]+)"/)[1].split(' ').map(Number);
const ASPECT = viewBoxWidth / viewBoxHeight;
const svg = LOGO.replace('<svg ', '<svg width="100%" height="100%" ');

// The logo alone, `w` pixels wide, on a transparent background.
const logoOnly = (w) => ({ w, h: Math.round(w / ASPECT), bg: 'transparent', html: `<div style="position:absolute;inset:0">${svg}</div>` });

// 1x, 2x and 3x of an image set whose logo is `points` wide.
const imageSet = (catalog, name, points) => Object.fromEntries([1, 2, 3].map((scale) =>
  [`${catalog}/${name}.imageset/${name}${scale > 1 ? `@${scale}x` : ''}.png`, logoOnly(points * scale)]));

// An app icon: the logo on black, `logoH` of the icon's height, centred (or `top` from the top),
// with an optional red pill under it.
const icon = ({ size = 1024, logoH, top, pill }) => {
  const lh = Math.round(size * logoH), lw = Math.round(lh * ASPECT);
  const t = top == null ? Math.round((size - lh) / 2) : Math.round(size * top);
  let html = `<div style="position:absolute;left:${Math.round((size - lw) / 2)}px;top:${t}px;width:${lw}px;height:${lh}px">${svg}</div>`;
  if (pill) {
    const pw = Math.round(size * pill.w), ph = Math.round(size * pill.h);
    html += `<div style="position:absolute;left:${Math.round((size - pw) / 2)}px;top:${Math.round(size * pill.top)}px;width:${pw}px;height:${ph}px;border-radius:${ph / 2}px;background:#D7141C;display:flex;align-items:center;justify-content:center;font:800 ${Math.round(ph * 0.58)}px/1 Inter, sans-serif;color:#fff;letter-spacing:-0.01em">Business</div>`;
  }
  return { w: size, h: size, bg: '#000000', html };
};

const CUSTOMER = 'IzzyClipz/Resources/Assets.xcassets';
const OWNER = 'IzzyClipzBusiness/Resources/Assets.xcassets';
const jobs = {
  ...imageSet(CUSTOMER, 'Logo', 160),
  ...imageSet(CUSTOMER, 'LaunchLogo', 132),
  [`${CUSTOMER}/AppIcon.appiconset/AppIcon.png`]: icon({ logoH: 0.74 }),
  ...imageSet(OWNER, 'Logo', 200),
  [`${OWNER}/AppIcon.appiconset/AppIcon.png`]: icon({ logoH: 0.58, top: 0.085, pill: { w: 0.56, h: 0.135, top: 0.75 } }),
};

// Without Inter the browser would quietly set "Business" in another font.
async function requireInter(browser) {
  const page = await browser.newPage();
  const installed = await page.evaluate(() => {
    const context = document.createElement('canvas').getContext('2d');
    const width = (family) => { context.font = `800 100px ${family}`; return context.measureText('Business').width; };
    return ['monospace', 'serif'].some((fallback) => width(`Inter, ${fallback}`) !== width(fallback));
  });
  await page.close();
  if (!installed) throw new Error('Inter is not installed: the owner app icon\'s "Business" mark is set in Inter ExtraBold (https://rsms.me/inter).');
}

(async () => {
  const browser = await chromium.launch();
  try {
    await requireInter(browser);
    for (const [file, job] of Object.entries(jobs)) {
      const page = await browser.newPage({ viewport: { width: job.w, height: job.h }, deviceScaleFactor: 1 });
      await page.setContent(`<!doctype html><html><head><style>html,body{margin:0;width:${job.w}px;height:${job.h}px;overflow:hidden;background:${job.bg}}</style></head><body>${job.html}</body></html>`);
      await page.evaluate(() => document.fonts.ready);
      await page.screenshot({ path: path.join(ROOT, file), omitBackground: job.bg === 'transparent' });
      await page.close();
      console.log(`${file}  ${job.w}x${job.h}`);
    }
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
