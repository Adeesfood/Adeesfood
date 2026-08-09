import Image from "next/image";
import Link from "next/link";

export function LandingDetails() {
  return (
    <div className="landing-details">
      <section className="landing-story" id="our-story" aria-labelledby="story-title">
        <div>
          <p className="eyebrow"><span /> Our story</p>
          <h2 id="story-title">Good food for <em>every mood.</em></h2>
        </div>
        <div className="landing-story-copy">
          <p>Adee&apos;s Food brings comforting favorites, bold grills, generous portions, and drinks made for the moment together in one menu.</p>
          <p>Every website order goes directly into our restaurant management system, ready for the team to confirm and prepare.</p>
          <Link href="/menu">Order from the live menu <span aria-hidden="true">→</span></Link>
        </div>
      </section>

      <section className="landing-gallery" id="gallery" aria-labelledby="gallery-title">
        <div className="landing-section-head">
          <p className="eyebrow"><span /> A taste of Adee&apos;s</p>
          <h2 id="gallery-title">Made to be <em>remembered.</em></h2>
        </div>
        <div className="landing-gallery-grid">
          <figure>
            <Image src="/images/menu/grilled-chicken-reveal.webp" alt="Glazed grilled chicken with roasted potatoes and peppers" fill sizes="(max-width: 720px) 100vw, 62vw" />
            <figcaption><span>01</span> From the grill</figcaption>
          </figure>
          <figure>
            <Image src="/images/hero/milo-milk-tea-hero.webp" alt="A steaming cup of creamy Milo and milk tea" fill sizes="(max-width: 720px) 100vw, 38vw" />
            <figcaption><span>02</span> The perfect sip</figcaption>
          </figure>
        </div>
      </section>

      <section className="landing-visit" id="visit" aria-labelledby="visit-title">
        <div>
          <p className="eyebrow"><span /> Visit or order</p>
          <h2 id="visit-title">Your next craving <em>starts here.</em></h2>
        </div>
        <div className="landing-visit-cards">
          <article><span>Location</span><strong>Main Branch</strong><p>Ghana · Africa/Accra time</p></article>
          <article><span>Contact</span><strong>Adee&apos;s Food</strong><a href="mailto:adeesfoods1@gmail.com">adeesfoods1@gmail.com</a></article>
          <article className="is-order"><span>Ordering</span><strong>Pickup or delivery</strong><Link href="/menu">Start an order <b aria-hidden="true">→</b></Link></article>
        </div>
      </section>
    </div>
  );
}
