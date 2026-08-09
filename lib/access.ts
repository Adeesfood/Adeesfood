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

export const managementModules = [
  {
    name: "Dashboard",
    shortName: "Home",
    slug: "",
    description: "Live service, sales, tables, and stock signals.",
    permissionPrefixes: ["dashboard."],
    marker: "01",
  },
  {
    name: "Orders",
    shortName: "Orders",
    slug: "orders",
    description: "Create, settle, and track every guest order.",
    permissionPrefixes: ["orders."],
    marker: "02",
  },
  {
    name: "Kitchen",
    shortName: "Kitchen",
    slug: "kitchen",
    description: "Run live preparation tickets and handoff.",
    permissionPrefixes: ["kitchen."],
    marker: "03",
  },
  {
    name: "Tables",
    shortName: "Tables",
    slug: "tables",
    description: "See covers, occupancy, and table readiness.",
    permissionPrefixes: ["tables."],
    marker: "04",
  },
  {
    name: "Menu",
    shortName: "Menu",
    slug: "menu",
    description: "Control the menu catalog, prices, and availability.",
    permissionPrefixes: ["menu."],
    marker: "05",
  },
  {
    name: "Inventory",
    shortName: "Inventory",
    slug: "inventory",
    description: "Monitor stock, costs, alerts, and movements.",
    permissionPrefixes: ["inventory."],
    marker: "06",
  },
  {
    name: "Recipes",
    shortName: "Recipes",
    slug: "recipes",
    description: "Map dishes to ingredients and live recipe cost.",
    permissionPrefixes: ["recipes."],
    marker: "07",
  },
  {
    name: "Purchasing",
    shortName: "Purchasing",
    slug: "purchasing",
    description: "Issue purchase orders and receive goods into stock.",
    permissionPrefixes: ["purchase_", "goods_receipts.", "supplier_invoices."],
    marker: "08",
  },
  {
    name: "Suppliers",
    shortName: "Suppliers",
    slug: "suppliers",
    description: "Manage supplier contacts and commercial details.",
    permissionPrefixes: ["suppliers."],
    marker: "09",
  },
  {
    name: "Customers",
    shortName: "Customers",
    slug: "customers",
    description: "Keep useful guest profiles and order history.",
    permissionPrefixes: ["customers."],
    marker: "10",
  },
  {
    name: "Reservations",
    shortName: "Reservations",
    slug: "reservations",
    description: "Manage bookings, arrivals, seating, and no-shows.",
    permissionPrefixes: ["reservations."],
    marker: "11",
  },
  {
    name: "Staff",
    shortName: "Staff",
    slug: "staff",
    description: "Review employment, access roles, and shifts.",
    permissionPrefixes: ["staff.", "security."],
    marker: "12",
  },
  {
    name: "Finance",
    shortName: "Finance",
    slug: "finance",
    description: "Track payments, expenses, and daily close.",
    permissionPrefixes: ["payments.", "expenses.", "daily_close.", "finance."],
    marker: "13",
  },
  {
    name: "Reports",
    shortName: "Reports",
    slug: "reports",
    description: "Read live sales, channel, payment, and item facts.",
    permissionPrefixes: ["reports."],
    marker: "14",
  },
  {
    name: "Settings",
    shortName: "Settings",
    slug: "settings",
    description: "Configure the restaurant and inspect the audit trail.",
    permissionPrefixes: ["settings.", "audit.", "security."],
    marker: "15",
  },
] as const;

export type ManagementModule = (typeof managementModules)[number];

export function canAccessModule(permissions: string[], module: ManagementModule) {
  return module.permissionPrefixes.some((prefix) =>
    permissions.some((permission) => permission.startsWith(prefix)),
  );
}
