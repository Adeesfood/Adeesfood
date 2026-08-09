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

test("seeds the production menu as structured Supabase catalog data", async () => {
  const [migration, composer, moduleActions, modulePage] = await Promise.all([
    readFile(new URL("../supabase/migrations/20260809023102_menu_catalog_seed.sql", import.meta.url), "utf8"),
    readFile(new URL("../components/management/OrderComposer.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/management/module-actions.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/management/[module]/page.tsx", import.meta.url), "utf8"),
  ]);
  const itemSeed = migration.split("with seed(sku, category_name")[1].split(")\n  insert into public.menu_items")[0];
  const variantSeed = migration.split("with seed(item_sku, code, name, price_minor")[1].split(")\n  insert into public.menu_item_variants")[0];

  assert.equal((itemSeed.match(/^      \('/gm) ?? []).length, 108);
  assert.equal((variantSeed.match(/^      \('/gm) ?? []).length, 38);
  assert.match(migration, /create table public\.modifier_groups/);
  assert.match(migration, /create table public\.order_item_modifiers/);
  assert.match(migration, /source_notes/);
  assert.match(migration, /BRG-LOADED-FRIES/);
  assert.doesNotMatch(itemSeed, /PZA-TOPPING/);
  assert.doesNotMatch(`${migration}${composer}${moduleActions}${modulePage}`, /zolara/i);
  assert.match(composer, /menu_item_variant_id/);
  assert.match(composer, /modifier_option_ids/);
  assert.match(moduleActions, /createMenuVariant/);
  assert.match(moduleActions, /menu_item_categories/);
  assert.match(modulePage, /order_item_modifiers\(option_name\)/);
});

test("connects the public menu and checkout to managed online orders", async () => {
  const [
    migration,
    menuPage,
    publicMenu,
    orderAction,
    header,
    hero,
    reveal,
    footer,
    navigation,
    moduleActions,
    modulePage,
    menuCss,
  ] = await Promise.all([
    readFile(new URL("../supabase/migrations/20260809024346_public_online_ordering.sql", import.meta.url), "utf8"),
    readFile(new URL("../app/menu/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/PublicOrderMenu.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/menu/actions.ts", import.meta.url), "utf8"),
    readFile(new URL("../components/Header.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/HeroStory.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/FirstFoodReveal.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/Footer.tsx", import.meta.url), "utf8"),
    readFile(new URL("../data/navigation.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/management/module-actions.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/management/[module]/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/menu/menu.css", import.meta.url), "utf8"),
  ]);

  assert.match(migration, /create or replace function public\.get_public_menu/);
  assert.match(migration, /create or replace function public\.create_online_order/);
  assert.match(migration, /security definer/);
  assert.match(migration, /server-side|reprices every item server-side/i);
  assert.match(migration, /guest_phone_normalized/);
  assert.match(migration, /source_reference/);
  assert.match(migration, /order_source = 'WEBSITE'/);
  assert.match(migration, /p_action = 'SEND_KITCHEN'/);
  assert.match(migration, /grant execute on function public\.create_online_order[^;]+to anon, authenticated/s);
  assert.doesNotMatch(migration, /grant (select|insert|update|delete)[^;]+to anon/i);

  assert.match(menuPage, /get_public_menu/);
  assert.match(menuPage, /randomUUID/);
  assert.match(publicMenu, /useActionState/);
  assert.match(publicMenu, /Pickup/);
  assert.match(publicMenu, /Delivery/);
  assert.match(publicMenu, /items_json/);
  assert.match(publicMenu, /Pay at/);
  assert.match(orderAction, /create_online_order/);
  assert.doesNotMatch(`${menuPage}${publicMenu}${orderAction}`, /service[_-]?role|sb_secret_/i);

  assert.match(`${header}${hero}${reveal}${footer}${navigation}`, /href="\/menu"|href: "\/menu"/);
  assert.doesNotMatch(`${hero}${reveal}`, /disabled title="(Ordering|Full menu|Visit)/i);
  assert.match(moduleActions, /orders\.send_kitchen/);
  assert.match(modulePage, /Accept &amp; send/);
  assert.match(modulePage, /Website order/);
  assert.match(menuCss, /@media \(max-width: 680px\)/);
  assert.match(menuCss, /mobile-cart-jump/);
});

test("makes every landing navigation destination real and responsive", async () => {
  const [page, details, navigation, globalCss] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/LandingDetails.tsx", import.meta.url), "utf8"),
    readFile(new URL("../data/navigation.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
  ]);

  assert.match(page, /LandingDetails/);
  assert.match(details, /id="our-story"/);
  assert.match(details, /id="gallery"/);
  assert.match(details, /id="visit"/);
  assert.match(navigation, /href: "#our-story"/);
  assert.match(navigation, /href: "#gallery"/);
  assert.match(navigation, /href: "#visit"/);
  assert.match(globalCss, /@media \(max-width: 430px\)/);
  assert.match(globalCss, /landing-gallery-grid/);
  assert.doesNotMatch(navigation, /\{ label: "(Our Story|Gallery|Visit)", phase:/);
});
