const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1800, height: 1200 } });
  const url = 'file://' + path.resolve('public/poster.html');
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForSelector('.poster', { state: 'visible' });
  await page.evaluate(async () => {
    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }
  });
  const poster = page.locator('.poster');
  await poster.screenshot({ path: 'tmp/docs/poster-capture.png' });
  await browser.close();
})();
