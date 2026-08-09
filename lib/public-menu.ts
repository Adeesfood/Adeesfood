export type PublicMenuVariant = {
  id: string;
  name: string | null;
  price_minor: number;
  currency_code: string;
  is_default: boolean;
};

export type PublicModifierOption = {
  id: string;
  name: string;
  price_delta_minor: number;
  currency_code: string;
};

export type PublicModifierGroup = {
  id: string;
  name: string;
  selection_type: "SINGLE" | "MULTIPLE";
  min_selections: number;
  max_selections: number;
  is_required: boolean;
  options: PublicModifierOption[];
};

export type PublicMenuItem = {
  id: string;
  name: string;
  description: string | null;
  price_minor: number;
  currency_code: string;
  image_url: string | null;
  is_price_from: boolean;
  variants: PublicMenuVariant[];
  modifier_groups: PublicModifierGroup[];
};

export type PublicMenuCategory = {
  id: string;
  name: string;
  description: string | null;
  items: PublicMenuItem[];
};

export type PublicMenu = {
  location_id: string;
  location_name: string;
  business_name: string;
  currency_code: string;
  categories: PublicMenuCategory[];
};

export type OnlineOrderState = {
  status: "idle" | "success" | "error";
  message: string;
  orderNumber?: string;
  totalMinor?: number;
  currencyCode?: string;
};

export const initialOnlineOrderState: OnlineOrderState = {
  status: "idle",
  message: "",
};

export function isPublicMenu(value: unknown): value is PublicMenu {
  if (!value || typeof value !== "object") return false;
  const menu = value as Partial<PublicMenu>;
  return (
    typeof menu.location_id === "string" &&
    typeof menu.location_name === "string" &&
    typeof menu.business_name === "string" &&
    typeof menu.currency_code === "string" &&
    Array.isArray(menu.categories)
  );
}

export function formatGhs(amountMinor: number) {
  return new Intl.NumberFormat("en-GH", {
    style: "currency",
    currency: "GHS",
    minimumFractionDigits: 2,
  }).format(amountMinor / 100);
}
