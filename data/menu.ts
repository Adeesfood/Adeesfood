export type MenuPrice = {
  label?: string;
  amount: string;
};

export type MenuItem = {
  name: string;
  description?: string;
  prices: MenuPrice[];
};

export type MenuCategory = {
  name: string;
  items: MenuItem[];
};

// Intentionally empty: no source menu or prices were supplied with Phase 1.
// Future phases should populate this array verbatim from approved restaurant data.
export const menuCategories: MenuCategory[] = [];
