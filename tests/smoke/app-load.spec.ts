import { test, expect } from '@playwright/test';

// ================================================================
// App-load smoke test — one check per deployed Allin1 web app
// ================================================================
// See playwright.config.ts for why this stays shallow (page-load +
// error-catching only, not deep flow testing). Each app gets:
//   1. No unhandled JS exception / pageerror within the load window.
//   2. Something actually rendered — Flutter Web's CanvasKit bundle
//      draws into a <flt-glass-pane>/<canvas>; if that never appears,
//      the app is stuck on a blank screen (index.html loaded but the
//      Dart app never painted — this exact failure mode has happened
//      on the admin map before).
//
// Run manually:   npx playwright test
// Run in CI:      see .github/workflows/playwright-smoke.yml
// ================================================================

const APPS: { name: string; url: string }[] = [
  { name: 'customer', url: 'https://my-allin1.web.app' },
  { name: 'hero', url: 'https://hero-allin1.web.app' },
  { name: 'seller', url: 'https://grow-allin1.web.app' },
  { name: 'admin', url: 'https://hq-allin1.web.app' },
];

for (const app of APPS) {
  test(`${app.name} app loads without JS errors`, async ({ page }) => {
    const errors: string[] = [];

    page.on('pageerror', (err) => {
      errors.push(`pageerror: ${err.message}`);
    });
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        errors.push(`console.error: ${msg.text()}`);
      }
    });

    await page.goto(app.url, { waitUntil: 'domcontentloaded' });

    // Flutter Web boots asynchronously (service worker + engine init) —
    // give it a real window to either paint or throw before judging.
    await page.waitForTimeout(8_000);

    // Flutter Web's root render target. If this never shows up, the
    // page is blank — the same failure class as the admin map issue.
    const rendered = await page
      .locator('flt-glass-pane, flutter-view, canvas')
      .first()
      .isVisible()
      .catch(() => false);

    expect(
      rendered,
      `${app.name} (${app.url}) never rendered its Flutter root — likely a blank/stuck screen`,
    ).toBeTruthy();

    // Fetch-event-handler no-op warnings (seen throughout this project's
    // console logs) are benign — ignore them so they don't create noise
    // in every single failure report.
    const meaningfulErrors = errors.filter(
      (e) => !e.includes('Fetch event handler is recognized as no-op'),
    );

    expect(
      meaningfulErrors,
      `${app.name} (${app.url}) threw JS errors on load:\n${meaningfulErrors.join('\n')}`,
    ).toHaveLength(0);
  });
}
