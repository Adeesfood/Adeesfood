import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("defines the Adee's Food Phase 1 experience", async () => {
  const [layout, page, hero, reveal] = await Promise.all([
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/HeroStory.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/FirstFoodReveal.tsx", import.meta.url), "utf8"),
  ]);

  assert.match(layout, /Adee's Food — Irresistible Taste/i);
  assert.match(page, /application\/ld\+json/i);
  assert.match(hero, /Irresistible/);
  assert.match(hero, /Something for/);
  assert.match(hero, /first sip/i);
  assert.match(hero, /last bite/i);
  assert.match(reveal, /Made for/);
  assert.match(reveal, /Asset required/i);
  assert.doesNotMatch(`${layout}${hero}${reveal}`, /codex-preview|Your site is taking shape|react-loading-skeleton/i);
});

test("keeps motion accessible and the prototype asset-honest", async () => {
  const [css, page, menu, assets] = await Promise.all([
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../data/menu.ts", import.meta.url), "utf8"),
    readFile(new URL("../ASSET_REQUIREMENTS.md", import.meta.url), "utf8"),
  ]);

  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /overflow-x:\s*hidden/);
  assert.match(page, /Restaurant/);
  assert.match(menu, /menuCategories:\s*MenuCategory\[\]\s*=\s*\[\]/);
  assert.match(assets, /No Adee's production assets were included/);
  assert.doesNotMatch(page, /address|telephone|openingHours|priceRange/);
});

test("uses the native Vercel Next.js build", async () => {
  const [packageSource, vercelSource] = await Promise.all([
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../vercel.json", import.meta.url), "utf8"),
  ]);
  const packageJson = JSON.parse(packageSource);
  const vercel = JSON.parse(vercelSource);

  assert.equal(packageJson.scripts.build, "next build");
  assert.equal(vercel.framework, "nextjs");
  assert.doesNotMatch(packageSource, /vinext|wrangler|cloudflare/i);
});
