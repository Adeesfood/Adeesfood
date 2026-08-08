import Image from "next/image";

export function FirstFoodReveal() {
  return (
    <section className="first-food" id="first-food" aria-labelledby="food-title">
      <div className="first-food-media">
        <Image
          className="first-food-image"
          src="/images/menu/grilled-chicken-reveal.webp"
          alt="Glazed grilled chicken with roasted potatoes and peppers, served hot"
          fill
          quality={90}
          sizes="100vw"
        />
      </div>

      <div className="first-food-copy">
        <p className="eyebrow">Adee&apos;s Food</p>
        <h2 id="food-title">
          Made for
          <br />
          <em>cravings.</em>
        </h2>
        <button type="button" className="text-cta" disabled title="Full menu arrives in Phase 3">
          Explore the menu <span aria-hidden="true">→</span>
        </button>
      </div>
    </section>
  );
}
