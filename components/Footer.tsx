import Image from "next/image";
import Link from "next/link";

export function Footer() {
  return (
    <footer className="site-footer" aria-labelledby="footer-title">
      <div className="footer-main">
        <div className="footer-brand">
          <Image
            src="/brand/adees-logo.webp"
            alt=""
            width={640}
            height={640}
            className="footer-logo"
          />
          <div>
            <p className="footer-kicker">Adee&apos;s Food</p>
            <h2 id="footer-title">Irresistible taste, thoughtfully served.</h2>
          </div>
        </div>

        <nav className="footer-links" aria-label="Footer navigation">
          <p>Explore</p>
          <a href="#top">Home</a>
          <Link href="/menu">Order online</Link>
          <a href="#our-story">Our story</a>
          <a href="#gallery">Gallery</a>
          <a href="#visit">Visit</a>
          <Link href="/staff/login">Staff login</Link>
        </nav>

        <div className="footer-access">
          <p>Restaurant operations</p>
          <span>Secure access for authorized Adee&apos;s Food staff.</span>
          <Link href="/staff/login" className="footer-login-link">
            Enter management system <span aria-hidden="true">→</span>
          </Link>
        </div>
      </div>

      <div className="footer-base">
        <p>© 2026 Adee&apos;s Food. All rights reserved.</p>
        <p>GHS · Africa/Accra</p>
      </div>
    </footer>
  );
}
