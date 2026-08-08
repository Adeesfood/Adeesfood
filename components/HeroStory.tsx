"use client";

import { useLayoutEffect, useRef } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { MOTION } from "../lib/animations";
import { CinematicMedia } from "./CinematicMedia";
import { FirstFoodReveal } from "./FirstFoodReveal";

const storyFrames = [
  ["Something for", "every craving."],
  ["From the", "first sip..."],
  ["To the", "last bite."],
] as const;

export function HeroStory() {
  const storyRef = useRef<HTMLElement>(null);

  useLayoutEffect(() => {
    gsap.registerPlugin(ScrollTrigger);

    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (mediaQuery.matches || !storyRef.current) return;

    const context = gsap.context(() => {
      const timeline = gsap.timeline({
        defaults: { ease: MOTION.easeInOut },
        scrollTrigger: {
          trigger: storyRef.current,
          start: "top top",
          end: "bottom bottom",
          scrub: MOTION.scrub,
        },
      });

      timeline
        .to("[data-intro-copy]", { autoAlpha: 0, yPercent: -14, duration: 0.7 }, 0.55)
        .to("[data-cinematic-media]", { scale: 1.045, xPercent: -3, duration: 1.2 }, 0.4)
        .to("[data-story-frame='0']", { autoAlpha: 1, yPercent: 0, duration: 0.7 }, 1.05)
        .to("[data-story-frame='0']", { autoAlpha: 0, yPercent: -12, duration: 0.65 }, 2.05)
        .to("[data-story-frame='1']", { autoAlpha: 1, yPercent: 0, duration: 0.7 }, 2.4)
        .to("[data-cinematic-media]", { scale: 1.09, xPercent: -8, yPercent: -2, duration: 1.5 }, 2.15)
        .to("[data-story-frame='1']", { autoAlpha: 0, yPercent: -12, duration: 0.65 }, 3.35)
        .to("[data-story-frame='2']", { autoAlpha: 1, yPercent: 0, duration: 0.7 }, 3.7)
        .to("[data-cinematic-media]", { scale: 1.18, xPercent: -11, yPercent: -4, duration: 1.4 }, 3.55)
        .to("[data-transition-veil]", { autoAlpha: 1, scale: 1.2, duration: 1.25 }, 4.35)
        .to("[data-story-frame='2']", { autoAlpha: 0, duration: 0.55 }, 4.55);
    }, storyRef);

    return () => context.revert();
  }, []);

  return (
    <>
      <section className="hero-story" id="top" ref={storyRef} aria-label="Adee's Food introduction">
        <div className="hero-scene">
          <div className="ambient ambient-left" aria-hidden="true" />
          <div className="ambient ambient-right" aria-hidden="true" />

          <div className="hero-copy hero-intro" data-intro-copy>
            <p className="eyebrow"><span /> Adee&apos;s Food</p>
            <h1>
              Irresistible
              <br />
              <em>Taste.</em>
            </h1>
            <p className="hero-support">Whatever you&apos;re craving, make it worth craving.</p>
            <div className="hero-actions">
              <a className="primary-cta" href="#first-food">
                Explore the menu <span aria-hidden="true">→</span>
              </a>
              <button type="button" className="secondary-cta" disabled title="Visit details required">
                Visit Adee&apos;s
              </button>
            </div>
          </div>

          <div className="story-copy-stack" aria-live="off">
            {storyFrames.map(([lineOne, lineTwo], index) => (
              <div className="story-frame" data-story-frame={index} key={lineOne}>
                <p className="chapter-number">0{index + 2}</p>
                <h2>
                  {lineOne}
                  <br />
                  <em>{lineTwo}</em>
                </h2>
              </div>
            ))}
          </div>

          <CinematicMedia />

          <div className="scroll-cue" aria-hidden="true">
            <span>Scroll to taste</span>
            <i />
          </div>
          <p className="scene-count" aria-hidden="true">01 — 04</p>
          <div className="transition-veil" data-transition-veil aria-hidden="true" />
        </div>
      </section>
      <FirstFoodReveal />
    </>
  );
}
