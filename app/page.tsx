import { Header } from "../components/Header";
import { HeroStory } from "../components/HeroStory";

export default function Home() {
  const restaurantSchema = {
    "@context": "https://schema.org",
    "@type": "Restaurant",
    name: "Adee's Food",
    slogan: "Irresistible Taste",
    description: "A modern restaurant experience made for every craving.",
  };

  return (
    <>
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>
      <Header />
      <main id="main-content">
        <HeroStory />
      </main>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(restaurantSchema) }}
      />
    </>
  );
}
