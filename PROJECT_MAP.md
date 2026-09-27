# PROJECT_MAP — Moaen (معاين)

> Remote car-inspection marketplace. A buyer in one city hires a certified local
> inspector to examine a vehicle and receive a report before travelling to buy it.
>
> **Last updated:** 2026-09-27 · **Phase:** 1 — architecture, schema and RLS complete and verified against the live project; only the device smoke test (M5) remains, pending an Android emulator.
> **Rule:** update this file in the same change as any code it describes.

---

## [TECH_STACK]

Versions verified 2026-09-27 against pub.dev, the Flutter infra release manifest,
and GitHub releases. Deprecated APIs and channels (`beta`, `dev`) rejected.

| Layer | Choice | Version | Published | Status |
|---|---|---|---|---|
| Framework | Flutter | **3.47.5** | 2026-09-18 | Upgraded from 3.41.0 |
| Language | Dart | **3.13.4** | 2026-09-18 | Bundled with the above |
| Client state | `flutter_riverpod` | 3.4.3 | 2026-09-03 | Resolved |
| Routing | `go_router` | 18.0.1 | 2026-09-02 | Resolved |
| Backend | Supabase Postgres + Auth + Storage | project `ybglobvcqgkfclvkjkri` | live | **Migrations applied** |
| CLI | `supabase` | 2.118.0 | 2026-09-25 | Installed |
| Log sink | `path_provider` | 2.1.6 | 2026-06-15 | Resolved |
| i18n | `intl` | 0.20.3 | 2026-06-25 | Pinned for Phase 2 |
| Test driver | `postgres` *(dev only)* | 3.5.17 | 2026-09-24 | Resolves the RLS suite over the wire |

**The upgrade was mandatory, not cosmetic.** `go_router` 18.0.1 declares
`flutter: >=3.44.0` and `flutter_riverpod` 3.4.3 declares `sdk: ^3.12.0`. Neither
resolves on the 3.41.0 / Dart 3.11.0 that was installed.

**Supabase over Firebase** (the brief allowed either). The domain is a 5-table
relational graph with 5 foreign keys; Postgres enforces referential integrity in
the engine, while Firestore cannot enforce an FK and would admit orphaned
reports and payments. The RLS requirement is likewise native to Postgres and only
approximately expressible as Firestore rules.

**`publishableKey`, not `anonKey`.** `supabase_flutter` 2.17.2 deprecates
`anonKey` in favour of `publishableKey`. The dashboard now issues an
`sb_publishable_…` key, which is what `tool/dart_defines.local.json` carries and
what `/auth/v1/health` was verified against. The first half of P9 is closed.

**`postgres` is a dev dependency, not app code.** It exists solely so the RLS
suite can reach a real database; nothing under `lib/` imports it, and it is not
reachable from a release build.

**Rejected for Phase 1 (YAGNI):** Freezed / json_serializable / build_runner,
Firebase, Bloc, GetX, DI frameworks, analytics, crash reporting, remote log
shipping, feature flags, `flutter_localizations` (unused until RTL lands).

### Environment

| Component | State |
|---|---|
| Flutter 3.47.5 / Dart 3.13.4 | ready |
| Android SDK, JDK 21, licences | ready — Build-Tools **36.1.0** |
| Supabase CLI 2.118.0 | ready |
| Project region | **`aws-0-eu-west-2`** (London) |
| Docker Desktop | absent — `supabase test db` unavailable, and not needed (see D5) |
| WSL2 | non-functional (virtualisation disabled in firmware) |
| Android emulator target | none attached — M5 smoke still needs one |

Three environment facts that cost real time and are not discoverable from the code:

- **`db.<ref>.supabase.co` does not resolve** for this project. The pooler is the
  only route in, so every connection must be
  `aws-0-eu-west-2.pooler.supabase.com`. Pooler DNS is a wildcard: all regions
  resolve and all accept TCP on 5432/6543, so reachability cannot be probed. Only
  a real auth attempt reveals the region, and it fails with
  `tenant/user … not found` rather than a password error — which means a wrong
  region looks exactly like a wrong password until the region is right.
- **A password containing `@` must be percent-encoded** (`%40`) inside a
  connection URI, or the URI parses as a host boundary.
- **The workspace path contains a space** (`E:\Real Projects\Moaen`). This breaks
  the Kotlin incremental compiler's page cache on Windows with *Could not close
  incremental caches*, which survives `flutter clean`. `kotlin.incremental=false`
  in `android/gradle.properties` is the fix, and should be removed if the project
  is ever moved to a space-free path.
- **Android Build-Tools 36.0.0 was a half-finished download** (a directory
  containing only `.installer`) that Gradle could not repair or replace.
  `buildToolsVersion = "36.1.0"` in `android/app/build.gradle.kts` pins the
  revision that is actually complete on disk.

