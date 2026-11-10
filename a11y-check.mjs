// Accessibility check: axe-core plus checks axe doesn't do, at 4 sizes in light and dark mode.
// Usage: node a11y-check.mjs [--click "selector"]... <url> [more urls]   (set CHROME to the browser path if it isn't /usr/bin/google-chrome)
import puppeteer from 'puppeteer-core';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const AXE = readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8');
const CHROME = process.env.CHROME || '/usr/bin/google-chrome';
const VIEWS = [
  { name: 'iPhone 14', width: 390, height: 844, isMobile: true, hasTouch: true },
  { name: 'small phone', width: 320, height: 568, isMobile: true, hasTouch: true },
  { name: 'iPad', width: 820, height: 1180, isMobile: true, hasTouch: true },
  { name: 'desktop', width: 1440, height: 900, isMobile: false, hasTouch: false },
];
const THEMES = ['light', 'dark'];
const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa', 'best-practice'];

// Runs in the page: tap size (44px), input text size (16px), zoom allowed, no sideways scroll.
function extraChecks() {
  const shown = (el) => {
    const r = el.getBoundingClientRect(), s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
  };
  const name = (el) => (el.getAttribute('aria-label') || el.textContent || el.id || el.tagName).trim().replace(/\s+/g, ' ').slice(0, 40);
  const vp = (document.querySelector('meta[name=viewport]') || {}).content || '';
  const out = {
    zoomBlocked: /user-scalable\s*=\s*(no|0)|maximum-scale\s*=\s*1(\.0*)?(\s|,|$)/i.test(vp),
    sidewaysScroll: document.documentElement.scrollWidth > innerWidth + 1,
    smallTargets: [],
    smallInputs: [],
  };
  const targets = 'button, a[href], input, select, textarea, summary, [role=button], [role=tab], [role=switch], [role=checkbox], [role=radio], [tabindex]:not([tabindex="-1"])';
  for (const el of document.querySelectorAll(targets)) {
    if (el.tagName === 'A' && el.closest('p, li')) continue; // links inside a sentence are exempt
    // A checkbox, radio or file input counts by its label, which is what people tap
    // (a file input is often hidden behind its label; one with no label is measured itself)
    const box = ['checkbox', 'radio', 'file'].includes(el.type) && el.labels && el.labels[0] ? el.labels[0] : el;
    if (!shown(box)) continue;
    const r = box.getBoundingClientRect();
    if (r.width < 44 || r.height < 44) out.smallTargets.push(`${name(box)} (${Math.round(r.width)}×${Math.round(r.height)})`);
  }
  for (const el of document.querySelectorAll('input, select, textarea')) {
    if (!shown(el) || ['checkbox', 'radio', 'range', 'color', 'file', 'hidden', 'button', 'submit'].includes(el.type)) continue;
    const size = parseFloat(getComputedStyle(el).fontSize);
    if (size < 16) out.smallInputs.push(`${name(el)} (${size}px)`);
  }
  return out;
}

async function checkUrl(browser, url, clicks = []) {
  const rules = new Map(), extras = [], errors = new Set();
  for (const view of VIEWS) {
    for (const theme of THEMES) {
      const label = `${view.name}, ${theme}`;
      const page = await browser.newPage();
      await page.setBypassCSP(true); // the app's privacy lock would block the checker's script
      await page.setViewport(view);
      // Reduced motion, plus a short wait, so fade-ins can't fake a contrast failure
      await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: theme }, { name: 'prefers-reduced-motion', value: 'reduce' }]);
      page.on('pageerror', (e) => errors.add(e.message));
      // Failed files by name (the console's own 404 lines don't say which file); a missing favicon isn't worth flagging
      page.on('console', (m) => { if (m.type() === 'error' && !m.text().startsWith('Failed to load resource')) errors.add(m.text()); });
      page.on('response', (r) => { const u = new URL(r.url()); if (r.status() >= 400 && !u.pathname.endsWith('/favicon.ico')) errors.add(`${r.status()} ${u.pathname}`); });
      try {
        await page.goto(url, { waitUntil: 'networkidle0', timeout: 30000 });
        await new Promise((done) => setTimeout(done, 600));
        // --click: open a sheet or screen first. Clicks the first match in the page, even if it sits on a hidden screen.
        for (const sel of clicks) {
          const hit = await page.evaluate((s) => { const e = document.querySelector(s); if (e) e.click(); return !!e; }, sel);
          if (!hit) throw new Error(`--click "${sel}" matched nothing`);
          await new Promise((done) => setTimeout(done, 800));
        }
        await page.addScriptTag({ content: AXE });
        const res = await page.evaluate((tags) => axe.run(document, { runOnly: { type: 'tag', values: tags }, resultTypes: ['violations'] }), TAGS);
        for (const v of res.violations) {
          // Each failing element remembers which size and theme it failed in
          const r = rules.get(v.id) || { impact: v.impact, help: v.help, url: v.helpUrl, targets: new Map() };
          for (const n of v.nodes) {
            const t = n.target.join(' ');
            if (!r.targets.has(t)) r.targets.set(t, new Set());
            r.targets.get(t).add(label);
          }
          rules.set(v.id, r);
        }
        extras.push({ label, ...(await page.evaluate(extraChecks)) });
      } catch (e) {
        errors.add(`${label}: ${e.message}`);
      } finally {
        await page.close();
      }
    }
  }
  return { url, rules, extras, errors };
}

