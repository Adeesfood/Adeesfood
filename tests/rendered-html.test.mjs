import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Adee's Food Phase 1 experience", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Adee&#x27;s Food — Irresistible Taste<\/title>/i);
  assert.match(html, /Irresistible/);
  assert.match(html, /Something for/);
  assert.match(html, /first sip/i);
  assert.match(html, /last bite/i);
  assert.match(html, /Made for/);
  assert.match(html, /Asset required/i);
  assert.match(html, /application\/ld\+json/i);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape|react-loading-skeleton/i);
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
