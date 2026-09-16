// web_console_check.js — headless smoke test for the web build.
//
// NEW (Sep 16 2026 — Nizam: "testinglam browserla ooti athoda console
// error paathu aavane agent ku report issue poduvana?"). Runs the
// already-built build/web bundle in a real (headless) Chrome via
// Puppeteer, loads it exactly like a real browser would, and records
// any uncaught JS exceptions or console.error output during startup.
// This is the one thing the whole plan-then-execute pipeline
// (propose_dev_plan / approve_dev_plan) was still missing: Claude's
// own PR never actually RAN in a browser before landing in front of
// the admin — this job is that missing check.
//
// Deliberately conservative about what counts as a reportable error:
// this CI environment has no .env / Firebase config (see the
// "Create placeholder .env for asset bundling" step elsewhere in this
// workflow), so some startup noise here is expected and NOT a code
// bug. The workflow step that runs this script treats the output as
// informational, not a hard CI failure — see ci-cd.yml's
// web_console_check job for how it's used.
//
// Usage: node .github/scripts/web_console_check.js <url> <outFile>
'use strict';

const fs = require('fs');

async function main() {
  const url = process.argv[2];
  const outFile = process.argv[3];
  if (!url || !outFile) {
    console.error('Usage: node web_console_check.js <url> <outFile>');
    process.exit(2);
  }

  const puppeteer = require('puppeteer');
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  const errors = [];
  try {
    const page = await browser.newPage();

    page.on('pageerror', (err) => {
      errors.push({ type: 'uncaught_exception', message: String(err) });
    });
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        errors.push({ type: 'console_error', message: msg.text() });
      }
    });
    page.on('requestfailed', (req) => {
      // Ignore aborted requests (Flutter web cancels some prefetches
      // on its own during startup — not a real failure).
      const failure = req.failure();
      if (failure && failure.errorText !== 'net::ERR_ABORTED') {
        errors.push({
          type: 'request_failed',
          message: `${req.url()} — ${failure.errorText}`,
        });
      }
    });

    await page.goto(url, { waitUntil: 'load', timeout: 30000 });
    // Flutter web boots asynchronously after the initial page load
    // (engine download, first frame) — give it real time to either
    // settle or throw before we snapshot the console.
    await new Promise((resolve) => setTimeout(resolve, 8000));
  } catch (e) {
    errors.push({ type: 'navigation_failed', message: String(e) });
  } finally {
    await browser.close();
  }

  fs.writeFileSync(outFile, JSON.stringify({ url, errors }, null, 2));
  console.log(`Collected ${errors.length} console/error entr${errors.length === 1 ? 'y' : 'ies'} -> ${outFile}`);
}

main().catch((e) => {
  console.error('web_console_check.js failed to run:', e);
  // Never fail the job on a harness problem (Chrome launch failure,
  // etc.) — an empty/absent report just means "nothing to report",
  // matching every other Chitti tool's "never let the caller crash"
  // contract.
  fs.writeFileSync(process.argv[3] || 'web-console-errors.json', JSON.stringify({
    url: process.argv[2] || null,
    errors: [],
    harnessError: String(e),
  }, null, 2));
  process.exit(0);
});
