"use client";

import Link from "next/link";
import { useActionState, useDeferredValue, useMemo, useState } from "react";
import { submitOnlineOrder } from "@/app/menu/actions";
import {
  formatGhs,
  initialOnlineOrderState,
  type PublicMenu,
  type PublicMenuItem,
  type PublicMenuVariant,
  type PublicModifierGroup,
  type PublicModifierOption,
} from "@/lib/public-menu";

type CartLine = {
  key: string;
  menu_item_id: string;
  menu_item_variant_id: string | null;
  modifier_option_ids: string[];
  name: string;
  variantName: string | null;
  modifierNames: string[];
  quantity: number;
  unitPriceMinor: number;
};

function availableVariants(item: PublicMenuItem) {
  return item.variants;
}

function preferredVariant(item: PublicMenuItem, selectedId?: string): PublicMenuVariant | null {
  const variants = availableVariants(item);
  return variants.find((variant) => variant.id === selectedId)
    ?? variants.find((variant) => variant.is_default)
    ?? variants[0]
    ?? null;
}

function MenuChoiceGroup({
  item,
  group,
  selected,
  onSingle,
  onMultiple,
}: {
  item: PublicMenuItem;
  group: PublicModifierGroup;
  selected: string[];
  onSingle: (optionId: string) => void;
  onMultiple: (optionId: string) => void;
}) {
  return (
    <fieldset className="online-choice-group">
      <legend>
        {group.name}
        <small>
          {group.is_required ? "Required" : "Optional"} · {group.max_selections === 1 ? "Choose one" : `Choose up to ${group.max_selections}`}
        </small>
      </legend>
      {group.selection_type === "SINGLE" ? (
        <select
          aria-label={`${item.name}: ${group.name}`}
          value={selected[0] ?? ""}
          onChange={(event) => onSingle(event.target.value)}
        >
          {!group.is_required ? <option value="">No selection</option> : null}
          {group.options.map((option) => (
            <option value={option.id} key={option.id}>
              {option.name}{option.price_delta_minor ? ` (+${formatGhs(option.price_delta_minor)})` : ""}
            </option>
          ))}
        </select>
      ) : (
        <div className="online-check-list">
          {group.options.map((option) => {
            const checked = selected.includes(option.id);
            const atLimit = !checked && selected.length >= group.max_selections;
            return (
              <label key={option.id}>
                <input
                  type="checkbox"
                  checked={checked}
                  disabled={atLimit}
                  onChange={() => onMultiple(option.id)}
                />
                <span>{option.name}</span>
                {option.price_delta_minor ? <b>+{formatGhs(option.price_delta_minor)}</b> : null}
              </label>
            );
          })}
        </div>
      )}
    </fieldset>
  );
}

