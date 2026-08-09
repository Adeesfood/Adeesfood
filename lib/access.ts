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
    name: "Orders",
    description: "Create, track, and manage every guest order.",
    permissionPrefix: "orders.",
    marker: "01",
  },
  {
    name: "Kitchen",
    description: "Coordinate tickets, preparation, and handoff status.",
    permissionPrefix: "kitchen.",
    marker: "02",
  },
  {
    name: "Menu",
    description: "Control availability and prepare the menu catalog.",
    permissionPrefix: "menu.",
    marker: "03",
  },
  {
    name: "Inventory",
    description: "Monitor stock, receiving, transfers, and adjustments.",
    permissionPrefix: "inventory.",
    marker: "04",
  },
  {
    name: "Finance",
    description: "Review settlements, cash controls, and financial reports.",
    permissionPrefix: "finance.",
    marker: "05",
  },
  {
    name: "People & access",
    description: "Manage staff assignments, roles, and security access.",
    permissionPrefix: "security.",
    marker: "06",
  },
] as const;
