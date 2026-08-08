import Image from "next/image";

export function CinematicMedia() {
  return (
    <div className="cinematic-media" data-cinematic-media>
      <Image
        className="hero-media-image"
        src="/images/hero/milo-milk-tea-hero.webp"
        alt="A steaming cup of creamy Milo and milk tea in warm restaurant lighting"
        fill
        priority
        quality={90}
        sizes="100vw"
      />
      <div className="hero-media-overlay" aria-hidden="true" />
    </div>
  );
}
