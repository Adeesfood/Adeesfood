# Adee's Food Supabase Backend

This directory is the version-controlled source of truth for the Adee's Food
backend. Do not recreate the schema manually in the Supabase dashboard.

## Current implementation slice

Phase 1A currently includes:

- organization and location scope;
- Supabase Auth-linked staff profiles and employment records;
- the three approved roles: Receptionist, Manager, and Owner;
- a normalized permission catalog and role mappings;
- location-scoped role assignments;
- default-deny RLS on every exposed foundation table;
- approval-policy and approval-request foundations;
- append-only audit events;
- private idempotency and outbox infrastructure for later transactional commands;
- staff-only signup configuration, stronger local password policy, and TOTP support;
- pgTAP schema, permission, RLS, revocation, MFA, idempotency, and outbox tests.

It does **not** yet create restaurant-specific users, an organization, a
location, menu data, orders, payments, KDS tickets, or inventory data.

## Local development

Requirements: Node.js 22+, Docker/Colima, and the project dependencies.

```bash
npm run db:start
npm run db:reset
npm run db:test
npm run db:lint
```

`db:reset` is destructive only to the local Supabase database. It applies all
migrations in order and then runs `seed.sql`. The seed intentionally contains
no invented restaurant, user, menu, price, or financial data.

## Hosted Supabase deployment

Use a dedicated Adee's Food Supabase project. Do not reuse any project owned by
another business.

After local tests pass:

```bash
npx supabase login
npx supabase link --project-ref YOUR_ADEES_PROJECT_REF
npx supabase db push --dry-run
npx supabase db push
```

Review the dry run before applying. Never run `db reset --linked` against
production and never use `--include-seed` for production.

Authentication users should be invited/provisioned deliberately. New Auth
users receive an inactive profile and no access until an employment and scoped
role assignment are created through an owner-authorized administration flow.

## Migration policy

- Add forward-only timestamped migrations; do not edit a migration after it has
  reached a shared hosted environment.
- Run reset, tests, and lint before every push.
- Keep the `private` schema out of Supabase API exposed schemas.
- Never grant browser clients direct mutation rights to ledgers or security
  tables. Later business writes must use reviewed transactional commands.
- Store hosted secrets in Supabase/Vercel secret management, never in this
  repository or chat.
