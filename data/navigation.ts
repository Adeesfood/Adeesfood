export type NavigationItem = {
  label: string;
  href?: string;
  phase: 1 | 2 | 3;
};

export const navigationItems: NavigationItem[] = [
  { label: "Menu", href: "/menu", phase: 1 },
  { label: "Our Story", href: "#our-story", phase: 1 },
  { label: "Gallery", href: "#gallery", phase: 1 },
  { label: "Visit", href: "#visit", phase: 1 },
];
