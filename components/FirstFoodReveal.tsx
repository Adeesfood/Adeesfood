export function FirstFoodReveal() {
  return (
    <section className="first-food" id="first-food" aria-labelledby="food-title">
      <div
        className="first-food-media"
        role="img"
        aria-label="Development placeholder for the first cinematic food photograph"
      >
        <div className="plate-placeholder" aria-hidden="true">
          <span />
        </div>
        <p className="food-asset-marker">
          <span>Asset required</span>
          First food reveal — landscape 2400 × 1600
        </p>
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
