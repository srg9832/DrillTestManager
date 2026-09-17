# CAP Drill Test Manager — Detailed Deployment Instructions

These instructions install CAP Drill Test Manager into the **existing Supabase project** already used by CAP Schedule and CAP Leadership Feedback, then deploy the website as a separate GitHub Pages/PWA site.

## Known project from our existing work

- Supabase project ref: `vosvdkkuiijywwmqzdiu`
- Supabase URL: `https://vosvdkkuiijywwmqzdiu.supabase.co`
- Suggested GitHub repository: `CAPDrillTestManager`
- Application name: **CAP Drill Test Manager**

The migration is additive. It reuses the existing shared `profiles`, `units`, `members`, and `member_unit_assignments` foundation and does not delete Schedule or Leadership Feedback data.

---

# STEP 0 — Protect the working system first

Before running any new SQL:

1. Open your existing **CAP Schedule** website and make sure it is working.
2. Open **CAP Leadership Feedback** and make sure it is working.
3. Keep an untouched copy of this ZIP.
4. If your Supabase plan gives you a database backup/snapshot option, take one now.
5. In Supabase Dashboard, verify you are working in project `vosvdkkuiijywwmqzdiu`.

The Drill migration includes a preflight check and will refuse to continue if the shared foundation is not present.

---

# STEP 1 — Run the pre-install check

Open Supabase Dashboard:

1. Select project `vosvdkkuiijywwmqzdiu`.
2. Click **SQL Editor**.
3. Click **New query**.
4. Open this local file:

   `supabase/PRE_INSTALL_CHECK.sql`

5. Copy all of it into SQL Editor.
6. Click **Run**.

The first result should show non-null values for:

- `profiles`
- `units`
- `members`
- `member_unit_assignments`
- `is_app_admin()`
- `set_updated_at()`

If any required object is `NULL`, stop here. Do not run the Drill migration until the existing Schedule/Leadership shared database is current.

The next results show your existing units and basic roster counts. Zero members would be unusual now that Leadership Feedback is installed, but it does not prevent the Drill migration itself.

---

# STEP 2 — Run the Drill database migration

Open:

`supabase/migrations/20260916_cap_drill_test_manager.sql`

Then:

1. Press **Ctrl+A** in the file.
2. Press **Ctrl+C**.
3. Go back to Supabase **SQL Editor**.
4. Create a **New query**.
5. Paste the entire migration.
6. Click **Run**.
7. Wait for a successful completion.

Do **not** deploy the website if this query returns an error.

## What the migration adds

Drill-specific tables:

- `drill_global_permissions`
- `drill_user_preferences`
- `drill_unit_permissions`
- `drill_activities`
- `drill_activity_permissions`
- `drill_test_definitions`
- `drill_test_items`
- `drill_records`
- `drill_audit_log`

It also adds:

- Drill authorization helper functions;
- secure save/admin RPCs;
- RLS policies;
- indexes for unit/activity/member/date queries;
- public signed-out drill sequence view;
- the seeded CAPP 60-34 Achievement 1–8 and Wright Brothers practical tests;
- the requested Montana units if missing, including MT-012 Malmstrom Composite.

## Initial Drill Application Administrator

At the end of the migration, current CAP Schedule users whose `profiles.is_app_admin = true` are copied into `drill_global_permissions` as Drill Application Administrators.

This is only a bootstrap so you have an administrator account immediately. Schedule App Admin and Drill App Admin are independent after installation.

---

# STEP 3 — Verify the database install

Open:

`supabase/VERIFY_AFTER_INSTALL.sql`

Paste it into a new Supabase SQL Editor query and click **Run**.

Confirm that:

1. all Drill tables are present;
2. RLS is enabled on the Drill tables;
3. Drill helper/RPC functions are present;
4. Achievement 1–8 and Wright Brothers appear;
5. their graded item counts are populated;
6. MT-008, MT-012, MT-018, MT-031, MT-037, MT-053, and MT-060 appear;
7. at least your existing Schedule App Admin appears as Drill App Admin;
8. `drill_public_sequences` returns the public sequence rows.

