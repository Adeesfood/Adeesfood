import type { Metadata } from "next";
import { Cormorant_Garamond, Manrope } from "next/font/google";
import "./globals.css";

const manrope = Manrope({
  variable: "--font-sans",
  subsets: ["latin"],
});

const cormorant = Cormorant_Garamond({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  title: "Adee's Food — Irresistible Taste",
  description:
    "Whatever you're craving, make it worth craving. Discover the Adee's Food experience.",
  applicationName: "Adee's Food",
  openGraph: {
    title: "Adee's Food — Irresistible Taste",
    description: "Whatever you're craving, make it worth craving.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Adee's Food — Irresistible Taste",
    description: "Whatever you're craving, make it worth craving.",
  },
};

export const viewport = {
  themeColor: "#0A0807",
  colorScheme: "dark",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${manrope.variable} ${cormorant.variable}`}>
        {children}
      </body>
    </html>
  );
}