---

## [SYSTEM_FLOW]

### Achievable objectives (Phase 1)

| # | Objective | Verified by | State |
|---|---|---|---|
| O1 | A session resolves to the correct role screen | `auth_flow_test.dart` — 4 tests | **done** |
| O2 | A client can never read or write another client's rows | `rls_policies_test.dart` — 10 tests | **done, live** |
| O3 | An inspector sees pending jobs in their city only | `rls_policies_test.dart` — 5 tests | **done, live** |
| O4 | A client cannot forge completion or a released payment | `rls_policies_test.dart` — 7 tests | **done, live** |
| O5 | Logging is non-blocking and bounded | `app_logger_test.dart` — 9 tests | **done** |

Every O2–O4 assertion has been executed against the live project, not merely
reviewed. That distinction mattered: the `SECURITY DEFINER` recursion fix and the
`handle_new_user` provisioning path are the kind of thing that reads correctly and
fails loudly at runtime.

### Data flow (Phase 2+, context only — not built)

```
Client                     Supabase                      Inspector
  │ create request ───────▶ car_inspections (pending) ─────▶ job board (city match)
  │                            │                                  │ accept
  │                            │◀── inspector_id + accepted ───────┘
  │                            │                                  │ in_progress
  │                            │◀── Inspection_Reports + media ────┘
  │ escrow payment ──▶ payments(status=escrow)   [service role only]
  │ view report     ◀── reports + report_media + signed URLs
  │ release funds   ──▶ payments(status=released) [service role only, P2]
```

### Inspection state machine

Enforced by a database trigger, not client code, so no API caller can skip a state.

```
pending ──▶ accepted ──▶ in_progress ──▶ completed
   │           │             │
   └───────────┴─────────────┴──────▶ cancelled
```

Acceptance also forces `inspector_id := auth.uid()`, so a job cannot be claimed on
another inspector's behalf. Commercial terms (client, city, price, vehicle
identity, seller contact) are frozen once a request leaves `pending`.

---

## [ARCHITECTURE]

```
lib/
  main.dart                       bootstrap: config -> logger -> Supabase -> run
  app.dart                        MaterialApp.router, theme, lifecycle flush
  core/
    env.dart                      dart-define config + validation
    logging/app_logger.dart       async, bounded, redacting, rotating file sink
    router/app_router.dart        GoRouter + auth/role redirect guard
  features/
    auth/  user_profile · auth_repository · auth_controller · sign_in_page
    home/  role_landing_page
  shared/
    utils/validators.dart
supabase/
  migrations/0001_schema.sql      types, tables, indexes, invariant triggers
  migrations/0002_rls.sql         auth provisioning, helpers, RLS, profiles view
  migrations/0003_storage.sql     private buckets + object policies
  config.toml
test/
  core/logging/app_logger_test.dart
  features/auth/auth_flow_test.dart
  support/test_client.dart
  integration/rls_policies_test.dart   O2/O3/O4, against the live project
tool/
  dart_defines.local.json         gitignored client config (URL + publishable key)
dart_test.yaml                    declares the `integration` tag
```

`core/` holds only code with real call sites: configuration, logging, routing.
No empty `features/` folders were scaffolded ahead of need. There is deliberately
no `shared/widgets/` yet — nothing in Phase 1 needs one, so the common
sign-in/landing error and row patterns stay inline until a third caller exists.

### Schema — as deployed

Verified by querying the catalog of the live project after `supabase db push`:

| Property | Expected | Live |
|---|---|---|
| Migrations applied | 0001, 0002, 0003 | 0001, 0002, 0003 |
| Tables | 5 | 5 (+ `inspector_profiles` view) |
| Primary keys | 5 | 5 |
| Foreign keys | 5 among app tables | 6 — the sixth is `users.id → auth.users.id` |
| RLS enabled | all 5 | all 5 |
| Policies | — | 13 |
| Triggers | 2 in `public` | 2 in `public` + 1 on `auth.users` |
| Storage buckets | 2 private | 2, both `public = false` |

`users` — 1:1 with `auth.users` · `car_inspections` — aggregate root ·
`inspection_reports` — one per inspection · `report_media` — append-only ·
`payments` — one escrow record per inspection

Deletion policy: dependent evidence dies with its parent (inspection → report →
media, CASCADE), money and inspection history survive (RESTRICT). Deleting a
user who has taken part in an inspection is therefore refused, which is the
intended behaviour — that history is the product.

No `cities` reference table. `city` is free text and the board matches it
case-insensitively; normalising it waits until a second consumer needs a list.

### Security design