Do not proceed if the seeded test list is empty or your App Admin bootstrap is missing.

---

# STEP 4 — Deploy the `drill-admin-users` Edge Function

The browser must never contain the Supabase service-role key. Creating or linking Supabase Auth accounts therefore uses a Drill-specific Edge Function.

The function source is:

`supabase/functions/drill-admin-users/index.ts`

It does **not** replace the existing Schedule `admin-users` or Leadership `leadership-admin-users` functions.

## Open PowerShell in the extracted project folder

Example:

```powershell
cd "C:\Users\YOURNAME\Documents\CAP-Drill-Test-Production"
```

Verify the Edge Function file exists:

```powershell
dir .\supabase\functions\drill-admin-users\
```

You should see `index.ts`.

## Log in to the Supabase CLI

If you have already done this recently, the CLI may remember you.

```powershell
npx supabase@latest login
```

A browser may open so you can authorize the CLI.

## Link this folder to the existing project

```powershell
npx supabase@latest link --project-ref vosvdkkuiijywwmqzdiu
```

## Deploy the Drill function

```powershell
npx supabase@latest functions deploy drill-admin-users --project-ref vosvdkkuiijywwmqzdiu
```

After it completes:

1. Open **Supabase Dashboard**.
2. Open **Edge Functions**.
3. Confirm `drill-admin-users` is listed.

You do **not** manually put the service-role key into the function source. Supabase provides its server-side environment variables to the deployed function.

---

# STEP 5 — Configure `config.js`

Open:

`config.js`

It already contains:

```js
supabaseUrl: "https://vosvdkkuiijywwmqzdiu.supabase.co"
```

Replace this placeholder:

```js
supabaseAnonKey: "PASTE_YOUR_EXISTING_CAP_SCHEDULE_ANON_OR_PUBLISHABLE_KEY_HERE"
```

with the **same public/anon/publishable key** used by your working CAP Schedule or Leadership Feedback website.

You can copy it from the working `config.js` of one of those apps, or locate the project's browser/public API key in Supabase Dashboard.

The final file should look conceptually like:

```js
window.CAP_DRILL_CONFIG = {
  supabaseUrl: "https://vosvdkkuiijywwmqzdiu.supabase.co",
  supabaseAnonKey: "YOUR_EXISTING_PUBLIC_KEY",
  appName: "CAP Drill Test Manager",
  adminFunctionName: "drill-admin-users"
};
```

### Never use these in `config.js`

- service-role key
- database password
- personal access token
- GitHub token

The public key is intended for browser applications. RLS is what protects the database.

---

# STEP 6 — Test locally over HTTP

Do not double-click `index.html` for the final integration test. Serve the folder through a tiny local web server.

In PowerShell, from the project folder:

```powershell
python -m http.server 8000
```

Open:

`http://localhost:8000`

Test the public Drill Sequences list before logging in.

Then sign in with your existing CAP Schedule / Leadership Feedback account.

If Supabase blocks an auth redirect during testing, temporarily add:

`http://localhost:8000/**`

under **Authentication → URL Configuration → Redirect URLs**.

Normal email/password login usually does not require a redirect, but password-reset/invitation flows do.

---

# STEP 7 — Initial local smoke test

Before GitHub deployment, test these items locally:

1. Sign in with your existing App Admin account.
2. Confirm **New Drill Test** is the default tab.
3. Confirm the seven requested Montana units exist, including MT-012.
4. Confirm all nine drill test definitions appear in Administration.
5. Enter an existing CAPID and confirm the name populates.
6. Enter a fake/new CAPID, add first/last/home unit, and save a Draft; verify it creates the member.
7. Confirm `--` ungraded sequence commands appear inline without scoring buttons.
8. Submit a test.
9. Open Dashboard and confirm the result appears.
10. Open Reports and confirm it appears in the eServices list.
11. Open Statistics.
12. Create a small Other Activity.
13. Test Users & Permissions.

Use `QA_CHECKLIST.md` for the full test plan.

---

