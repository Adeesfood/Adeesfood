"use client";

import { useEffect, useState } from "react";
import { navigationItems } from "../data/navigation";

export function Header() {
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setIsOpen(false);
    };

    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, []);

  return (
    <header className="site-header" data-site-header>
      <a className="wordmark" href="#top" aria-label="Adee's Food home">
        <span className="wordmark-name">ADEE&apos;S</span>
        <span className="wordmark-sub">FOOD</span>
      </a>

      <nav className="desktop-nav" aria-label="Primary navigation">
        {navigationItems.map((item) =>
          item.href ? (
            <a key={item.label} href={item.href}>
              {item.label}
            </a>
          ) : (
            <button
              key={item.label}
              type="button"
              disabled
              title={`${item.label} will be added in Phase ${item.phase}`}
            >
              {item.label}
            </button>
          ),
        )}
      </nav>

      <div className="header-actions">
        <button
          className="order-link"
          type="button"
          disabled
          title="Ordering URL required"
        >
          Order now <span aria-hidden="true">↗</span>
        </button>
        <button
          className="menu-toggle"
          type="button"
          aria-expanded={isOpen}
          aria-controls="mobile-navigation"
          aria-label={isOpen ? "Close menu" : "Open menu"}
          onClick={() => setIsOpen((current) => !current)}
        >
          <span />
          <span />
        </button>
      </div>

      <div
        className={`mobile-nav-panel${isOpen ? " is-open" : ""}`}
        id="mobile-navigation"
        aria-hidden={!isOpen}
      >
        <nav aria-label="Mobile navigation">
          {navigationItems.map((item, index) =>
            item.href ? (
              <a
                key={item.label}
                href={item.href}
                onClick={() => setIsOpen(false)}
                tabIndex={isOpen ? 0 : -1}
              >
                <span>0{index + 1}</span>
                {item.label}
              </a>
            ) : (
              <button
                key={item.label}
                type="button"
                disabled
                tabIndex={-1}
                title={`${item.label} will be added in Phase ${item.phase}`}
              >
                <span>0{index + 1}</span>
                {item.label}
              </button>
            ),
          )}
        </nav>
        <p>IRRESISTIBLE TASTE.</p>
      </div>
    </header>
  );
}
