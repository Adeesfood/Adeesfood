-- Adee's Food initial role and permission catalog.
-- Thresholds and dual-approval rules are configured separately per restaurant.

begin;

insert into public.roles (id, code, name, description, risk_level, is_system)
values
  (
    '00000000-0000-4000-8000-000000000101',
    'RECEPTIONIST',
    'Receptionist',
    'Front-of-house orders, payments, tables, reservations, and customer service.',
    'MEDIUM',
    true
  ),
  (
    '00000000-0000-4000-8000-000000000102',
    'MANAGER',
    'Manager',
    'Day-to-day restaurant operations and bounded approvals.',
    'HIGH',
    true
  ),
  (
    '00000000-0000-4000-8000-000000000103',
    'OWNER',
    'Owner',
    'Organization-wide governance, finance, security, and high-risk approvals.',
    'CRITICAL',
    true
  );

insert into public.permissions (code, module, description, risk_level)
values
  ('dashboard.view_operational', 'dashboard', 'View the assigned location operational dashboard.', 'LOW'),

  ('orders.view', 'orders', 'View orders in the assigned scope.', 'LOW'),
  ('orders.create', 'orders', 'Create a draft order.', 'MEDIUM'),
  ('orders.update_draft', 'orders', 'Edit an eligible draft order.', 'MEDIUM'),
  ('orders.submit', 'orders', 'Confirm a commercial order.', 'HIGH'),
  ('orders.send_kitchen', 'orders', 'Send eligible order quantities to the kitchen.', 'HIGH'),
  ('orders.add_after_send', 'orders', 'Add a follow-up line after kitchen send.', 'HIGH'),
  ('orders.cancel_unstarted', 'orders', 'Cancel an eligible unstarted order or line.', 'HIGH'),
  ('orders.void_posted', 'orders', 'Void a posted commercial order through a reversal.', 'CRITICAL'),
  ('orders.reopen_completed', 'orders', 'Exceptionally reopen a completed order.', 'CRITICAL'),
  ('orders.transfer_table', 'orders', 'Transfer an open dine-in order to another table.', 'MEDIUM'),
  ('orders.merge_split', 'orders', 'Merge or split eligible orders and checks.', 'HIGH'),

  ('discounts.apply_standard', 'discounts', 'Apply an active configured discount.', 'MEDIUM'),
  ('discounts.apply_manual', 'discounts', 'Apply a manual discount within policy.', 'HIGH'),
  ('discounts.approve', 'discounts', 'Approve a discount request within policy.', 'HIGH'),
  ('receipts.print_or_send', 'receipts', 'Print, download, or send an order receipt.', 'LOW'),

  ('payments.view_order', 'payments', 'View settlement details needed for an order.', 'MEDIUM'),
  ('payments.record', 'payments', 'Record a payment through a configured method.', 'CRITICAL'),
  ('payments.split_tender', 'payments', 'Allocate an order across multiple payment methods.', 'HIGH'),
  ('payments.correct_unsettled', 'payments', 'Correct an unsettled payment attempt.', 'CRITICAL'),
  ('refunds.request', 'refunds', 'Request an eligible customer refund.', 'HIGH'),
  ('refunds.approve', 'refunds', 'Approve a refund within policy.', 'CRITICAL'),
  ('refunds.process', 'refunds', 'Process an approved refund.', 'CRITICAL'),

  ('cash_sessions.open_own', 'cash', 'Open an assigned cash-register session.', 'HIGH'),
  ('cash_sessions.declare_close_own', 'cash', 'Declare actual cash for an assigned session.', 'HIGH'),
  ('cash_movements.record', 'cash', 'Record an authorized paid-in, paid-out, or safe drop.', 'CRITICAL'),
  ('cash_variance.approve', 'cash', 'Approve a cash variance within policy.', 'CRITICAL'),

  ('kitchen.view_status', 'kitchen', 'View kitchen status for assigned orders or stations.', 'LOW'),
  ('kitchen.start_ticket', 'kitchen', 'Start an assigned kitchen ticket.', 'HIGH'),
  ('kitchen.ready_ticket', 'kitchen', 'Mark an assigned kitchen ticket ready.', 'HIGH'),
  ('kitchen.recall_ticket', 'kitchen', 'Recall or re-fire a kitchen ticket with reason.', 'HIGH'),
  ('kitchen.reroute_ticket', 'kitchen', 'Reroute a ticket between stations.', 'HIGH'),

  ('tables.view', 'tables', 'View table availability and sessions.', 'LOW'),
  ('tables.open_session', 'tables', 'Open a table session.', 'MEDIUM'),
  ('tables.change_status', 'tables', 'Change an eligible restaurant table status.', 'MEDIUM'),
  ('tables.close_session', 'tables', 'Close an eligible table session.', 'HIGH'),

  ('reservations.view', 'reservations', 'View reservations in the assigned location.', 'LOW'),
  ('reservations.create_update', 'reservations', 'Create or update an eligible reservation.', 'MEDIUM'),
  ('reservations.cancel_no_show', 'reservations', 'Cancel or mark a reservation no-show.', 'MEDIUM'),
  ('reservations.override_conflict', 'reservations', 'Override a reservation conflict with reason.', 'HIGH'),

  ('customers.lookup', 'customers', 'Search limited customer details.', 'MEDIUM'),
  ('customers.create_update_basic', 'customers', 'Create or update basic customer details.', 'MEDIUM'),
  ('customers.export', 'customers', 'Export customer information for an approved purpose.', 'CRITICAL'),
  ('customers.merge', 'customers', 'Merge verified duplicate customer records.', 'HIGH'),
  ('customers.delete_or_anonymize', 'customers', 'Delete or anonymize customer data under policy.', 'CRITICAL'),

  ('menu.view_internal', 'menu', 'View current internal menu and availability.', 'LOW'),
  ('menu.toggle_availability', 'menu', 'Temporarily change menu availability.', 'MEDIUM'),
  ('menu.manage_catalog', 'menu', 'Manage menu categories, items, variants, and modifiers.', 'HIGH'),
  ('menu.manage_prices_tax', 'menu', 'Manage effective prices and tax mappings.', 'CRITICAL'),
  ('menu.manage_modifiers_routing', 'menu', 'Manage modifier rules and kitchen routing.', 'HIGH'),

  ('inventory.view_on_hand', 'inventory', 'View stock balances for assigned locations.', 'MEDIUM'),
  ('inventory.view_cost', 'inventory', 'View inventory cost and valuation.', 'HIGH'),
  ('inventory.count_enter', 'inventory', 'Enter physical stock counts.', 'HIGH'),
  ('inventory.count_approve_post', 'inventory', 'Approve and post a stock-count variance.', 'CRITICAL'),
  ('inventory.adjust', 'inventory', 'Post an exceptional inventory adjustment.', 'CRITICAL'),
  ('inventory.record_wastage', 'inventory', 'Record and post stock wastage.', 'HIGH'),
  ('inventory.transfer', 'inventory', 'Transfer stock between authorized storage locations.', 'HIGH'),
  ('inventory.manage_items_units', 'inventory', 'Manage inventory items and unit conversions.', 'CRITICAL'),

  ('recipes.view', 'recipes', 'View recipe composition in the assigned scope.', 'MEDIUM'),
  ('recipes.create_draft', 'recipes', 'Create and edit a draft recipe version.', 'HIGH'),
  ('recipes.publish_version', 'recipes', 'Publish an immutable recipe version.', 'CRITICAL'),
  ('recipes.view_margin', 'recipes', 'View recipe cost and menu margin.', 'HIGH'),

  ('suppliers.view', 'suppliers', 'View supplier records in the organization.', 'MEDIUM'),
  ('suppliers.manage', 'suppliers', 'Manage supplier identity and commercial details.', 'CRITICAL'),
  ('purchase_requests.create', 'purchasing', 'Create a purchase request.', 'HIGH'),
  ('purchase_requests.approve', 'purchasing', 'Approve a purchase request within policy.', 'CRITICAL'),
  ('purchase_orders.create_issue', 'purchasing', 'Create, approve, and issue an eligible purchase order.', 'CRITICAL'),
  ('goods_receipts.record', 'purchasing', 'Record and post accepted supplier goods.', 'CRITICAL'),
  ('goods_receipts.post_override', 'purchasing', 'Override a goods-receipt tolerance.', 'CRITICAL'),
  ('supplier_invoices.record', 'purchasing', 'Record a supplier invoice and matching detail.', 'HIGH'),
  ('supplier_invoices.approve', 'purchasing', 'Approve a supplier invoice or match exception.', 'CRITICAL'),
  ('supplier_payments.request', 'purchasing', 'Request a supplier payment.', 'CRITICAL'),
  ('supplier_payments.approve_process', 'purchasing', 'Approve and process a supplier payment.', 'CRITICAL'),

  ('staff.view', 'staff', 'View staff profiles and access scope required for operations.', 'HIGH'),
  ('staff.view_schedule', 'staff', 'View permitted staff schedule information.', 'MEDIUM'),
  ('staff.manage_shifts_attendance', 'staff', 'Manage shifts and attendance corrections.', 'HIGH'),
  ('staff.manage_employment', 'staff', 'Manage staff employment status and details.', 'CRITICAL'),

  ('expenses.create', 'expenses', 'Create an operational expense.', 'HIGH'),
  ('expenses.approve_post', 'expenses', 'Approve and post an operational expense.', 'CRITICAL'),
  ('daily_close.prepare', 'finance', 'Prepare a location daily close.', 'HIGH'),
  ('daily_close.post', 'finance', 'Post a daily close within policy.', 'CRITICAL'),
  ('daily_close.reopen', 'finance', 'Reopen a closed business day.', 'CRITICAL'),
  ('periods.lock_reopen', 'finance', 'Lock or reopen a financial period.', 'CRITICAL'),

  ('reports.view_own_shift', 'reports', 'View the authenticated staff member''s shift summary.', 'LOW'),
  ('reports.view_operational', 'reports', 'View assigned location operational reports.', 'MEDIUM'),
  ('reports.view_financial', 'reports', 'View permitted financial reports.', 'CRITICAL'),
  ('reports.export', 'reports', 'Export permitted report data.', 'CRITICAL'),

  ('approvals.view', 'approvals', 'View approval requests within assigned authority.', 'HIGH'),
  ('approvals.decide', 'approvals', 'Approve or reject a request within policy.', 'CRITICAL'),
  ('audit.view_location', 'audit', 'View operational audit events for assigned locations.', 'HIGH'),
  ('audit.view_all', 'audit', 'View organization-wide audit events.', 'CRITICAL'),
  ('security.manage_users_roles', 'security', 'Manage staff activation, role assignments, and permissions.', 'CRITICAL'),
  ('settings.manage_location', 'settings', 'Manage permitted location operating settings.', 'HIGH'),
  ('settings.manage_financial_security', 'settings', 'Manage finance, tax, payment, approval, and security settings.', 'CRITICAL');

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = any (array[
  'dashboard.view_operational',
  'orders.view',
  'orders.create',
  'orders.update_draft',
  'orders.submit',
  'orders.send_kitchen',
  'orders.add_after_send',
  'orders.cancel_unstarted',
  'orders.transfer_table',
  'orders.merge_split',
  'discounts.apply_standard',
  'receipts.print_or_send',
  'payments.view_order',
  'payments.record',
  'payments.split_tender',
  'payments.correct_unsettled',
  'refunds.request',
  'cash_sessions.open_own',
  'cash_sessions.declare_close_own',
  'cash_movements.record',
  'kitchen.view_status',
  'tables.view',
  'tables.open_session',
  'tables.change_status',
  'tables.close_session',
  'reservations.view',
  'reservations.create_update',
  'reservations.cancel_no_show',
  'customers.lookup',
  'customers.create_update_basic',
  'menu.view_internal',
  'menu.toggle_availability',
  'reports.view_own_shift'
])
where r.code = 'RECEPTIONIST';

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = any (array[
  'dashboard.view_operational',
  'orders.view',
  'orders.create',
  'orders.update_draft',
  'orders.submit',
  'orders.send_kitchen',
  'orders.add_after_send',
  'orders.cancel_unstarted',
  'orders.void_posted',
  'orders.transfer_table',
  'orders.merge_split',
  'discounts.apply_standard',
  'discounts.apply_manual',
  'discounts.approve',
  'receipts.print_or_send',
  'payments.view_order',
  'payments.record',
  'payments.split_tender',
  'payments.correct_unsettled',
  'refunds.request',
  'refunds.approve',
  'refunds.process',
  'cash_sessions.open_own',
  'cash_sessions.declare_close_own',
  'cash_movements.record',
  'cash_variance.approve',
  'kitchen.view_status',
  'kitchen.start_ticket',
  'kitchen.ready_ticket',
  'kitchen.recall_ticket',
  'kitchen.reroute_ticket',
  'tables.view',
  'tables.open_session',
  'tables.change_status',
  'tables.close_session',
  'reservations.view',
  'reservations.create_update',
  'reservations.cancel_no_show',
  'reservations.override_conflict',
  'customers.lookup',
  'customers.create_update_basic',
  'customers.merge',
  'menu.view_internal',
  'menu.toggle_availability',
  'menu.manage_catalog',
  'menu.manage_prices_tax',
  'menu.manage_modifiers_routing',
  'inventory.view_on_hand',
  'inventory.view_cost',
  'inventory.count_enter',
  'inventory.count_approve_post',
  'inventory.adjust',
  'inventory.record_wastage',
  'inventory.transfer',
  'inventory.manage_items_units',
  'recipes.view',
  'recipes.create_draft',
  'recipes.publish_version',
  'recipes.view_margin',
  'suppliers.view',
  'suppliers.manage',
  'purchase_requests.create',
  'purchase_requests.approve',
  'purchase_orders.create_issue',
  'goods_receipts.record',
  'goods_receipts.post_override',
  'supplier_invoices.record',
  'supplier_invoices.approve',
  'supplier_payments.request',
  'staff.view',
  'staff.view_schedule',
  'staff.manage_shifts_attendance',
  'staff.manage_employment',
  'expenses.create',
  'expenses.approve_post',
  'daily_close.prepare',
  'daily_close.post',
  'reports.view_own_shift',
  'reports.view_operational',
  'reports.view_financial',
  'reports.export',
  'approvals.view',
  'approvals.decide',
  'audit.view_location',
  'settings.manage_location'
])
where r.code = 'MANAGER';

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.code = 'OWNER';

create trigger roles_audit_changes
after insert or update or delete on public.roles
for each row execute function private.audit_row_change();

create trigger permissions_audit_changes
after insert or update or delete on public.permissions
for each row execute function private.audit_row_change();

create trigger role_permissions_audit_changes
after insert or update or delete on public.role_permissions
for each row execute function private.audit_row_change();

comment on table public.roles is
  'System roles. Authorization checks use permission codes rather than role-name conditionals.';
comment on table public.permissions is
  'Immutable capability catalog used by server commands and database RLS.';

commit;