# STEP 8 — Create the GitHub repository

A clean repository name is:

`CAPDrillTestManager`

In GitHub:

1. Sign in.
2. Create a new repository.
3. Name it `CAPDrillTestManager`.
4. Do not add a starter website over the supplied files.
5. Upload the **contents** of `CAP-Drill-Test-Production`, not the outer folder itself.

The repository root should contain:

```text
index.html
styles.css
app.js
config.js
manifest.json
service-worker.js
.nojekyll
assets/
supabase/
README.md
DEPLOYMENT_INSTRUCTIONS.md
DATABASE_DESIGN.md
QA_CHECKLIST.md
```

Keeping `supabase/` in GitHub is useful for source control even though GitHub Pages does not use that folder at runtime.

---

# STEP 9 — Enable GitHub Pages

In the GitHub repository:

1. Open **Settings**.
2. Open **Pages**.
3. Under **Build and deployment**, choose **Deploy from a branch**.
4. Branch: `main`.
5. Folder: `/(root)`.
6. Click **Save**.
7. Wait for GitHub to publish the site.

If your GitHub username remains `srg9832` and the repository is `CAPDrillTestManager`, the normal URL would be:

`https://srg9832.github.io/CAPDrillTestManager/`

Open the published site in a new browser tab.

---

# STEP 10 — Add the Drill URL to Supabase Auth configuration

In Supabase:

1. Open **Authentication**.
2. Open **URL Configuration**.
3. Keep your existing CAP Schedule Site URL unless you intentionally want to change the main auth landing page.
4. Add the Drill site to the allowed Redirect URLs:

   `https://srg9832.github.io/CAPDrillTestManager/**`

5. Leave the existing Schedule and Leadership Feedback URLs in place.

---

# STEP 11 — First production login

Open the GitHub Pages site and sign in using the **same email/password** you already use for CAP Schedule.

Because the migration bootstraps existing Schedule App Admins, your normal administrator login should have full Drill Application Admin access immediately.

Open **Administration** and confirm:

- Member List
- Users & Permissions
- Units
- Other Activities
- Drill Tests

are available.

---

# STEP 12 — Assign Drill permissions

Drill permissions are independent from the other applications.

## Data Entry

Can:
- enter drill tests in assigned units/activities;
- view records for the assigned scope;
- use Dashboard, Records, Reports, and Statistics for the assigned scope.

## Unit Admin

Includes Data Entry and can:
- maintain the unit's Drill roster status;
- create/link users whose home unit is that unit;
- grant/revoke that unit's Drill access;
- grant temporary Data Entry access to visitors;
- revoke outside-unit borrowed access held by its own members.

## Create / Manage Other Activities

Allows creation and management of Wing Drills, Encampments, Cadet Program Activities, etc., without making the user an Application Admin.

## Application Admin

Full Drill Test Manager control.

---

# STEP 13 — Temporary cross-unit permission workflow

Example: an MT-060 cadet helps MT-012 conduct drill tests for one evening.

### MT-012 grants the permission

1. MT-012 Unit Admin signs in.
2. Open **Administration → Users & Permissions**.
3. Click **Grant Temporary Cross-Unit Access**.
4. Select MT-012 as the host unit.
5. Enter the visitor's exact login email.
6. Choose:
   - Tonight
   - 7 days
   - 30 days
   - Custom Date / Time
   - No expiration
7. Add a note if desired.
8. Grant access.

A normal Unit Admin can grant **Data Entry only** to an outside-unit user. Cross-unit Unit Admin elevation requires Application Admin.

### MT-060 can clean up its own member's borrowed access

If MT-012 forgets to remove the permission:

1. MT-060 Unit Admin signs in.
2. Open **Users & Permissions**.
3. Open the MT-060 member.
4. The MT-012 permission appears as a foreign/borrowed permission.
5. Click **Revoke**.

MT-060 can terminate its own member's outside access but cannot extend, upgrade, or recreate MT-012's permission.

The action is recorded in the Drill audit log.

---

# STEP 14 — Member active/inactive behavior