1. **RLS recursion.** A policy on `car_inspections` must read the caller's role
   and city from `users`. Referring to `users` directly re-enters `users`' own
   SELECT policy and Postgres aborts the statement with *infinite recursion
   detected in policy for relation "users"*. Solved by five `SECURITY DEFINER`
   `STABLE` helpers with `search_path = ''`, owned by the table owner and
   therefore exempt from RLS: `current_user_role`, `current_user_city`,
   `is_inspection_participant`, `is_inspection_inspector`,
   `is_report_participant`. A sixth, `storage_inspection_id`, parses an object
   path safely and returns NULL rather than raising on a malformed one.
   A NULL city or NULL id makes every check false, so both cases fail closed.
   *Verified live: the suite impersonates each persona and reads through these
   helpers without a recursion abort.*

2. **Policy independence.** Participant checks go through the helpers, not
   through `car_inspections`' own policies. A bug in one table's RLS therefore
   cannot widen visibility in the tables layered above it.

3. **PII boundary.** A blanket SELECT on `users` would let any inspector read
   every rival's email and phone. `users` is readable only by its owner and by
   admins; everyone else reads the `inspector_profiles` view, which projects only
   `id, full_name, avatar_url, location_city, rating` and intentionally runs with
   owner rights. The suite asserts that exact column list from
   `information_schema`, so adding `email` to the view breaks a test.

4. **No self-registered admins.** `public.users` rows are created by the
   `handle_new_user` trigger on `auth.users`, never by the client, and the
   requested role is whitelisted to `client|inspector`. `users.role` is
   additionally frozen by a trigger against self-modification, so the UPDATE
   policy that lets a user fix their phone number cannot be used to escalate.
   *Verified live: a client updating their own `role` is refused with 42501, and
   the admin path is exercised as `authenticated` so that
   `current_user_role() = 'admin'` is genuinely evaluated rather than short-
   circuited by `service_role`'s BYPASSRLS.*

5. **Payments are server-written.** `authenticated` has SELECT on `payments` and
   nothing else. No INSERT policy exists, so a client cannot post
   `status = 'released'` and fabricate a settlement. Writes require the service
   role. See P2. *Verified live.*

6. **Fail-closed storage.** Both buckets are private; reads require
   participation, writes require being the assigned inspector. UPDATE and DELETE
   are ungranted because evidence is immutable. The migration also drops any
   scaffolded `Allow public…` policy on `storage.objects`, which would otherwise
   OR its way past the policies below it.

### How the RLS policies are actually proven

`test/integration/rls_policies_test.dart` — **24 assertions, all executed against
the live project.** The mechanics are worth recording, because each one was a real
obstacle:

- **A persona is impersonated by switching role, not by superuser.** Each test
  sets `request.jwt.claims` and then `set_config('role', …, true)`, which is what
  PostgREST does per request. Asserting from the owner role would bypass RLS and
  prove nothing. The suite confirms the impersonation took effect by reading
  `auth.uid()` and `current_user` rather than assuming it.
- **The whole suite runs in one transaction that never commits**, so the fixtures
  roll back and the project is left untouched. Confirmed after every run: all six
  tables read 0 rows.
- **Every denied statement runs inside a savepoint.** A statement error inside an
  explicit transaction aborts it, and an aborted transaction rejects everything
  except `ROLLBACK TO SAVEPOINT` — so that rollback must be the very next
  statement. Restoring the role first produces a confusing `25P02` instead of the
  real result.
- **`setUpAll` is guarded separately.** It runs even when every test in the group
  is skipped, so it must stand down on its own when there is no credential.
- **`count` returns the number of rows, and `scalar` returns the first column.**
  These are not interchangeable. A single helper that quietly coerced a non-integer
  to 0 would make every "sees nothing" assertion pass vacuously while the "sees
  something" ones failed for no visible reason — which is exactly the failure mode
  that cost a debugging cycle here.

---

## [ORPHANS & PENDING]

### Blocking — Phase 1 cannot close

| ID | Item | Action needed |
|---|---|---|
| **B3** | No Android emulator or device attached (`flutter doctor` lists only Windows/Chrome/Edge). Blocks the M5 smoke test. | Boot an AVD, then `flutter run --dart-define-from-file=tool\dart_defines.local.json`. |

B1 (migrations unapplied) and B2 (email confirmation left on) are **resolved** —
B2 confirmed by `/auth/v1/settings` reporting `mailer_autoconfirm: true`. Sign-up
now returns a session. Only B3 stands between the project and M5.

### Resolved decisions

