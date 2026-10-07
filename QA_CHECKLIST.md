# CAP Drill Test Manager — Production QA Checklist

Complete this after database migration, Edge Function deployment, and GitHub deployment.

## Existing applications
- [ ] CAP Schedule still opens normally.
- [ ] CAP Schedule can still edit/publish a schedule.
- [ ] CAP Leadership Feedback still opens normally.
- [ ] Leadership Feedback Administration still works.

## Signed-out Drill application
- [ ] Login page opens.
- [ ] Public Drill Sequences load without signing in.
- [ ] Achievement 1 through 8 and Wright Brothers appear.
- [ ] Public sequence screen exposes no CAPID/member/score information.

## Authentication
- [ ] Existing CAP Schedule / Leadership Feedback email and password work.
- [ ] Signing out returns to the public login/sequence screen.

## Default Unit / Activity
- [ ] Header shows only scopes the user may use.
- [ ] Changing the default updates New Drill Test.
- [ ] Dashboard uses the same default.
- [ ] Records uses the same default.
- [ ] Reports uses the same default.
- [ ] Statistics uses the same default.
- [ ] Default remains after refresh/sign-in.

## New Drill Test
- [ ] Existing active CAPID fills first and last name.
- [ ] Inactive CAPID is found when typed exactly.
- [ ] Inactive cadet does not appear in normal unit suggestion list.
- [ ] Unknown CAPID enables first/last name and home-unit entry.
- [ ] Saving an unknown CAPID creates the shared member record.
- [ ] Ungraded sequence steps show `--` inline.
- [ ] Ungraded steps have no Satisfactory / Unsatisfactory controls.
- [ ] S/U test cannot submit until every graded item is scored.
- [ ] Passing threshold calculates correctly.
- [ ] Achievement 7 point scoring works.
- [ ] Save Draft works.
- [ ] Submit Test works.

## Dashboard / Records / Reports
- [ ] Dashboard shows unit/activity-wide totals, not just the logged-in user's submissions.
- [ ] Recent table order is Date, Cadet, Test, Score, Status, Testing Officer, Evaluation Unit / Activity.
- [ ] Dashboard begins with 10 records.
- [ ] Dashboard Show 10 More works.
- [ ] Dashboard custom row count works and caps at 250.
- [ ] Records displays records for the full authorized scope.
- [ ] Reports begins with 10 submitted records.
- [ ] Reports Show 10 More works.
- [ ] Reports custom row count works and caps at 250.
- [ ] An MT-060 cadet tested at an Other Activity appears in MT-060 reporting.

## Record editing
- [ ] Record View opens.
- [ ] Authorized creator/admin sees Edit Record.
- [ ] Unauthorized user cannot edit by manually calling the RPC.
- [ ] Edited record remains auditable.

## Statistics
- [ ] Testing Officer mode works.
- [ ] Record Submitter mode works.
- [ ] Same-test adjusted difference displays.
- [ ] Fewer than 10 records suppresses pairwise interpretation.
- [ ] Fewer than 30 records shows Small Sample.
- [ ] Significant q-values are labeled Statistical Signal, not misconduct.
- [ ] Screen explains alternative causes / assignment effects.

## Member administration
- [ ] Unit Admin can add a member to their unit.
- [ ] Unit Admin can correct name/CAPID.
- [ ] Unit Admin can mark member inactive.
- [ ] Unit Admin can reactivate member.
- [ ] Historical records remain after status changes.

## User and permission administration
- [ ] Home Unit Admin can create/authorize a shared login with their unit as its Drill Home Unit.
- [ ] Shared Auth users appear in the Application Admin directory.
- [ ] A shared login can be assigned a Drill Home Unit without a CAPID/member link.
- [ ] Unit permissions require a Drill Home Unit, not a CAPID link.
- [ ] Unit Admin can assign Data Entry in their unit.
- [ ] Unit Admin can assign Unit Admin in their own unit.
- [ ] Home Unit Admin cannot directly grant another unit's permission.
- [ ] Application Admin can assign Drill App Admin.
- [ ] Application prevents removal of the last Drill App Admin.
- [ ] Application Admin can assign Create / Manage Other Activities.
- [ ] Application Admin can assign activity Data Entry / Activity Admin.

## Temporary cross-unit permission scenario
Use MT-060 and MT-012 for this test.

- [ ] MT-060 visitor has an existing shared login with Drill Home Unit MT-060.
- [ ] MT-012 Unit Admin searches that visitor by exact email.
- [ ] MT-012 can grant temporary MT-012 Data Entry.
- [ ] MT-012 cannot grant the outside member Unit Admin unless using Application Admin.
- [ ] Visitor can switch default to MT-012 and enter a test.
- [ ] Tonight / 7 days / 30 days / Custom / No expiration work.
- [ ] MT-012 can revoke its permission.
- [ ] Re-grant permission.
- [ ] MT-060 home Unit Admin sees the borrowed permission.
- [ ] MT-060 can revoke the borrowed MT-012 permission.
- [ ] MT-060 cannot extend or upgrade the MT-012 permission.
- [ ] Grant and revoke actions appear in the permission audit.

## Other Activities
- [ ] Activity Manager can create an activity.
- [ ] Creator receives access to the new activity.
- [ ] Activity can be edited.
- [ ] Activity can be made inactive.
- [ ] Activity testing works.
- [ ] Activity record rolls up to cadet's home unit.

## Drill test administration
- [ ] App Admin can edit a test definition.
- [ ] App Admin can edit sequence text.
- [ ] App Admin can edit acceptable standards.
- [ ] App Admin can change pass/max score.
- [ ] App Admin can make a test inactive.
- [ ] Public sequence viewer reflects active test edits.

## Mobile / PWA
- [ ] 390 × 844 browser emulator is usable.
- [ ] New Drill Test scoring cards are easy to tap.
- [ ] Dashboard/Records/Reports turn into mobile record cards.
- [ ] GitHub Pages offers install/add-to-home-screen on supported devices.
- [ ] Installed PWA opens normally.
