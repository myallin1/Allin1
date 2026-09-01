// playwright-tests/playwright.config.ts
//
// One Playwright project per Allin1 app, each pointed at its own live
// Firebase Hosting URL (site IDs come straight from ../.firebaserc —
// do NOT hand-guess these, they're the actual deployed targets):
//   customer -> my-allin1.web.app
//   hero     -> hero-allin1.web.app
//   admin    -> hq-allin1.web.app
//   seller   -> grow-allin1.web.app
//
// These are the PRODUCTION URLs deploy_web.ps1 publishes to. There is
// no local dev server wired up here on purpose — Flutter web builds
// (build/web) are large and app-specific per deploy_web.ps1's own
// comments (all 4 apps share one build/web output, swapped in place
// per-app at build time), so "run flutter build web and serve it
// locally" isn't a stable target for CI-style testing the way a normal
// Node/React app would be. Pointing at the real deployed sites means
// this test always reflects what a customer/hero/admin/seller actually
// sees right now.
import { defineConfig, devices } from '@playwright/test';

const APPS = {
  customer: 'https://my-allin1.web.app',
  hero: 'https://hero-allin1.web.app',
  admin: 'https://hq-allin1.web.app',
  seller: 'https://grow-allin1.web.app',
} as const;

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  timeout: 45_000,
  expect: {
    // Flutter web's first frame (splash-screen -> app) can take a few
    // seconds on a cold CDN hit, especially for the CanvasKit renderer.
    timeout: 15_000,
  },
  use: {
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: Object.entries(APPS).map(([name, baseURL]) => ({
    name,
    use: { ...devices['Desktop Chrome'], baseURL },
  })),
});
