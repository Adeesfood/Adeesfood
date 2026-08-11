"use client";

import { useMemo, useState } from "react";
import { createOrder } from "@/app/management/module-actions";
import { FormSubmitButton } from "./FormSubmitButton";

type MenuVariant = {
  id: string;
  name: string | null;
  price_minor: number;
  is_default: boolean;
  is_available: boolean;
  is_active: boolean;
  sort_order: number;
};

type ModifierOption = {
  id: string;
  name: string;
  price_delta_minor: number;
  is_available: boolean;
  is_active: boolean;
  sort_order: number;
};

type ModifierGroup = {
  id: string;
  name: string;
  selection_type: "SINGLE" | "MULTIPLE";
  min_selections: number;
  max_selections: number;
  is_required: boolean;
  options: ModifierOption[];
};

type MenuItem = {
  id: string;
  name: string;
  description: string | null;
  price_minor: number;
  station: string;
  is_available: boolean;
  is_price_from: boolean;
  categories: string[];
  variants: MenuVariant[];
  modifier_groups: ModifierGroup[];
};

type SelectOption = { id: string; label: string };
type CartLine = {
  key: string;
  menu_item_id: string;
  menu_item_variant_id: string | null;
  modifier_option_ids: string[];
  name: string;
  variant_name: string | null;
  modifier_names: string[];
  quantity: number;
  price_minor: number;
};

function money(amount: number) {
  return `GH₵ ${(amount / 100).toFixed(2)}`;
}

const CHANNEL_LABELS: Record<string, string> = {
  WALK_IN: "Walk-in",
  TAKEAWAY: "Pickup",
  DELIVERY: "Delivery",
  PHONE: "Phone order",
  WHATSAPP: "WhatsApp order",
  DINE_IN: "Dine-in",
};

