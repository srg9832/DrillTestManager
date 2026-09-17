# CAP Drill Test Manager — Production Build

This is the production GitHub Pages / Supabase version of the CAP Drill Test Manager prototype.

It is designed to extend the **same Supabase project** already used by CAP Schedule and CAP Leadership Feedback. It reuses the shared authentication, unit, member, and CAPID foundation rather than creating a separate member database.

Start with **DEPLOYMENT_INSTRUCTIONS.md**.

## Package contents

```text
CAP-Drill-Test-Production/
├── index.html
├── styles.css
├── app.js
├── config.js
├── manifest.json
├── service-worker.js
├── .nojekyll
├── assets/
│   └── icon.svg
├── supabase/
│   ├── PRE_INSTALL_CHECK.sql
│   ├── VERIFY_AFTER_INSTALL.sql
│   ├── ROLLBACK_DRILL_ONLY.sql
│   ├── migrations/
│   │   └── 20260916_cap_drill_test_manager.sql
│   └── functions/
│       └── drill-admin-users/
│           └── index.ts
├── DEPLOYMENT_INSTRUCTIONS.md
├── DATABASE_DESIGN.md
└── QA_CHECKLIST.md
```

## Shared CAP data reused

- `auth.users`
- `public.profiles`
- `public.units`
- `public.members`
- `public.member_unit_assignments`
- `profiles.member_id`

The migration is additive. It does **not** delete or replace CAP Schedule or Leadership Feedback tables.

## Drill-specific security

Drill permissions are independent from Schedule and Leadership permissions. Supabase Row Level Security and security-definer RPCs are the security boundary; hidden buttons in the browser are not relied upon for authorization.

The browser receives only the public/anon/publishable key. Never put the Supabase service-role key in `config.js` or GitHub.

## Important deployment order

1. Run `supabase/PRE_INSTALL_CHECK.sql`.
2. Run `supabase/migrations/20260916_cap_drill_test_manager.sql`.
3. Run `supabase/VERIFY_AFTER_INSTALL.sql`.
4. Deploy the `drill-admin-users` Edge Function.
5. Put your existing Supabase public key in `config.js`.
6. Test locally over HTTP.
7. Upload the site to GitHub and enable GitHub Pages.
8. Add the new GitHub Pages URL to Supabase Auth redirect URLs.
9. Sign in with your existing CAP Schedule / Leadership Feedback account.
10. Complete `QA_CHECKLIST.md`.
