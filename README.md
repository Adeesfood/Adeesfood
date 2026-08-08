# Adee's Food

Phase 1 of the art-directed website for **Adee's Food — Irresistible Taste**.

This review build includes:

- the responsive primary header;
- a GSAP/ScrollTrigger cinematic hero sequence;
- the supplied Milo + milk tea cinematic hero image;
- the continuous transition into the first food reveal;
- the supplied grilled chicken food reveal and Adee's logo;
- accessible reduced-motion behavior; and
- explicit documentation for every missing production asset.

The project intentionally stops after Phase 1. Category storytelling, the complete menu, gallery, story, visit information, ordering, and final polish are deferred until the first experience is approved and real business content is supplied.

## Run locally

Requires Node.js `>=22.13.0`.

```bash
npm install
npm run dev
```

Open the local URL shown in the terminal.

## Quality checks

```bash
npm run build
npm run lint
node --test tests/rendered-html.test.mjs
```

## Project notes

- [DESIGN_PLAN.md](./DESIGN_PLAN.md) defines the visual, motion, responsive, and technical direction.
- [ASSET_REQUIREMENTS.md](./ASSET_REQUIREMENTS.md) inventories all missing media and content.
- `data/menu.ts` remains intentionally empty because approved menu names and prices have not yet been supplied.
- Supplied imagery is stored as optimized WebP assets; no fake operational details are included.

## Production stack

Next.js App Router, TypeScript, Tailwind CSS, GSAP + ScrollTrigger, and Vercel.

## Deployment

The production site is deployed from the `main` branch on Vercel. The repository
includes `vercel.json` so Vercel always detects and builds it as a Next.js app.
