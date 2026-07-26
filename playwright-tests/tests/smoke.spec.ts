// playwright-tests/tests/smoke.spec.ts
//
// One test, run 4x (once per Playwright "project" in playwright.config.ts
// — customer/hero/admin/seller each hit their own live URL). This is a
// SAFE, passive load-health check only:
//   1. Open the app's root URL.
//   2. Wait for Flutter's own splash-screen (web/index.html) to report
//      the app actually booted — the splash div starts with class
//      "visible" and Flutter's bootstrap JS swaps it to "hidden" the
//      moment the engine renders its first frame. Waiting for that swap
//      proves Dart/Flutter genuinely came up, not just that the static
//      HTML shell returned a 200.
//   3. Fail the test if the page threw any uncaught JS error (pageerror)
//      while getting there.
//
// Deliberately does NOT click anything — no login, no navigation past
// the home screen, and critically NOT the temporary red "Throw Test
// Error" buttons added for Sentry verification (dashboard_screen.dart /
// hero_home_screen.dart / super_admin_home_screen.dart /
// seller_dashboard_screen.dart). Nizam/CTO said to leave those buttons
// in place and handle them separately — an automated test tapping one
// on every run would throw a StateError on purpose every single time,
// which is the opposite of "checks the app loads without critical
// errors." Once those buttons are removed, this test doesn't need to
// change at all.
import { test, expect } from '@playwright/test';

test('app boots to its first Flutter frame with no uncaught JS errors', async ({
  page,
}) => {
  const pageErrors: Error[] = [];
  page.on('pageerror', (err) => pageErrors.push(err));

  await page.goto('/');

  // Flutter web's splash-screen element (see web/index.html) is the one
  // stable, framework-level signal that isn't Flutter-widget-tree
  // specific — every one of the 4 apps shares this same index.html, so
  // the same selector works for all of them regardless of what each
  // app's actual home screen looks like.
  const splash = page.locator('#splash-screen');

  // On a slow cold CDN hit the splash element may not even exist yet
  // when we query it — give it a moment to appear before asserting on
  // its class.
  await expect(splash).toBeAttached({ timeout: 15_000 });
  await expect(splash).not.toHaveClass(/visible/, { timeout: 15_000 });

  expect(
    pageErrors,
    `Uncaught JS error(s) during load: ${pageErrors.map((e) => e.message).join('; ')}`,
  ).toHaveLength(0);
});
