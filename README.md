# Adee's Food

Phase 1 of the art-directed website for **Adee's Food — Irresistible Taste**.

This review build includes:

- the responsive primary header;
- a GSAP/ScrollTrigger cinematic hero sequence;
- the Milo + milk tea development media placeholder;
- the continuous transition into the first food reveal;
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
- Placeholder media is built with CSS and labeled in the interface; no fake restaurant imagery or operational details are included.

## Production stack

Next.js App Router, TypeScript, Tailwind CSS, GSAP + ScrollTrigger, and the vinext/Cloudflare runtime.
