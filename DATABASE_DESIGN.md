# CAP Drill Test Manager — Database Design

## Shared foundation

The Drill application reuses the same Supabase project and shared CAP objects already used by the other applications:

- `auth.users` — login accounts
- `profiles` — application login profile
- `units` — CAP units
- `members` — organization-wide member roster
- `member_unit_assignments` — current and historical member-to-unit assignments
- `profiles.member_id` — optional link from a login account to the member roster

`members.capid` remains the human/business lookup key. Database relationships use the member UUID so correcting a CAPID later does not require rewriting every drill record.

## Drill-specific tables

### `drill_global_permissions`
Application-wide Drill permissions:
- `is_app_admin`
- `manage_activities`

These are intentionally independent from CAP Schedule and Leadership Feedback permissions.

### `drill_unit_permissions`
Per-unit permissions:
- Data Entry
- Unit Admin

The row also stores:
- who granted it;
- the host/granting unit;
- grant time;
- optional expiration;
- grant note;
- revocation time, actor, and reason.

An active permission has no `revoked_at` and is not expired.

### `drill_activities`
Generalized activity/event table for:
- Encampment
- Wing Drill
- Cadet Program Activity
- Wing Conference
- Training Activity
- Other

### `drill_activity_permissions`
Per-activity Data Entry and Activity Admin access.

### `drill_user_preferences`
Stores the user's selected default Unit or Activity. Dashboard, Records, Reports, Statistics, and New Drill Test all use the same default scope.

### `drill_test_definitions`
Administrator-editable drill test metadata:
- code and label;
- topic;
- conditions;
- scoring mode;
- passing / maximum score;
- source page;
- full command sequence;
- active state and version.

### `drill_test_items`
Administrator-editable graded items:
- item number/key;
- command;
- acceptable standards;
- point value;
- optional group label;
- order.

### `drill_records`
Stores the completed drill evaluation.

Important historical snapshots are retained with every record:
- CAPID / first / last name;
- test code / label / topic;
- passing threshold;
- graded items;
- sequence;
- home unit at evaluation time.

This prevents later roster or test-definition edits from changing what an old record represented.

### `drill_audit_log`
Tracks important Drill administrative changes and permission activity.

## Cross-unit borrowed access

The host unit owns its permission.

Example: MT-012 grants an MT-060 cadet temporary MT-012 Data Entry permission.

Authorization rules:
1. MT-012 Unit Admin may grant and revoke MT-012 access.
2. The MT-060 home Unit Admin may revoke the MT-012 borrowed permission for its own member.
3. MT-060 may **not** create, extend, or upgrade MT-012 permission.
4. Application Admin may manage everything.
5. Expired permissions stop working at authorization time; no cleanup job is required.

The member's home unit is resolved server-side from `profiles.member_id` and the active primary `member_unit_assignments` row. A browser-supplied home unit is never trusted for permission decisions.

## Unit and activity roll-up

A drill record contains both:
- where the test occurred (`evaluation_unit_id` or `activity_id`), and
- the cadet's `home_unit_id_at_evaluation`.

Therefore an MT-060 cadet tested at a Wing Drill can appear in:
- the Wing Drill activity report; and
- MT-060's unit report.

The historical home-unit snapshot prevents later transfers from changing old reports.

## Public Drill Sequences

`drill_public_sequences` is the only signed-out Drill dataset. It exposes active test reference data needed for the login-screen sequence viewer:
- code / label;
- topic / conditions;
- source page;
- sequence;
- display/version metadata.

It does not expose CAPIDs, member names, scores, users, permissions, or audit data.

## Large record counts

Dashboard and Reports request bounded ranges from Supabase instead of downloading every record.

Indexes support newest-first queries by:
- home unit;
- evaluation unit;
- activity;
- member;
- creator.

Dashboard totals come from `drill_dashboard_summary()` so a unit with thousands of tests does not have to download thousands of rows merely to display totals.

The browser limits one rendered Dashboard/Reports list to 250 rows. That is a UI safeguard, not a database limit.
