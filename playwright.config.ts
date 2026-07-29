import { defineConfig } from '@playwright/test';

// ================================================================
// Playwright config — Allin1 live-site smoke tests
// ================================================================
// Scope, deliberately narrow: these are NOT end-to-end flow tests
// (fill a form, place an order, etc.). Flutter Web renders through
// CanvasKit by default, which draws to a <canvas> — there's no real
// DOM for Playwright's text/role selectors to grab onto, so deep
// interaction testing here would be fragile and misleading.
//
// What this DOES catch, reliably, regardless of renderer: a page that
// throws an unhandled JS exception on load, or fails to render
// anything at all (blank white screen — the #1 symptom Nizam has
// actually hit this project, e.g. the admin map stuck on
// "Allin1 map loading..."). See tests/smoke/app-load.spec.ts.
// ================================================================
export default defineConfig({
  testDir: './tests/smoke',
  timeout: 45_000,
  retries: 1,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
});