export function OrderComposer({ menuItems, customers, tables, dineInEnabled }: {
  menuItems: MenuItem[];
  customers: SelectOption[];
  tables: SelectOption[];
  dineInEnabled: boolean;
}) {
  const channelOptions = dineInEnabled
    ? ["WALK_IN", "DINE_IN", "TAKEAWAY", "DELIVERY", "PHONE", "WHATSAPP"]
    : ["WALK_IN", "TAKEAWAY", "DELIVERY", "PHONE", "WHATSAPP"];
  const [channel, setChannel] = useState("WALK_IN");
  const [category, setCategory] = useState("All");
  const [search, setSearch] = useState("");
  const [cart, setCart] = useState<CartLine[]>([]);
  const [variantSelections, setVariantSelections] = useState<Record<string, string>>({});
  const [modifierSelections, setModifierSelections] = useState<Record<string, string[]>>({});
  const [selectionError, setSelectionError] = useState<string | null>(null);
  const [customerId, setCustomerId] = useState("");

  const categories = useMemo(
    () => ["All", ...Array.from(new Set(menuItems.flatMap((item) => item.categories)))],
    [menuItems],
  );
  const filtered = menuItems.filter((item) => {
    const categoryMatch = category === "All" || item.categories.includes(category);
    const searchMatch = `${item.name} ${item.description ?? ""}`.toLowerCase().includes(search.toLowerCase());
    return categoryMatch && searchMatch;
  });
  const total = cart.reduce((sum, line) => sum + line.price_minor * line.quantity, 0);

  function activeVariants(item: MenuItem) {
    return item.variants.filter((variant) => variant.is_active && variant.is_available);
  }

  function selectedVariant(item: MenuItem) {
    const variants = activeVariants(item);
    return variants.find((variant) => variant.id === variantSelections[item.id])
      ?? variants.find((variant) => variant.is_default)
      ?? variants[0]
      ?? null;
  }

  function selectedOptions(item: MenuItem, group: ModifierGroup) {
    const available = group.options.filter((option) => option.is_active && option.is_available);
    const selected = modifierSelections[`${item.id}:${group.id}`];
    if (selected) return selected.filter((id) => available.some((option) => option.id === id));
    if (group.selection_type === "SINGLE" && group.min_selections > 0 && available[0]) return [available[0].id];
    return [];
  }

  function setSingleModifier(item: MenuItem, group: ModifierGroup, optionId: string) {
    setModifierSelections((current) => ({ ...current, [`${item.id}:${group.id}`]: optionId ? [optionId] : [] }));
  }

  function toggleMultipleModifier(item: MenuItem, group: ModifierGroup, optionId: string) {
    const key = `${item.id}:${group.id}`;
    setModifierSelections((current) => {
      const selected = current[key] ?? [];
      if (selected.includes(optionId)) return { ...current, [key]: selected.filter((id) => id !== optionId) };
      if (selected.length >= group.max_selections) return current;
      return { ...current, [key]: [...selected, optionId] };
    });
  }

  function addItem(item: MenuItem) {
    const variant = selectedVariant(item);
    const modifierOptions = item.modifier_groups.flatMap((group) => {
      const selected = selectedOptions(item, group);
      if (selected.length < group.min_selections || selected.length > group.max_selections) {
        throw new Error(`${group.name} requires ${group.min_selections === group.max_selections ? group.min_selections : `${group.min_selections}–${group.max_selections}`} selection${group.max_selections === 1 ? "" : "s"}.`);
      }
      return group.options.filter((option) => selected.includes(option.id));
    });

    const modifierIds = modifierOptions.map((option) => option.id).sort();
    const key = `${item.id}:${variant?.id ?? "base"}:${modifierIds.join(",")}`;
    const unitPrice = (variant?.price_minor ?? item.price_minor)
      + modifierOptions.reduce((sum, option) => sum + option.price_delta_minor, 0);
    setSelectionError(null);
    setCart((current) => {
      const existing = current.find((line) => line.key === key);
      if (existing) return current.map((line) => line.key === key ? { ...line, quantity: line.quantity + 1 } : line);
      return [...current, {
        key,
        menu_item_id: item.id,
        menu_item_variant_id: variant?.id ?? null,
        modifier_option_ids: modifierIds,
        name: item.name,
        variant_name: variant?.name ?? (variant ? money(variant.price_minor) : null),
        modifier_names: modifierOptions.map((option) => option.name),
        quantity: 1,
        price_minor: unitPrice,
      }];
    });
  }

  function safelyAddItem(item: MenuItem) {
    try {
      addItem(item);
    } catch (error) {
      setSelectionError(error instanceof Error ? error.message : "Complete the required choices before adding this item.");
    }
  }

  function changeQuantity(key: string, change: number) {
    setCart((current) => current
      .map((line) => line.key === key ? { ...line, quantity: line.quantity + change } : line)
      .filter((line) => line.quantity > 0));
  }

  return (
    <form action={createOrder} className="pos-layout">
      <input type="hidden" name="items_json" value={JSON.stringify(cart.map(({ menu_item_id, menu_item_variant_id, modifier_option_ids, quantity }) => ({ menu_item_id, menu_item_variant_id, modifier_option_ids, quantity })))} />
      <input type="hidden" name="channel" value={channel} />
      <section className="pos-catalog">
        <div className="pos-order-types" role="group" aria-label="Order channel">
          {channelOptions.map((option) => (
            <button className={channel === option ? "is-active" : ""} type="button" onClick={() => setChannel(option)} key={option}>{CHANNEL_LABELS[option]}</button>
          ))}
        </div>
        <div className="pos-tools">
          <input aria-label="Search menu" placeholder="Search the menu…" value={search} onChange={(event) => setSearch(event.target.value)} />
          <div className="pos-categories">{categories.map((name) => <button type="button" className={category === name ? "is-active" : ""} onClick={() => setCategory(name)} key={name}>{name}</button>)}</div>
        </div>
        {selectionError ? <div className="ops-alert is-error" role="alert">{selectionError}</div> : null}
        <div className="pos-items">
          {filtered.length ? filtered.map((item) => {
            const variants = activeVariants(item);
            const currentVariant = selectedVariant(item);
            return (
              <article className={`pos-item${!item.is_available ? " is-disabled" : ""}`} key={item.id}>
                <span>{item.station}</span><strong>{item.name}</strong><small>{item.description || "Ready to add"}</small>
                {variants.length ? <div className="pos-variant-options" role="group" aria-label={`${item.name} size or portion`}>
                  {variants.map((variant) => <button type="button" className={currentVariant?.id === variant.id ? "is-active" : ""} onClick={() => setVariantSelections((current) => ({ ...current, [item.id]: variant.id }))} disabled={!item.is_available} key={variant.id}>{variant.name ?? "Option"}<b>{money(variant.price_minor)}</b></button>)}
                </div> : <b className="pos-base-price">{item.is_price_from ? "From " : ""}{money(item.price_minor)}</b>}
                {item.modifier_groups.length ? <details className="pos-modifiers">
                  <summary>Customize {item.modifier_groups.some((group) => group.is_required) ? "· choices required" : "· optional"}</summary>
                  {item.modifier_groups.map((group) => {
                    const available = group.options.filter((option) => option.is_active && option.is_available);
                    const selected = selectedOptions(item, group);
                    return <fieldset key={group.id}><legend>{group.name}{group.is_required ? " *" : ""}</legend>
                      {group.selection_type === "SINGLE" ? <select aria-label={`${item.name}: ${group.name}`} value={selected[0] ?? ""} onChange={(event) => setSingleModifier(item, group, event.target.value)} disabled={!item.is_available}>
                        {!group.is_required ? <option value="">No selection</option> : null}
                        {available.map((option) => <option value={option.id} key={option.id}>{option.name}{option.price_delta_minor ? ` (+${money(option.price_delta_minor)})` : ""}</option>)}
                      </select> : <div className="pos-modifier-checks">{available.map((option) => <label key={option.id}><input type="checkbox" checked={selected.includes(option.id)} onChange={() => toggleMultipleModifier(item, group, option.id)} disabled={!item.is_available || (!selected.includes(option.id) && selected.length >= group.max_selections)} /><span>{option.name}</span>{option.price_delta_minor ? <b>+{money(option.price_delta_minor)}</b> : null}</label>)}</div>}
                    </fieldset>;
                  })}
                </details> : null}
                <button className="pos-add-item" type="button" onClick={() => safelyAddItem(item)} disabled={!item.is_available}>{item.is_available ? "Add to order" : "Sold out"}</button>
              </article>
            );
          }) : <div className="ops-empty is-wide"><strong>No menu items match</strong><p>Add menu items or change the current filter.</p></div>}
        </div>
      </section>

      <aside className="pos-cart">
        <div className="pos-cart-head"><div><p className="ops-kicker">Current order</p><h2>{CHANNEL_LABELS[channel]}</h2></div><span>{cart.reduce((sum, line) => sum + line.quantity, 0)} items</span></div>
        <div className="pos-customer-fields">
          <label>Saved customer<select name="customer_id" value={customerId} onChange={(event) => setCustomerId(event.target.value)}><option value="">Not a saved customer</option>{customers.map((customer) => <option value={customer.id} key={customer.id}>{customer.label}</option>)}</select></label>
          {channel === "DINE_IN" ? <label>Table<select name="table_id" required defaultValue=""><option value="" disabled>Choose a table</option>{tables.map((table) => <option value={table.id} key={table.id}>{table.label}</option>)}</select></label> : null}
          {!customerId && channel !== "DINE_IN" ? (
            <>
              <label>Guest name<input name="guest_name" placeholder="Who is this order for?" /></label>
              <label>Guest phone<input name="guest_phone" type="tel" placeholder="024 000 0000" /></label>
            </>
          ) : null}
          {channel === "DELIVERY" ? <label className="pos-full">Delivery address<textarea name="delivery_address" rows={2} required placeholder="House number, street, landmark…" /></label> : null}
        </div>
        <div className="pos-cart-lines">
          {cart.length ? cart.map((line) => (
            <div className="pos-cart-line" key={line.key}><div><strong>{line.name}{line.variant_name ? ` · ${line.variant_name}` : ""}</strong>{line.modifier_names.length ? <small>{line.modifier_names.join(" · ")}</small> : null}<small>{money(line.price_minor)} each</small></div><div className="pos-quantity"><button type="button" aria-label={`Remove one ${line.name}`} onClick={() => changeQuantity(line.key, -1)}>−</button><span>{line.quantity}</span><button type="button" aria-label={`Add one ${line.name}`} onClick={() => changeQuantity(line.key, 1)}>＋</button></div><b>{money(line.price_minor * line.quantity)}</b></div>
          )) : <div className="ops-empty"><strong>Your order is empty</strong><p>Choose an available menu item to begin.</p></div>}
        </div>
        <label className="pos-note">Order note<textarea name="notes" placeholder="Allergies, preparation note, delivery detail…" rows={2} /></label>
        <div className="pos-total"><span>Total</span><strong>{money(total)}</strong></div>
        <FormSubmitButton pendingText="Sending order…">Send to kitchen</FormSubmitButton>
      </aside>
    </form>
  );
}