Unit Admins can mark members Active or Inactive in **Administration → Member List**.

- Active cadets appear in normal CAPID suggestions.
- Inactive cadets remain in the database and historical records.
- Typing an inactive cadet's exact CAPID still finds them and permits an evaluation.
- Saving a score does not automatically erase historical inactive status.

---

# STEP 15 — Other Activities

Use **Administration → Other Activities** to create:

- Encampment
- Wing Drill
- Cadet Program Activity
- Wing Conference
- Training Activity
- Other

When a cadet is tested at an activity, the record retains both:

- the activity where the test occurred; and
- the cadet's home unit at the time of evaluation.

That record therefore appears in activity reporting and the cadet's home-unit reporting.

---

# STEP 16 — Public sequence viewer

The public sequence viewer works before login through the `drill_public_sequences` view.

It exposes only active test reference information. It does not expose:

- CAPIDs
- names
- scores
- users
- permissions
- audit records

If an App Admin edits an active test definition/sequence, the public viewer reads the updated database definition instead of a permanently hard-coded copy.

---

# STEP 17 — Large data volumes

The Dashboard and Reports pages do not use a true “Show All” operation.

They:

- start with 10 rows;
- use Show 10 More;
- allow a custom row count;
- cap a single rendered list at 250 rows;
- use Supabase range queries;
- use an aggregate RPC for Dashboard totals.

A database containing 1,000, 10,000, or more drill tests can therefore continue to work without rendering every record at once.

---

# STEP 18 — Mobile / PWA check

Use Edge/Chrome DevTools:

1. Press **F12**.
2. Press **Ctrl+Shift+M**.
3. Test around `390 × 844` for a phone.
4. Test an 8-inch tablet in portrait and landscape.

On narrow phones:

- the drill scorecard becomes stacked/touch-friendly;
- Dashboard/Records/Reports rows become record cards;
- the navigation remains horizontally scrollable if needed.

Once served by GitHub Pages over HTTPS, supported devices can install/add the site to the home screen as a PWA.

---

# STEP 19 — Run the full QA checklist

Open:

`QA_CHECKLIST.md`

Do not consider the site production-ready until the important permission tests pass, especially:

- MT-012 granting temporary access to MT-060;
- MT-060 revoking its own member's borrowed MT-012 access;
- preventing MT-060 from increasing MT-012 permission;
- activity-to-home-unit report roll-up;
- unknown CAPID creation;
- signed-out public sequence safety.

---

# Troubleshooting

## The page says config.js is not configured

Copy your existing public/anon/publishable key into `config.js`.

## “Profile not found”

The Auth account exists but does not have the expected `profiles` row. Your normal CAP Schedule user-management flow should have created it. Use the Drill home-unit user create/link flow for a properly linked member account.

## User can sign in but has no Drill unit/activity

Assign at least one Drill Data Entry / Unit Admin / activity permission. Schedule or Leadership permission does not automatically become Drill permission.

## Unit Admin cannot find an outside visitor

Use **Grant Temporary Cross-Unit Access** and search by the visitor's exact login email. The visitor must already have a linked CAP login/member record; their home unit can create/link it first.

## Edge Function returns 401

Sign out/in and confirm `drill-admin-users` is deployed to project `vosvdkkuiijywwmqzdiu`.

## Edge Function returns 403

The caller is neither Drill App Admin nor the target member's home Unit Admin for the requested create/link operation.

## Public sequences do not load

Run `supabase/VERIFY_AFTER_INSTALL.sql`. Confirm `drill_public_sequences` returns rows and `config.js` points at the correct Supabase project/public key.

## RLS / permission denied

Do not disable Row Level Security. Check the Drill permission row, expiration, revocation status, and the user's home-unit assignment.

## Need to remove only Drill Test Manager

`supabase/ROLLBACK_DRILL_ONLY.sql` is included as a destructive Drill-only rollback helper. It is intended to remove Drill-specific tables/functions/data while leaving shared Schedule/Leadership objects intact.

**Do not run it casually. It deletes Drill Test Manager records.**
