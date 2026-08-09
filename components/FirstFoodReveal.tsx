import Image from "next/image";
import Link from "next/link";

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
        <Link href="/menu" className="text-cta">
          Explore the menu <span aria-hidden="true">→</span>
        </Link>
      </div>
    </section>
  );
}
