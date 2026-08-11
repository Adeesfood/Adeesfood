export type StaffAssignment = {
  assignment_id: string;
  organization_id: string;
  organization_name: string;
  location_id: string | null;
  location_name: string | null;
  role_code: string;
  role_name: string;
};

export type AccessContext = {
  user_id: string | null;
  assignments: StaffAssignment[];
  permissions: string[];
};

const EMPTY_ACCESS: AccessContext = {
  user_id: null,
  assignments: [],
  permissions: [],
};

export function parseAccessContext(value: unknown): AccessContext {
  if (!value || typeof value !== "object") return EMPTY_ACCESS;

  const candidate = value as Partial<AccessContext>;
  const assignments = Array.isArray(candidate.assignments)
    ? candidate.assignments.filter(
        (assignment): assignment is StaffAssignment =>
          Boolean(
            assignment &&
              typeof assignment === "object" &&
              typeof assignment.organization_id === "string" &&
              typeof assignment.organization_name === "string" &&
              typeof assignment.role_code === "string",
          ),
      )
    : [];
  const permissions = Array.isArray(candidate.permissions)
    ? candidate.permissions.filter((permission): permission is string => typeof permission === "string")
    : [];

  return {
    user_id: typeof candidate.user_id === "string" ? candidate.user_id : null,
    assignments,
    permissions,
  };
}

export const navGroups = ["Overview", "Operations", "Catalog & stock", "Supply chain", "People", "Insights", "System"] as const;

export const managementModules = [
  {
    name: "Dashboard",
    shortName: "Dashboard",
    slug: "",
    description: "Live pickup, delivery, sales, and stock signals.",
    permissionPrefixes: ["dashboard."],
    group: "Overview",
    icon: "dashboard",
  },
  {
    name: "Orders",
    shortName: "Orders",
    slug: "orders",
    description: "Create, settle, and track every guest order.",
    permissionPrefixes: ["orders."],
    group: "Operations",
    icon: "orders",
  },
  {
    name: "Deliveries",
    shortName: "Deliveries",
    slug: "deliveries",
    description: "Assign riders, track dispatch, and settle cash on delivery.",
    permissionPrefixes: ["deliveries."],
    group: "Operations",
    icon: "deliveries",
  },
  {
    name: "Tables",
    shortName: "Tables",
    slug: "tables",
    description: "See covers, occupancy, and table readiness.",
    permissionPrefixes: ["tables."],
    group: "Operations",
    icon: "tables",
    dineInOnly: true,
  },
  {
    name: "Reservations",
    shortName: "Reservations",
    slug: "reservations",
    description: "Manage bookings, arrivals, seating, and no-shows.",
    permissionPrefixes: ["reservations."],
    group: "Operations",
    icon: "reservations",
    dineInOnly: true,
  },
  {
    name: "Menu",
    shortName: "Menu",
    slug: "menu",
    description: "Control the menu catalog, prices, and availability.",
    permissionPrefixes: ["menu."],
    group: "Catalog & stock",
    icon: "menu",
  },
  {
    name: "Inventory",
    shortName: "Inventory",
    slug: "inventory",
    description: "Monitor stock, costs, alerts, and movements.",
    permissionPrefixes: ["inventory."],
    group: "Catalog & stock",
    icon: "inventory",
  },
  {
    name: "Recipes",
    shortName: "Recipes",
    slug: "recipes",
    description: "Map dishes to ingredients and live recipe cost.",
    permissionPrefixes: ["recipes."],
    group: "Catalog & stock",
    icon: "recipes",
  },
  {
    name: "Purchasing",
    shortName: "Purchasing",
    slug: "purchasing",
    description: "Issue purchase orders and receive goods into stock.",
    permissionPrefixes: ["purchase_", "goods_receipts.", "supplier_invoices."],
    group: "Supply chain",
    icon: "purchasing",
  },
  {
    name: "Suppliers",
    shortName: "Suppliers",
    slug: "suppliers",
    description: "Manage supplier contacts and commercial details.",
    permissionPrefixes: ["suppliers."],
    group: "Supply chain",
    icon: "suppliers",
  },
  {
    name: "Customers",
    shortName: "Customers",
    slug: "customers",
    description: "Keep useful guest profiles, addresses, and order history.",
    permissionPrefixes: ["customers."],
    group: "People",
    icon: "customers",
  },
  {
    name: "Staff",
    shortName: "Staff",
    slug: "staff",
    description: "Review employment, access roles, and shifts.",
    permissionPrefixes: ["staff.", "security."],
    group: "People",
    icon: "staff",
  },
  {
    name: "Finance",
    shortName: "Finance",
    slug: "finance",
    description: "Track payments, expenses, and daily close.",
    permissionPrefixes: ["payments.", "expenses.", "daily_close.", "finance."],
    group: "Insights",
    icon: "finance",
  },
  {
    name: "Reports",
    shortName: "Reports",
    slug: "reports",
    description: "Read live sales, channel, payment, and item facts.",
    permissionPrefixes: ["reports."],
    group: "Insights",
    icon: "reports",
  },
  {
    name: "Settings",
    shortName: "Settings",
    slug: "settings",
    description: "Configure the restaurant and inspect the audit trail.",
    permissionPrefixes: ["settings.", "audit.", "security."],
    group: "System",
    icon: "settings",
  },
] as const;

export type ManagementModule = (typeof managementModules)[number];

export function canAccessModule(
  permissions: string[],
  module: ManagementModule,
  dineInEnabled: boolean,
) {
  if ("dineInOnly" in module && module.dineInOnly && !dineInEnabled) return false;
  return module.permissionPrefixes.some((prefix) =>
    permissions.some((permission) => permission.startsWith(prefix)),
  );
}