// "everywhere", "light" or "dark" (all sizes in that theme), or the exact list
function where(labels) {
  const all = VIEWS.flatMap((v) => THEMES.map((t) => `${v.name}, ${t}`));
  if (all.every((l) => labels.has(l))) return 'everywhere';
  for (const t of THEMES) {
    const inTheme = all.filter((l) => l.endsWith(`, ${t}`));
    if (labels.size === inTheme.length && inTheme.every((l) => labels.has(l))) return `${t} mode`;
  }
  return [...labels].join('; ');
}

function report({ url, rules, extras, errors }) {
  const order = { critical: 0, serious: 1, moderate: 2, minor: 3 };
  const lines = [`\n=== ${url}`, `axe found ${rules.size} rule(s) failing:`];
  [...rules.entries()].sort((a, b) => order[a[1].impact] - order[b[1].impact]).forEach(([id, r]) => {
    lines.push(`- [${r.impact}] ${id}: ${r.help}`);
    [...r.targets].slice(0, 6).forEach(([t, labels]) => lines.push(`    ${t} (${where(labels)})`));
    if (r.targets.size > 6) lines.push(`    +${r.targets.size - 6} more`);
    lines.push(`    how to fix: ${r.url}`);
  });
  for (const x of extras) {
    const bits = [];
    if (x.zoomBlocked) bits.push('zoom is blocked');
    if (x.sidewaysScroll) bits.push('page scrolls sideways');
    if (x.smallTargets.length) bits.push(`${x.smallTargets.length} tap target(s) under 44px: ${x.smallTargets.slice(0, 4).join(', ')}`);
    if (x.smallInputs.length) bits.push(`${x.smallInputs.length} input(s) under 16px: ${x.smallInputs.slice(0, 4).join(', ')}`);
    lines.push(`${x.label}: ${bits.length ? bits.join('; ') : 'extra checks all fine'}`);
  }
  lines.push(errors.size ? `Errors: ${[...errors].join(' | ')}` : 'No page errors.');
  return lines.join('\n');
}

// Arguments: [--click "css selector"]... <url> [more urls]. Each --click is pressed (in order) before the scan, on every url.
const urls = [], clicks = [];
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--click') { if (!args[i + 1]) { console.log('--click needs a selector'); process.exit(1); } clicks.push(args[++i]); } else urls.push(args[i]);
}
if (!urls.length) { console.log('Usage: node a11y-check.mjs [--click "selector"]... <url> [more urls]'); process.exit(1); }
const browser = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--no-sandbox'] });
let problems = 0;
try {
  for (const url of urls) {
    const result = await checkUrl(browser, url, clicks);
    const extraIssues = result.extras.filter((x) => x.zoomBlocked || x.sidewaysScroll || x.smallTargets.length || x.smallInputs.length).length;
    problems += result.rules.size + extraIssues + result.errors.size;
    console.log(report(result));
  }
} finally {
  await browser.close();
}
process.exit(problems ? 1 : 0); // 0 only when every page is clean
