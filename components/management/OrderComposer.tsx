"use client";

import { useMemo, useState } from "react";
import { createOrder } from "@/app/management/module-actions";
import { FormSubmitButton } from "./FormSubmitButton";

type MenuItem = {
  id: string;
  name: string;
  description: string | null;
  price_minor: number;
  station: string;
  is_available: boolean;
  menu_categories: { name: string } | null;
};

type SelectOption = { id: string; label: string };
type CartLine = { menu_item_id: string; name: string; quantity: number; price_minor: number };

export function OrderComposer({ menuItems, customers, tables }: {
  menuItems: MenuItem[];
  customers: SelectOption[];
  tables: SelectOption[];
}) {
  const [channel, setChannel] = useState("DINE_IN");
  const [category, setCategory] = useState("All");
  const [search, setSearch] = useState("");
  const [cart, setCart] = useState<CartLine[]>([]);
  const categories = useMemo(() => ["All", ...Array.from(new Set(menuItems.map((item) => item.menu_categories?.name ?? "Other")))], [menuItems]);
  const filtered = menuItems.filter((item) => {
    const categoryMatch = category === "All" || item.menu_categories?.name === category;
    const searchMatch = item.name.toLowerCase().includes(search.toLowerCase());
    return categoryMatch && searchMatch;
  });
  const total = cart.reduce((sum, line) => sum + line.price_minor * line.quantity, 0);

  function addItem(item: MenuItem) {
    setCart((current) => {
      const existing = current.find((line) => line.menu_item_id === item.id);
      if (existing) return current.map((line) => line.menu_item_id === item.id ? { ...line, quantity: line.quantity + 1 } : line);
      return [...current, { menu_item_id: item.id, name: item.name, quantity: 1, price_minor: item.price_minor }];
    });
  }

  function changeQuantity(id: string, change: number) {
    setCart((current) => current
      .map((line) => line.menu_item_id === id ? { ...line, quantity: line.quantity + change } : line)
      .filter((line) => line.quantity > 0));
  }

  return (
    <form action={createOrder} className="pos-layout">
      <input type="hidden" name="items_json" value={JSON.stringify(cart.map(({ menu_item_id, quantity }) => ({ menu_item_id, quantity })))} />
      <input type="hidden" name="channel" value={channel} />
      <section className="pos-catalog">
        <div className="pos-order-types" role="group" aria-label="Order channel">
          {["DINE_IN", "TAKEAWAY", "DELIVERY", "PHONE", "WHATSAPP"].map((option) => (
            <button className={channel === option ? "is-active" : ""} type="button" onClick={() => setChannel(option)} key={option}>{option.replaceAll("_", " ")}</button>
          ))}
        </div>
        <div className="pos-tools">
          <input aria-label="Search menu" placeholder="Search the menu…" value={search} onChange={(event) => setSearch(event.target.value)} />
          <div className="pos-categories">{categories.map((name) => <button type="button" className={category === name ? "is-active" : ""} onClick={() => setCategory(name)} key={name}>{name}</button>)}</div>
        </div>
        <div className="pos-items">
          {filtered.length ? filtered.map((item) => (
            <button className="pos-item" type="button" onClick={() => addItem(item)} disabled={!item.is_available} key={item.id}>
              <span>{item.station}</span><strong>{item.name}</strong><small>{item.description || "Ready to add"}</small><b>GH₵ {(item.price_minor / 100).toFixed(2)}</b>
              {!item.is_available ? <em>Sold out</em> : <i aria-hidden="true">＋</i>}
            </button>
          )) : <div className="ops-empty is-wide"><strong>No menu items match</strong><p>Add menu items or change the current filter.</p></div>}
        </div>
      </section>

      <aside className="pos-cart">
        <div className="pos-cart-head"><div><p className="ops-kicker">Current order</p><h2>{channel.replaceAll("_", " ")}</h2></div><span>{cart.reduce((sum, line) => sum + line.quantity, 0)} items</span></div>
        <div className="pos-customer-fields">
          <label>Customer<select name="customer_id" defaultValue=""><option value="">Walk-in guest</option>{customers.map((customer) => <option value={customer.id} key={customer.id}>{customer.label}</option>)}</select></label>
          {channel === "DINE_IN" ? <label>Table<select name="table_id" required defaultValue=""><option value="" disabled>Choose a table</option>{tables.map((table) => <option value={table.id} key={table.id}>{table.label}</option>)}</select></label> : null}
        </div>
        <div className="pos-cart-lines">
          {cart.length ? cart.map((line) => (
            <div className="pos-cart-line" key={line.menu_item_id}><div><strong>{line.name}</strong><small>GH₵ {(line.price_minor / 100).toFixed(2)} each</small></div><div className="pos-quantity"><button type="button" onClick={() => changeQuantity(line.menu_item_id, -1)}>−</button><span>{line.quantity}</span><button type="button" onClick={() => changeQuantity(line.menu_item_id, 1)}>＋</button></div><b>GH₵ {((line.price_minor * line.quantity) / 100).toFixed(2)}</b></div>
          )) : <div className="ops-empty"><strong>Your order is empty</strong><p>Choose an available menu item to begin.</p></div>}
        </div>
        <label className="pos-note">Order note<textarea name="notes" placeholder="Allergies, preparation note, delivery detail…" rows={2} /></label>
        <div className="pos-total"><span>Total</span><strong>GH₵ {(total / 100).toFixed(2)}</strong></div>
        <FormSubmitButton pendingText="Sending order…">Send to kitchen</FormSubmitButton>
      </aside>
    </form>
  );
}