| ID | Decision |
|---|---|
| D1 | **Escrow ships manual.** Phase 2 records escrow/released/refunded without integrating a payment provider. The schema already supports it, so a licensed provider later needs no migration. Escrow is a regulated activity; flagged for legal review before any real money moves. |
| D2 | **Pricing.** `car_inspections.price` is set at creation by the client as a stated budget. No quotes table, no negotiation flow. Revisit if a counter-offer feature appears. |
| D3 | **Backend provisioning.** Free hosted project `ybglobvcqgkfclvkjkri`, not Docker. |
| D4 | **`user_role` enum is `client \| inspector \| admin`.** `admin` is never self-assignable (see Security design §4). Admin UI is Phase 3. |
| D5 | **The RLS suite is Dart, not pgTAP.** `supabase test db` needs Docker, which this machine does not have. A pgTAP suite is not a workable substitute: it reports pass/fail by writing TAP to the *server's* stdout, which cannot be captured over a normal Postgres connection, so a Dart port of it would have passed no matter what the policies did. Driving the assertions from Dart yields real pass/fail, runs under the project's existing `flutter test`, and needs no second container. The pgTAP file was removed rather than left to drift — one source of truth for the security assertions. |

### Assumptions

| ID | Assumption | Rationale |
|---|---|---|
| A1 | Email + password only. `phone` is a contact field. | SMS login needs a paid provider; no requirement states it. |
| A2 | An inspector serves exactly one city. | `users.location_city` is scalar per the brief. Multi-city needs an `inspector_cities` join table. |
| A3 | Currency is EGP, single implicit currency. | A currency column is cheap to add later and unrequested now. |
| A4 | `updated_at` added to `car_inspections`. | Not in the brief; required to audit status transitions, which RLS alone cannot provide. |
| A5 | `inspection_center_name` stays a text column. | An inspector may be a person or a centre; normalising waits for a second consumer. |
| A6 | Android + iOS only. | Windows desktop toolchain is broken and the product is mobile. |
| A7 | `overall_rating` is inspector-supplied, not the mean of the six components. | Holistic judgement may legitimately differ from an average. |
| A8 | The pooler region for a project is not discoverable from its URL. | Established the hard way; recorded under Environment so it is not re-derived. |

### Deferred — Phase 2 and beyond

| ID | Item | Blocked by |
|---|---|---|
| P1 | `users.rating` has no source table. | Needs a `reviews` table and a rule for who may review. |
| P2 | Escrow release / refund endpoint. | D1. A service-role Edge Function plus an audit log. |
| P3 | PDF report generation. | `pdf_report_url` stays nullable until then. |
| P4 | Media and PDF upload UI. | Buckets and policies exist (0003); only the client side is missing. |
| P5 | Job board, request creation, report entry. | Phase 2 feature screens. No folders scaffolded yet. |
| P6 | Arabic UI and RTL. | `intl` is pinned; translations and `flutter_localizations` arrive with the Phase 2 screens. |
| P7 | Notifications on status change. | No push provider selected. |
| P8 | Inspector payouts. | Follows the D1 escrow outcome. |
| P9 | Re-enable email confirmation for production. | Disabled for Phase 1 testing; **restore before any real launch**, since a confirmed address is the only thing standing between a typo and an account takeover. |
| P10 | Normalise `city` to a reference table. | Awaits a second consumer (A5/A2). |

---

## Milestones

| M | Deliverable | Pass condition | State |
|---|---|---|---|
| **M0** | Toolchain | `flutter --version` reports 3.47.5 / Dart 3.13.4 | **met** |
| **M1** | Scaffold | `flutter analyze` 0 issues; `flutter test` green; `flutter build apk --debug` produces an APK | **met** — APK 161.7 MB |
| **M2** | Schema | Migrations apply cleanly; 5 tables, FKs, PKs, transition and role-guard triggers present | **met** — applied and inspected in the catalog |
| **M3** | RLS | Cross-tenant reads return 0 rows; city scoping holds; forged `released` payment denied | **met** — 24/24 live |
| **M4** | App wiring | Logger, sign-in and router-guard tests pass | **met** — 17 unit + 24 integration |
| **M5** | Smoke | Boots on an emulator, signs in, reaches the role screen, writes a log file | **blocked by B3** |

## Running it

```powershell
# 1. database — the password must be percent-encoded; note the region and port.
$env:MOAEN_DB_URL = "postgresql://postgres.ybglobvcqgkfclvkjkri:<pw>@aws-0-eu-west-2.pooler.supabase.com:5432/postgres?sslmode=require"
flutter test test\integration\rls_policies_test.dart

# 2. client
flutter pub get
flutter run --dart-define-from-file=tool\dart_defines.local.json
flutter test
```

`flutter test` on its own reports 17 passing and 24 skipped: the RLS suite skips
itself when `MOAEN_DB_URL` is absent, so a developer with no database credential
still gets a useful signal. A credential that is *present but wrong* is not
skipped — it fails loudly.

`tool/dart_defines.local.json` holds the project URL and the publishable key,
both public by design, but it is gitignored anyway so that a database password
cannot be committed alongside them. It is named to avoid colliding with
`.env.local`, which the Supabase CLI reads as dotenv while
`--dart-define-from-file` requires JSON — the two formats are not compatible.
