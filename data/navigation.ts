export type NavigationItem = {
  label: string;
  href?: string;
  phase: 1 | 2 | 3;
};

export const navigationItems: NavigationItem[] = [
  { label: "Menu", href: "#first-food", phase: 1 },
  { label: "Our Story", phase: 3 },
  { label: "Gallery", phase: 3 },
  { label: "Visit", phase: 3 },
];
