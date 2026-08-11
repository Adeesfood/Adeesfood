const PATHS: Record<string, string> = {
  dashboard: "M4 4h7v7H4V4Zm9 0h7v4h-7V4Zm0 7h7v9h-7v-9ZM4 13h7v7H4v-7Z",
  orders: "M6 3h12v18l-3-2-3 2-3-2-3 2V3Zm3 5h6M9 11h6M9 14h4",
  kitchen: "M12 3c2 2.5.5 3.5 0 5-1 1.3-1 2.7 0 4 1.5-1.3 2.5-3 2-5 2 1.5 3 3.5 3 5.5a5 5 0 1 1-10 0C7 9.5 9.5 6 12 3Z",
  deliveries: "M3 7h11v8H3V7Zm11 3h4l3 3v2h-7v-5ZM6.5 18a1.7 1.7 0 1 0 0-3.4 1.7 1.7 0 0 0 0 3.4Zm11 0a1.7 1.7 0 1 0 0-3.4 1.7 1.7 0 0 0 0 3.4Z",
  tables: "M3 8h18M5 8v12M19 8v12M3 8l2-4h14l2 4",
  reservations: "M7 3v3M17 3v3M4 8h16M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1Zm2 8h3m-3 3h6",
  menu: "M8 3v7a2 2 0 0 1-2 2v9m2-18v18M16 3v18M16 3c2.2 0 4 1.8 4 4v3h-4",
  inventory: "M12 3 4 7v10l8 4 8-4V7l-8-4Zm0 0v18M4 7l8 4 8-4",
  recipes: "M9 3h6v3H9V3ZM6 5h12v16H6V5Zm3 6h6M9 14h6M9 17h4",
  purchasing: "M4 5h2l2 12h10l2-8H7M9 20a1 1 0 1 0 0-2 1 1 0 0 0 0 2Zm8 0a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z",
  suppliers: "M4 21V9l8-5 8 5v12M9 21v-6h6v6M4 9h16",
  customers: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-7 9c0-3.9 3.1-7 7-7s7 3.1 7 7",
  staff: "M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM3 20c0-3.3 2.7-6 6-6s6 2.7 6 6M16 5.5a3 3 0 0 1 0 6M19 20c0-2.8-1.8-5.1-4-5.8",
  finance: "M12 3v18M7 7.5h6a2.5 2.5 0 0 1 0 5H9a2.5 2.5 0 0 0 0 5h7",
  reports: "M5 21V10m6 11V5m6 16v-8",
  settings:
    "M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7ZM4 12a8 8 0 0 1 .3-2.2l-1.8-1.4 1.5-2.6 2.1.8a8 8 0 0 1 1.9-1.1L8.4 3h3l.4 2.5a8 8 0 0 1 1.9 1.1l2.1-.8 1.5 2.6-1.8 1.4c.2.7.3 1.4.3 2.2s-.1 1.5-.3 2.2l1.8 1.4-1.5 2.6-2.1-.8a8 8 0 0 1-1.9 1.1L11.4 21h-3l-.4-2.5a8 8 0 0 1-1.9-1.1l-2.1.8-1.5-2.6 1.8-1.4A8 8 0 0 1 4 12Z",
};

export function NavIcon({ name }: { name: string }) {
  const d = PATHS[name] ?? PATHS.settings;
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d} />
    </svg>
  );
}
