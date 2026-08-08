# Adee's Food — Phase 1 Design Plan

## Creative direction

Phase 1 is built around the principle **one moment at a time**. The experience stays within one warm, dark cinematic world while the copy changes through a single pinned composition. The Milo + milk tea is treated as an opening sensory object, never as the restaurant's identity.

The emotional sequence is:

1. **Irresistible Taste.** — establish Adee's and the appetite-led promise.
2. **Something for every craving.** — broaden the brand beyond the drink.
3. **From the first sip...** — begin the transition.
4. **To the last bite.** — move the visual language from beverage into food.
5. **Made for cravings.** — reveal the first food moment and the menu call to action.

## Visual system

- Canvas: `#0A0807` warm black with `#11100E` and `#1B120C` roasted depth.
- Primary type: `#F5EFE6` warm cream.
- Secondary type: `#A69C91` warm grey.
- Detail: `#C6A36A` muted champagne.
- Brand punctuation: `#E91E73` pink, used only for small marks and active details.
- Display typography: Cormorant Garamond, chosen for high contrast, expressive curves, and a more editorial hospitality character than a conventional restaurant template.
- Interface typography: Manrope, chosen for quiet clarity in navigation and labels.
- Shapes remain architectural and photographic in proportion. Rounded cards, glass panels, and decorative UI chrome are excluded.

## Phase 1 layout

- **Header** — wordmark placeholder, minimal navigation, and restrained order action. Future-phase destinations remain visibly present but non-functional until their content and URLs exist.
- **Pinned hero story** — a 320–360vh scroll track with a single 100svh stage. Copy crossfades; the beverage media position, scale, warmth, and steam veil evolve gradually.
- **First food reveal** — a nearly full-viewport image stage emerging directly from the hero's dark veil, followed by the Phase 1 menu call to action.

## Animation strategy

- GSAP + ScrollTrigger drives the hero timeline.
- The motion is scrubbed, slow, and continuous with `power3.out` / `power4.inOut` character.
- Headline frames crossfade in place rather than forming separate page sections.
- The media object scales only slightly until the final transition.
- A soft cream/brown veil bridges the beverage and food moments.
- Simple header and button interactions remain CSS-only.
- `prefers-reduced-motion` removes the pinned story and displays a static, readable hero plus the food reveal.

## Responsive strategy

- Desktop uses an asymmetrical left-copy/right-media composition.
- Tablet maintains the split composition with tighter type and spacing.
- Mobile becomes a vertical composition: the beverage object sits above the lower-left headline, the navigation collapses behind a semantic menu button, and scroll distance is reduced.
- Small-height mobile devices reduce decorative details before reducing core headline legibility.
- No horizontal scroll, scroll locking, or touch hijacking is used.

## Technical architecture

- Next.js App Router + TypeScript.
- Tailwind remains available, but the art-directed system is implemented in scoped global CSS for precise control.
- GSAP + ScrollTrigger is the only JavaScript animation system.
- Components are separated into `Header`, `HeroStory`, `CinematicMedia`, and `FirstFoodReveal`.
- Navigation and future menu data live separately under `data/`.
- Production media folders are prepared under `public/images`, `public/video`, and `public/brand` once real assets are delivered.

## Phase boundary

This implementation stops after Phase 1. Category storytelling, menu preview, full menu, gallery, restaurant experience, story, visit details, ordering integration, and the final footer are intentionally deferred until review approval and real content are supplied.