export function PublicOrderMenu({ menu, sourceReference }: { menu: PublicMenu; sourceReference: string }) {
  const [category, setCategory] = useState("All");
  const [search, setSearch] = useState("");
  const deferredSearch = useDeferredValue(search.trim().toLowerCase());
  const [channel, setChannel] = useState<"TAKEAWAY" | "DELIVERY">("TAKEAWAY");
  const [cart, setCart] = useState<CartLine[]>([]);
  const [variantSelections, setVariantSelections] = useState<Record<string, string>>({});
  const [modifierSelections, setModifierSelections] = useState<Record<string, string[]>>({});
  const [selectionError, setSelectionError] = useState<string | null>(null);
  const [orderState, formAction, isSubmitting] = useActionState(submitOnlineOrder, initialOnlineOrderState);

  const catalog = useMemo(() => {
    const itemMap = new Map<string, PublicMenuItem>();
    const categoryMap = new Map<string, Set<string>>();
    for (const menuCategory of menu.categories) {
      for (const item of menuCategory.items) {
        itemMap.set(item.id, item);
        const memberships = categoryMap.get(item.id) ?? new Set<string>();
        memberships.add(menuCategory.name);
        categoryMap.set(item.id, memberships);
      }
    }
    return { items: Array.from(itemMap.values()), categoryMap };
  }, [menu.categories]);

  const visibleItems = useMemo(() => catalog.items.filter((item) => {
    const matchesCategory = category === "All" || catalog.categoryMap.get(item.id)?.has(category);
    const matchesSearch = !deferredSearch || `${item.name} ${item.description ?? ""}`.toLowerCase().includes(deferredSearch);
    return matchesCategory && matchesSearch;
  }), [catalog, category, deferredSearch]);

  const itemCount = cart.reduce((sum, line) => sum + line.quantity, 0);
  const totalMinor = cart.reduce((sum, line) => sum + line.unitPriceMinor * line.quantity, 0);

  function selectedOptions(item: PublicMenuItem, group: PublicModifierGroup) {
    const stored = modifierSelections[`${item.id}:${group.id}`];
    if (stored) return stored.filter((id) => group.options.some((option) => option.id === id));
    if (group.selection_type === "SINGLE" && group.min_selections > 0 && group.options[0]) return [group.options[0].id];
    return [];
  }

  function setSingleModifier(itemId: string, groupId: string, optionId: string) {
    setModifierSelections((current) => ({ ...current, [`${itemId}:${groupId}`]: optionId ? [optionId] : [] }));
  }

  function toggleMultipleModifier(item: PublicMenuItem, group: PublicModifierGroup, optionId: string) {
    const key = `${item.id}:${group.id}`;
    setModifierSelections((current) => {
      const selected = current[key] ?? [];
      if (selected.includes(optionId)) return { ...current, [key]: selected.filter((id) => id !== optionId) };
      if (selected.length >= group.max_selections) return current;
      return { ...current, [key]: [...selected, optionId] };
    });
  }

  function addItem(item: PublicMenuItem) {
    const variant = preferredVariant(item, variantSelections[item.id]);
    if (item.variants.length && !variant) {
      setSelectionError(`Choose an available size for ${item.name}.`);
      return;
    }

    const selectedModifiers: PublicModifierOption[] = [];
    for (const group of item.modifier_groups) {
      const ids = selectedOptions(item, group);
      if (ids.length < group.min_selections || ids.length > group.max_selections) {
        const count = group.min_selections === group.max_selections
          ? String(group.min_selections)
          : `${group.min_selections}–${group.max_selections}`;
        setSelectionError(`${item.name}: ${group.name} requires ${count} choice${group.max_selections === 1 ? "" : "s"}.`);
        return;
      }
      selectedModifiers.push(...group.options.filter((option) => ids.includes(option.id)));
    }

    const modifierIds = selectedModifiers.map((option) => option.id).sort();
    const key = `${item.id}:${variant?.id ?? "base"}:${modifierIds.join(",")}`;
    const unitPriceMinor = (variant?.price_minor ?? item.price_minor)
      + selectedModifiers.reduce((sum, option) => sum + option.price_delta_minor, 0);
    setSelectionError(null);
    setCart((current) => {
      const existing = current.find((line) => line.key === key);
      if (existing) {
        return current.map((line) => line.key === key
          ? { ...line, quantity: Math.min(line.quantity + 1, 20) }
          : line);
      }
      return [...current, {
        key,
        menu_item_id: item.id,
        menu_item_variant_id: variant?.id ?? null,
        modifier_option_ids: modifierIds,
        name: item.name,
        variantName: variant?.name ?? null,
        modifierNames: selectedModifiers.map((option) => option.name),
        quantity: 1,
        unitPriceMinor,
      }];
    });
  }

  function changeQuantity(key: string, change: number) {
    setCart((current) => current
      .map((line) => line.key === key ? { ...line, quantity: Math.min(line.quantity + change, 20) } : line)
      .filter((line) => line.quantity > 0));
  }

  if (orderState.status === "success") {
    return (
      <main className="order-success-page">
        <section className="order-success-card" aria-labelledby="order-success-title">
          <span className="order-success-mark" aria-hidden="true">✓</span>
          <p className="menu-kicker">Order received</p>
          <h1 id="order-success-title">Thank you, your order is in.</h1>
          <p>{orderState.message}</p>
          <dl>
            <div><dt>Order number</dt><dd>{orderState.orderNumber}</dd></div>
            <div><dt>Total</dt><dd>{formatGhs(orderState.totalMinor ?? 0)}</dd></div>
            <div><dt>Payment</dt><dd>Pay at {channel === "DELIVERY" ? "delivery" : "pickup"}</dd></div>
          </dl>
          <p className="order-success-note">Keep your order number. Adee&apos;s Food staff can now see this order in the management system.</p>
          <div className="order-success-actions">
            <a href="/menu">Place another order</a>
            <Link href="/">Return home</Link>
          </div>
        </section>
      </main>
    );
  }

  return (
    <form action={formAction} className="online-order-form">
      <input type="hidden" name="location_id" value={menu.location_id} />
      <input type="hidden" name="source_reference" value={sourceReference} />
      <input type="hidden" name="channel" value={channel} />
      <input
        type="hidden"
        name="items_json"
        value={JSON.stringify(cart.map(({ menu_item_id, menu_item_variant_id, modifier_option_ids, quantity }) => ({
          menu_item_id,
          menu_item_variant_id,
          modifier_option_ids,
          quantity,
        })))}
      />

      <section className="online-catalog" aria-labelledby="menu-title">
        <div className="online-menu-intro">
          <p className="menu-kicker">Order from {menu.location_name}</p>
          <h1 id="menu-title">Choose your <em>craving.</em></h1>
          <p>Build your order from the same live menu used by our kitchen. Prices and availability are confirmed when you submit.</p>
        </div>

        <div className="online-menu-tools">
          <label className="menu-search">
            <span>Search the menu</span>
            <input
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Try chicken, pizza, drinks…"
            />
          </label>
          <div className="online-categories" role="group" aria-label="Menu category">
            {["All", ...menu.categories.map((menuCategory) => menuCategory.name)].map((name) => (
              <button
                type="button"
                aria-pressed={category === name}
                className={category === name ? "is-active" : ""}
                onClick={() => setCategory(name)}
                key={name}
              >
                {name}
              </button>
            ))}
          </div>
        </div>

        {selectionError ? <div className="menu-alert" role="alert">{selectionError}</div> : null}
        <div className="online-items" aria-live="polite">
          {visibleItems.map((item, index) => {
            const variant = preferredVariant(item, variantSelections[item.id]);
            const memberships = Array.from(catalog.categoryMap.get(item.id) ?? []);
            return (
              <article className="online-item" key={item.id}>
                <div className="online-item-number" aria-hidden="true">{String(index + 1).padStart(2, "0")}</div>
                <div className="online-item-heading">
                  <div>
                    <span>{memberships.join(" · ")}</span>
                    <h2>{item.name}</h2>
                  </div>
                  <strong>{item.is_price_from ? "From " : ""}{formatGhs(variant?.price_minor ?? item.price_minor)}</strong>
                </div>
                <p>{item.description || "Prepared fresh by Adee's Food."}</p>

                {item.variants.length ? (
                  <div className="online-variants" role="group" aria-label={`${item.name} size or portion`}>
                    {item.variants.map((itemVariant) => (
                      <button
                        type="button"
                        className={variant?.id === itemVariant.id ? "is-active" : ""}
                        aria-pressed={variant?.id === itemVariant.id}
                        onClick={() => setVariantSelections((current) => ({ ...current, [item.id]: itemVariant.id }))}
                        key={itemVariant.id}
                      >
                        <span>{itemVariant.name ?? "Option"}</span>
                        <b>{formatGhs(itemVariant.price_minor)}</b>
                      </button>
                    ))}
                  </div>
                ) : null}

                {item.modifier_groups.length ? (
                  <details className="online-customize">
                    <summary>Customize <span>{item.modifier_groups.some((group) => group.is_required) ? "choices required" : "optional"}</span></summary>
                    <div className="online-customize-body">
                      {item.modifier_groups.map((group) => (
                        <MenuChoiceGroup
                          item={item}
                          group={group}
                          selected={selectedOptions(item, group)}
                          onSingle={(optionId) => setSingleModifier(item.id, group.id, optionId)}
                          onMultiple={(optionId) => toggleMultipleModifier(item, group, optionId)}
                          key={group.id}
                        />
                      ))}
                    </div>
                  </details>
                ) : null}
                <button type="button" className="online-add" onClick={() => addItem(item)}>
                  Add to order <span aria-hidden="true">＋</span>
                </button>
              </article>
            );
          })}
          {visibleItems.length ? null : (
            <div className="online-menu-empty">
              <strong>No dishes found</strong>
              <p>Try another search or menu category.</p>
            </div>
          )}
        </div>
      </section>

      <aside className="online-cart" id="your-order" aria-labelledby="cart-title">
        <div className="online-cart-title">
          <div><p className="menu-kicker">Your order</p><h2 id="cart-title">Ready when you are.</h2></div>
          <span>{itemCount} {itemCount === 1 ? "item" : "items"}</span>
        </div>

        <div className="fulfillment-switch" role="group" aria-label="Pickup or delivery">
          <button type="button" className={channel === "TAKEAWAY" ? "is-active" : ""} aria-pressed={channel === "TAKEAWAY"} onClick={() => setChannel("TAKEAWAY")}>
            Pickup <small>Pay at pickup</small>
          </button>
          <button type="button" className={channel === "DELIVERY" ? "is-active" : ""} aria-pressed={channel === "DELIVERY"} onClick={() => setChannel("DELIVERY")}>
            Delivery <small>Pay on delivery</small>
          </button>
        </div>

        <div className="online-cart-lines">
          {cart.map((line) => (
            <div className="online-cart-line" key={line.key}>
              <div>
                <strong>{line.name}{line.variantName ? ` · ${line.variantName}` : ""}</strong>
                {line.modifierNames.length ? <small>{line.modifierNames.join(" · ")}</small> : null}
                <span>{formatGhs(line.unitPriceMinor)} each</span>
              </div>
              <div className="online-quantity">
                <button type="button" onClick={() => changeQuantity(line.key, -1)} aria-label={`Remove one ${line.name}`}>−</button>
                <span>{line.quantity}</span>
                <button type="button" onClick={() => changeQuantity(line.key, 1)} disabled={line.quantity >= 20} aria-label={`Add one ${line.name}`}>＋</button>
              </div>
              <b>{formatGhs(line.unitPriceMinor * line.quantity)}</b>
            </div>
          ))}
          {cart.length ? null : (
            <div className="online-cart-empty">
              <span aria-hidden="true">＋</span>
              <strong>Your order is empty</strong>
              <p>Choose something irresistible from the menu.</p>
            </div>
          )}
        </div>

        <div className="online-customer-fields">
          <label>Full name<input name="guest_name" autoComplete="name" maxLength={120} required /></label>
          <label>Phone number<input name="guest_phone" type="tel" inputMode="tel" autoComplete="tel" maxLength={30} placeholder="e.g. 024 000 0000" required /></label>
          <label>Email <small>Optional</small><input name="guest_email" type="email" autoComplete="email" maxLength={254} /></label>
          {channel === "DELIVERY" ? (
            <label>Delivery address<textarea name="delivery_address" autoComplete="street-address" maxLength={500} rows={3} required /></label>
          ) : null}
          <label>Order note <small>Optional</small><textarea name="notes" maxLength={500} rows={3} placeholder="Allergies or preparation notes…" /></label>
        </div>

        {orderState.status === "error" ? <div className="menu-alert is-error" role="alert">{orderState.message}</div> : null}
        <div className="online-cart-total"><span>Total</span><strong>{formatGhs(totalMinor)}</strong></div>
        <button type="submit" className="online-checkout" disabled={!cart.length || isSubmitting}>
          {isSubmitting ? "Sending your order…" : "Place order"}<span aria-hidden="true">→</span>
        </button>
        <p className="online-payment-note">No online payment is taken. Pay at {channel === "DELIVERY" ? "delivery" : "pickup"} after the restaurant confirms your order.</p>
      </aside>

      {cart.length ? <a className="mobile-cart-jump" href="#your-order">View order · {itemCount} · {formatGhs(totalMinor)}</a> : null}
    </form>
  );
}
