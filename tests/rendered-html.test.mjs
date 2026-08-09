import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("defines the Adee's Food Phase 1 experience", async () => {
  const [layout, page, hero, media, reveal] = await Promise.all([
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/HeroStory.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/CinematicMedia.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/FirstFoodReveal.tsx", import.meta.url), "utf8"),
  ]);

  assert.match(layout, /Adee's Food — Irresistible Taste/i);
  assert.match(page, /application\/ld\+json/i);
  assert.match(hero, /Irresistible/);
  assert.match(hero, /Something for/);
  assert.match(hero, /first sip/i);
  assert.match(hero, /last bite/i);
  assert.match(reveal, /Made for/);
  assert.match(media, /milo-milk-tea-hero\.webp/i);
  assert.match(reveal, /grilled-chicken-reveal\.webp/i);
  assert.doesNotMatch(`${media}${reveal}`, /Asset required/i);
  assert.doesNotMatch(`${layout}${hero}${media}${reveal}`, /codex-preview|Your site is taking shape|react-loading-skeleton/i);
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
  assert.match(assets, /Three approved raster assets/);
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

test("connects staff login to protected Supabase management access", async () => {
  const [header, footer, login, management, managementSession, proxy, serverClient, envExample, packageSource] =
    await Promise.all([
      readFile(new URL("../components/Header.tsx", import.meta.url), "utf8"),
      readFile(new URL("../components/Footer.tsx", import.meta.url), "utf8"),
      readFile(new URL("../components/StaffLoginForm.tsx", import.meta.url), "utf8"),
      readFile(new URL("../app/management/page.tsx", import.meta.url), "utf8"),
      readFile(new URL("../lib/management.ts", import.meta.url), "utf8"),
      readFile(new URL("../lib/supabase/proxy.ts", import.meta.url), "utf8"),
      readFile(new URL("../lib/supabase/server.ts", import.meta.url), "utf8"),
      readFile(new URL("../.env.example", import.meta.url), "utf8"),
      readFile(new URL("../package.json", import.meta.url), "utf8"),
    ]);

  assert.match(header, /Staff login/i);
  assert.match(footer, /Enter management system/i);
  assert.match(login, /signInWithPassword/);
  assert.match(login, /get_my_access_context/);
  assert.match(management, /getManagementSession/);
  assert.match(managementSession, /getClaims/);
  assert.match(managementSession, /get_my_access_context/);
  assert.match(managementSession, /from\("locations"\)/);
  assert.match(managementSession, /if \(!assignment\.location_id\)/);
  assert.match(proxy, /getClaims/);
  assert.match(proxy, /\/management/);
  assert.match(serverClient, /createServerClient/);
  assert.match(envExample, /NEXT_PUBLIC_SUPABASE_URL/);
  assert.match(envExample, /NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY/);
  assert.doesNotMatch(
    `${header}${footer}${login}${management}${managementSession}${proxy}${serverClient}${envExample}${packageSource}`,
    /service[_-]?role|sb_secret_/i,
  );
});
