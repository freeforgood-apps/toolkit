// Run an app's self-test in headless Chrome at three sizes and print each report's first lines.
// Usage: node selftest-runner.mjs <selftest url>   (set CHROME if Chrome isn't at /usr/bin/google-chrome)
// Works with any self-test that has a "Run self-test" button (#st-go) and a report box (#st-sum) saying PASSED or FAILED.
import puppeteer from 'puppeteer-core';

const url = process.argv[2];
if (!url) { console.log('Usage: node selftest-runner.mjs <selftest url>'); process.exit(1); }
const CHROME = process.env.CHROME || '/usr/bin/google-chrome';
const RUNS = [
  { name: 'phone (390px), light', view: { width: 390, height: 844, isMobile: true, hasTouch: true }, theme: 'light' },
  { name: 'small phone (320px), dark', view: { width: 320, height: 568, isMobile: true, hasTouch: true }, theme: 'dark' },
  { name: 'desktop (1440px), light', view: { width: 1440, height: 900 }, theme: 'light' },
];

const browser = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--no-sandbox'] });
let allPassed = true;
try {
  for (const run of RUNS) {
    const ctx = await browser.createBrowserContext(); // fresh storage for every run
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.setViewport(run.view);
    await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: run.theme }]);
    await page.goto(url, { waitUntil: 'networkidle0' });
    await page.click('#st-go');
    // The report box appears when the run ends; wait for its verdict
    await page.waitForFunction(() => /PASSED|FAILED/.test((document.getElementById('st-sum') || {}).value || ''), { timeout: 300000 });
    const report = await page.$eval('#st-sum', (el) => el.value);
    const passed = /PASSED/.test(report.split('\n')[0]);
    allPassed = allPassed && passed && !errors.length;
    console.log(`${run.name}: ${passed ? 'PASSED' : 'FAILED'}`);
    report.split('\n').slice(0, 4).forEach((line) => console.log('   ' + line));
    if (!passed) report.split('\n').filter((l) => /^\s*[-•✗]/.test(l)).slice(0, 10).forEach((l) => console.log('   issue: ' + l.trim()));
    if (errors.length) console.log('   page errors: ' + errors.slice(0, 3).join(' | '));
    await ctx.close();
  }
} finally {
  await browser.close();
}
process.exit(allPassed ? 0 : 1);
