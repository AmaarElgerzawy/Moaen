# PROJECT_MAP — Moaen (معاين)

> Remote car-inspection marketplace. A buyer in one city hires a certified local
> inspector to examine a vehicle and receive a report before travelling to buy it.
>
> **Last updated:** 2026-09-29 · **Phase:** 2 — the client request flow *and* the inspector flow (city-scoped job board, my jobs, profile, accept → start → complete) are built and tested: **188/188 with `MOAEN_DB_URL`**, `flutter analyze` clean. Only the device smoke test (M5) remains, pending an Android emulator.
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
`sb_publishable_…` key, which is what `env.dart` falls back to in debug builds
(D6) and what `/auth/v1/health` was verified against. The first half of P9 is
closed.

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
- **Grepping an APK's raw bytes for a compiled string proves nothing.** Entries
  are DEFLATE-compressed, so a search of the file as-is reports a credential
  "missing" when it is present. Inflate first, then search the Dart snapshot —
  `assets/flutter_assets/kernel_blob.bin` in debug, `lib/<abi>/libapp.so` in
  release. This is the only reliable way to confirm what a build actually
  embeds, which is how D6's release exclusion is verified.
- **Android resource strings are not greppable in `resources.arsc`** — the
  string pool may be UTF-8 or UTF-16 and a raw byte search finds neither
  reliably. Use the SDK tool instead:
  `aapt2 dump resources <apk>`, which prints the resolved value per locale and
  is the authority on whether `values-ar/` actually shipped. That is how the
  localised launcher label is verified. Note the PowerShell console renders
  Arabic as `?????`, so match on the surrounding structure, not the glyphs.

---

## [SYSTEM_FLOW]

### Achievable objectives (Phase 1)

| # | Objective | Verified by | State |
|---|---|---|---|
| O1 | A session resolves to the correct role screen | `auth_flow_test.dart` — 13 tests | **done** |
| O2 | A client can never read or write another client's rows | `rls_policies_test.dart` — 10 tests | **done, live** |
| O3 | An inspector sees pending jobs in their city only | `rls_policies_test.dart` — 5 tests | **done, live** |
| O4 | A client cannot forge completion or a released payment | `rls_policies_test.dart` — 7 tests | **done, live** |
| O5 | Logging is non-blocking and bounded | `app_logger_test.dart` — 9 tests | **done** |

Every O2–O4 assertion has been executed against the live project, not merely
reviewed. That distinction mattered: the `SECURITY DEFINER` recursion fix and the
`handle_new_user` provisioning path are the kind of thing that reads correctly and
fails loudly at runtime.

### Data flow (Phase 2 — the inspector half is built; report entry and escrow are pending)

```
Client                     Supabase                      Inspector
  │ create request ───────▶ car_inspections (pending) ─────▶ job board (city match)  ✓
  │                            │                                  │ accept           ✓
  │                            │◀── inspector_id + accepted ───────┘                 ✓
  │                            │                                  │ in_progress      ✓
  │                            │◀── Inspection_Reports + media ────┘                 (P4)
  │ escrow payment ──▶ payments(status=escrow)   [service role only]                (P2)
  │ view report     ◀── reports + report_media + signed URLs                        (P4)
  │ release funds   ──▶ payments(status=released) [service role only]               (P2)
```
✓ = built and tested. The buyer's create/dashboard/list/detail and the
inspector's board/jobs/profile plus the three enforced transitions are live
against real RLS; the report form, media upload and manual escrow remain Phase 2
work (P4, P2).

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
  app.dart                        MaterialApp.router, locale, delegates, lifecycle
  core/
    env.dart                      dart-define config, debug fallback + validation
    logging/app_logger.dart       async, bounded, redacting, rotating file sink
    localization/locale_provider  the active locale; Arabic default (D7)
    router/app_router.dart        GoRouter + auth/role redirect guard
    theme/app_theme.dart          AppSpacing / AppRadius / AppTheme tokens (D8)
  l10n/
    arb/app_en.arb                message template — its keys are the contract
    arb/app_ar.arb                Arabic translations
    gen/                          `flutter gen-l10n` output, gitignored
  features/
    auth/  user_profile · auth_repository · auth_controller · sign_in_page
           user_role_localizations
    home/  role_landing_page
    inspections/
      data/         inspection_repository      all car_inspections I/O + 3 enforced transitions
      domain/       inspection_request · inspection_draft
      application/  inspection_controller      myRequests / dashboard / jobBoard / myJobs /
                                                inspectorJob (+ accept · start · complete)
      presentation/ client screens (dashboard, create, my requests, request detail)
                    inspector_home_page        NavigationBar: Job board | My jobs | Profile
                    inspector_job_detail_page  status-driven accept/start/complete
                    widgets/request_widgets.dart  StatusChip · RequestCard · DetailCard · DetailRow
  shared/
    utils/validators.dart
supabase/
  migrations/0001_schema.sql      types, tables, indexes, invariant triggers
  migrations/0002_rls.sql         auth provisioning, helpers, RLS, profiles view
  migrations/0003_storage.sql     private buckets + object policies
  config.toml
test/
  core/localization_test.dart     RTL default, fallback, translation coverage
  core/logging/app_logger_test.dart
  features/auth/auth_flow_test.dart
  features/inspections/client_request_flow_test.dart · rtl_layout_test.dart
  features/inspections/inspector_flow_test.dart · inspector_rtl_layout_test.dart
  support/fake_inspection_repository.dart · test_client.dart
  integration/rls_policies_test.dart   O2/O3/O4, against the live project
tool/
  dart_defines.local.json         gitignored, optional client override (D6)
l10n.yaml                         gen-l10n config; ARB in, Dart into lib/l10n/gen
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
| Migrations applied | 0001, 0002, 0003 | 0001, 0002, 0003, 0004 |
| Tables | 5 | 5 (+ `inspector_profiles` view) |
| Primary keys | 5 | 5 |
| Foreign keys | 5 among app tables | 6 — the sixth is `users.id → auth.users.id` |
| RLS enabled | all 5 | all 5 |
| Policies | — | 13 |
| Triggers | 2 in `public` | 3 in `public` + 1 on `auth.users` |
| Storage buckets | 2 private | 2, both `public = false` |

Migration 0004 adds two columns to `car_inspections` and the sequence behind
them: `reference_no bigint NOT NULL` (server-assigned, from a sequence starting at
1000, rendered as `MN-1001`) and `client_notes text`. Neither needed a policy or
grant change, because Phase 1's grants are table-level and its policies are
row-level with no column lists — a fact worth recording, because the usual
assumption is that a new column means a new policy. *Verified live by undo →
column-absent → re-apply, so it is correct from an empty database and not merely
present.* See D9 and D10.

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

`test/integration/rls_policies_test.dart` — **28 assertions, all executed against
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
- **Exact row-count assertions only hold on an empty project.** The admin
  visibility test asserted `select * from public.users` returned exactly 5 — true
  while the project held no committed profiles, false the moment one real account
  signs up outside the suite's rolled-back transaction (which is what happened:
  a real developer account in `public.users` made it 6). It now asserts visibility
  of all five *fixture* profiles (four of them not the admin's own) plus a count
  greater than one, proving whole-population visibility without depending on what
  the project has accumulated.
- **The reference-integrity assertions (D9) assert the value, not the absence of
  an error.** RLS *permits* a client to UPDATE its own row; the trigger discards
  the change. A test asserting only "no error was raised" would therefore pass
  against a trigger that did nothing at all. The suite asserts the stored number
  is unchanged, and that a client-supplied number is overwritten on insert.
- **A custom enum column arrives as `UndecodedBytes`**, not a Dart enum — cast
  `::text` in the query. A `bigint` arrives as a Dart `int`, while a `numeric`
  serialises as `500` and therefore decodes as an `int` where the model wants a
  `double`; `_asDouble` covers `int`, `double` and `String`.
- **`Connection.openFromUrl(url)` takes the URI positionally** — there is no
  `Connection.open(uri: …)` — and `Result` is not generic. The driver always uses
  the extended query protocol, so a multi-statement `execute` fails with
  `42601: cannot insert multiple commands into a prepared statement`. That is why
  `tool/sql_statement_splitter.dart` exists.

---

## [ORPHANS & PENDING]

### Blocking — Phase 1 cannot close

| ID | Item | Action needed |
|---|---|---|
| **B3** | No Android emulator or device attached (`flutter doctor` lists only Windows/Chrome/Edge). Blocks the M5 smoke test. | Boot an AVD, then `flutter run`. |

**B4 is resolved** (2026-09-27). The Supabase project had the Email sign-in provider
switched off, so GoTrue answered `POST /auth/v1/signup` with
`400 email_provider_disabled` ("Email signups are disabled") and
`POST /auth/v1/token?grant_type=password` with `422 email_provider_disabled`
("Email logins are disabled") — no account could be created and none could be
signed into. Enabled in the dashboard, then confirmed end to end: sign-up creates
the account, the `handle_new_user` trigger populates `public.users` from the
metadata, a session is issued, the password grant succeeds, and the RLS profile
read returns the row. **4/4 live assertions** in
`test/integration/auth_live_test.dart`, which stays as the standing check.

B1 (migrations unapplied) and B2 (email confirmation left on) are also **resolved** —
B2 confirmed by `/auth/v1/settings` reporting `mailer_autoconfirm: true`. Sign-up
returns a session.

**Correction, 2026-09-27.** That endpoint is a *catalogue* for the provider list: it
reports every provider Supabase supports whether or not the project uses one, so
`external.email` appearing there is **not** evidence the provider is enabled — and
relying on it is how B4 went unnoticed. The `mailer_autoconfirm` value does come
from project config and is genuinely confirmed. The only trustworthy signal is the
signup response itself, which is what `auth_live_test.dart` now asserts on.

**B4 was mistaken for a client bug** for a specific, traceable reason: the
`AuthException` *was* caught and logged, but `AppLogger` wrote only to a file on the
device, so `adb logcat` showed Flutter's own IME and inset events and none of the
app's errors. A debug build that logs only to a file nobody can read is
indistinguishable from one with nothing to report. Fixed here: a debug build tees to
the console (`TeeLogWriter`), and a disabled provider is now its own reason, with
its own sentence and its own log line.

Only B3 stands between the project and M5.

### Resolved decisions

| ID | Decision |
|---|---|
| D1 | **Escrow ships manual.** Phase 2 records escrow/released/refunded without integrating a payment provider. The schema already supports it, so a licensed provider later needs no migration. Escrow is a regulated activity; flagged for legal review before any real money moves. |
| D2 | **Pricing.** `car_inspections.price` is set at creation by the client as a stated budget. No quotes table, no negotiation flow. Revisit if a counter-offer feature appears. |
| D3 | **Backend provisioning.** Free hosted project `ybglobvcqgkfclvkjkri`, not Docker. |
| D4 | **`user_role` enum is `client \| inspector \| admin`.** `admin` is never self-assignable (see Security design §4). Admin UI is Phase 3. |
| D5 | **The RLS suite is Dart, not pgTAP.** `supabase test db` needs Docker, which this machine does not have. A pgTAP suite is not a workable substitute: it reports pass/fail by writing TAP to the *server's* stdout, which cannot be captured over a normal Postgres connection, so a Dart port of it would have passed no matter what the policies did. Driving the assertions from Dart yields real pass/fail, runs under the project's existing `flutter test`, and needs no second container. The pgTAP file was removed rather than left to drift — one source of truth for the security assertions. |
| D6 | **Development credentials are hardcoded as a debug-only fallback.** `env.dart` compiles the project URL and publishable key into debug builds so a bare `flutter run` works on an emulator. The guard is the point: an unconditional fallback would let `flutter build apk --release` with no flags silently ship production users onto the testing database — starting cleanly and writing to the wrong place. In release and profile the fallbacks compile to `''`, are tree-shaken out, and `Env.validate()` throws as it did before. `--dart-define` always overrides. Both values are public by design, so embedding them leaks nothing; the database password and the `service_role` key must still never appear in a client build. **Verified against real builds**: the release APK contains neither the project ref nor the publishable key in any of its three `libapp.so` AOT snapshots, while the debug APK contains both in `kernel_blob.bin`. |
| D7 | **Arabic-first, RTL by default.** The product is معاين, the users are Egyptian car buyers, and every string a user reads — city names, findings, report sections — is Arabic. Retrofitting RTL after the fact means re-auditing every `Row`, `EdgeInsets`, alignment and directional icon on every screen, so the direction is decided once, up front. The locale is a Riverpod provider (`localeProvider`) rather than a constant in `app.dart`, so a language switcher becomes a provider invalidation rather than a restructure — and so behaviour tests can render in English without pointing finders at wording that is expected to change. Arabic is both the default *and* the fallback: a device set to a language Moaen does not ship gets Arabic, not English. LTR still works; English is a fully supported locale. |
| D8 | **No external UI designs exist; the app is built from the written brief.** The repository contains no mockups — no Figma reference in any tracked file, and the only images are Flutter's stock icon and a 68-byte launch placeholder. Rather than freeze that gap, the visual language is expressed as tokens (`AppSpacing`, `AppRadius`, `AppTheme`) so a design can be applied by editing one file instead of forty call sites, and so literal drift between screens is impossible. If designs arrive later, the tokens are the seam they slot into. |
| D9 | **`reference_no` is server-assigned and enforced by a trigger, not a column revoke.** A buyer needs something to read out over the phone — `MN-1001` — and the number must not be forgeable, because it is what an inspector and a buyer match on. Migration 0004 adds a `bigint` from a sequence starting at 1000 plus a `BEFORE INSERT OR UPDATE` trigger. The first instinct, `revoke update (reference_no)`, does not work: **Postgres column privileges are additive**, so a table-level `grant select, insert, update` leaves the client able to rewrite the column no matter what is revoked. The trigger overwrites the value on insert and *restores* the stored value on update. Restoring rather than raising is deliberate: raising would break an unrelated field update on the same row (a phone-number correction, say) with an error about a number the user never touched. *Verified live: four assertions, asserting restored values rather than rejections.* |
| D10 | **`client_notes` is separate from `inspection_reports.notes`.** The brief has one "notes" field; there are two distinct things — what the buyer tells the inspector before the visit, and what the inspector finds after it. Conflating them loses the buyer's instructions the moment a report exists. Bounded at 1000 characters, and the create form counts as you type rather than rejecting on submit, so a buyer over the limit finds out while they can still cut something. |
| D11 | **The pricing breakdown is display-only.** `price` is one column and D2 forbids a quotes table, so `CostEstimate` presents a single number rather than persisted line items. The base fee (`baseInspectionFee = 500`) is a placeholder constant in exactly one place, pending a real pricing source. Both the create form and the dashboard derive their split from that one constant, so the number a buyer approved and the number they later see cannot disagree. Every total is labelled as an estimate: a total shown without that reads as a charge that has already happened, when it is a budget the buyer stated. |
| D12 | **Migrations are applied by `tool/apply_migration.dart`.** `supabase db push` requires `supabase link` (not linked), `psql` is not on PATH, and `supabase db reset` needs Docker. The script runs each file in one transaction via the Dart `postgres` driver, so a failure rolls back rather than leaving a half-applied schema. It depends on `tool/sql_statement_splitter.dart`, because the driver has no simple-query mode. |
| D13 | **The dashboard leads with the buyer's *most recent* request, not their most *urgent* one.** The obvious rule — filter to open requests — is wrong for this product. The instant an inspection completes, a buyer who filtered to open would be told they have no active request and be offered to book another, and the report they paid for and travelled for would be unreachable from the screen they open first. Cancelled requests are shown for the same honesty reason. Ranking an open request above a completed one was also rejected: a buyer realistically has one live request, and an invented priority would be a product decision smuggled into a query. The card title is status-aware, because a finished report labelled "your active request" is still telling the buyer the wrong thing. |
| D14 | **`AuthFailure` carries a reason, not a message.** It previously held an English sentence, which the sign-in banner rendered verbatim — so an Arabic build showed an English error, and nothing could be asserted about a failure except that *some* banner appeared. The repository now maps a server response to an `AuthFailureReason` and the presentation layer resolves that to a localized string. Three things follow. The repository stays free of the wording. The exact reason is a value a test can assert on and a log can record. And a *configuration* fault is distinguishable from a user error: `email_provider_disabled` is an operator mistake that no retry can clear, and presenting it as "Something went wrong. Please try again." is what made B4 look like a client bug for a day. `AuthFailure.detail` keeps the server's own wording for the log and is unreachable from the UI. The mapping matches on `AuthException.code` first — the stable contract — and falls back to message text, because GoTrue has renamed these strings across versions and an app pointed at an older server should still recognise `invalid login credentials` rather than degrade to a generic error. |
| D15 | **The job board read takes no user id; the inspector's own jobs read takes it, and the difference is the point.** `listBoard()` takes no parameter because the board RLS policy already scopes to `pending` rows in the caller's `location_city` — a parameter that was accepted and then ignored would read as though the caller decides whose board this is. `listForInspector(profile.id)` passes the id because the participant RLS policy cannot tell which *side* of a request the caller was: an inspector who also buys cars holds both roles, and a row where they are the buyer must not appear in their jobs list. The narrowing cannot be abused to read a stranger's jobs — RLS still refuses any row the caller has no part in. |
| D16 | **A status write that matches no row is read as a race, not guessed at.** Each transition updates then `.select().single()`, so a zero-row update (the loser of a claim, a request cancelled mid-read) surfaces as PGRST116 instead of silently succeeding. Accept maps it to "another inspector just took this request"; start/complete map it to "no longer in that state". The trigger stays the authority on legality: a page that offers the wrong action can still never move a request illegally — the database refuses, and the page just has to say why. |

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
| P5 | ~~Job board, request creation, report entry.~~ **Mostly done** — the client flow (create, dashboard tracker, list, detail) and the inspector flow (city-scoped job board, my jobs, profile, accept → start → complete) are built and tested. Still open: **report entry** — the inspector's report form and its media upload. | The `enforce_inspection_transition` trigger makes every status move the UI already performs irreversible and properly ordered; report entry is next because it is the inspector's one remaining screen. |
| P6 | ~~Arabic UI and RTL.~~ **done** — `flutter_localizations` + ARB (`lib/l10n/arb/app_{en,ar}.arb`), Arabic default and fallback, `Directionality` resolved by `MaterialApp` and asserted in `test/core/localization_test.dart`. Android launcher label localised via `values/strings.xml` and `values-ar/strings.xml`. |
| P7 | Notifications on status change. | No push provider selected. |
| P8 | Inspector payouts. | Follows the D1 escrow outcome. |
| P9 | Re-enable email confirmation for production. | Disabled for Phase 1 testing; **restore before any real launch**, since a confirmed address is the only thing standing between a typo and an account takeover. Independent of B4: the provider toggle is off *now*, and autoconfirm is a separate switch to restore at launch. |
| P10 | Normalise `city` to a reference table. | Awaits a second consumer (A5/A2). |
| P11 | **Release signing is unverified.** `flutter build apk --release` with no `key.properties` falls back to debug keys. A real keystore is required before distribution, and the build will look successful right up until it matters. |
| P12 | **No screen has been seen on a real device** (B3). The RTL work is asserted from laid-out geometry rather than from a screenshot, which catches a number on the wrong edge but cannot catch a font that renders Arabic as boxes. | Needs an emulator. |
| P13 | **Inspection write-failure messages are English, shown verbatim.** The buyer's cancel and the new inspector transitions surface `InspectionFailure.message` directly, so an Arabic build shows an English sentence on a write failure — the exact gap D14 closed for auth. It was deliberately left that way for the inspector work: fixing it properly is the D14 move again (a reason enum resolved through the ARB), and doing that during the flow build would have churned every existing client-flow assertion for no behaviour. | Do the D14 treatment: `InspectionFailureReason` + an ARB mapping, replacing the message strings in the repository and the snackbar call sites. Safe whenever, since it changes wording, not behaviour. |

---

## Milestones

| M | Deliverable | Pass condition | State |
|---|---|---|---|
| **M0** | Toolchain | `flutter --version` reports 3.47.5 / Dart 3.13.4 | **met** |
| **M1** | Scaffold | `flutter analyze` 0 issues; `flutter test` green; `flutter build apk --debug` produces an APK | **met** — debug APK 229.6 MB (94 MB of it is the uncompressed debug snapshot) |
| **M2** | Schema | Migrations apply cleanly; 5 tables, FKs, PKs, transition and role-guard triggers present | **met** — applied and inspected in the catalog |
| **M3** | RLS | Cross-tenant reads return 0 rows; city scoping holds; forged `released` payment denied | **met** — 28/28 live |
| **M4** | App wiring | Logger, sign-in and router-guard tests pass | **met** — 157 unit/widget + 28 RLS + 4 live auth |
| **M5** | Smoke | Boots on an emulator, signs in, reaches the role screen, writes a log file | **blocked by B3** — the sign-in half is now proven against live GoTrue, so only the on-device part is outstanding |
| **M6** | Client request flow | Dashboard, create form, list and detail render in both locales; create/cancel reach the database | **met** — but see B3: it has never run on a device |
| **M7** | Inspector flow | Job board (city-scoped), my jobs, profile tab, and accept → start → complete all render in both locales with the trigger's transitions enforced and the claim race reported | **met** — 21 new widget tests (15 flow + 6 Arabic-RTL geometry) riding on the live RLS proof; still never on a device (B3) |

## Running it

```powershell
# 1. database — the password must be percent-encoded; note the region and port.
$env:MOAEN_DB_URL = "postgresql://postgres.ybglobvcqgkfclvkjkri:<pw>@aws-0-eu-west-2.pooler.supabase.com:5432/postgres?sslmode=require"
flutter test test\integration\rls_policies_test.dart

# 2. live auth — same credential. Signs up through real GoTrue, then cleans up.
flutter test test\integration\auth_live_test.dart

# 3. apply a migration — the only working route to the live DB on this machine (D12)
dart run tool\apply_migration.dart supabase\migrations\000N.sql

# 4. diagnose auth without a device — the symptom in one command
dart run tool\auth_probe.dart

# 5. prove the signup trigger populates public.users (rolls back, leaves no account)
dart run tool\diagnose_signup_trigger.dart

# 6. remove any throwaway account a probe left behind
dart run tool\cleanup_probe_accounts.dart

# 7. client — no flags needed
flutter pub get
flutter run
flutter test
```

`flutter test` on its own reports 157 passing and 31 skipped: the RLS and live-auth
suites skip themselves when `MOAEN_DB_URL` is absent, so a developer with no database
credential still gets a useful signal. A credential that is *present but wrong* is
not skipped — it fails loudly. With the credential every one of the 188 runs
(157 unit/widget + 28 RLS + 4 live auth).

The live auth suite needs the gate for a stronger reason than the RLS one: it reaches
the network as well as the database, so without it a bare `flutter test` would make
real sign-up attempts — and against a healthy project, would create real accounts.

A bare `flutter run` is enough (D6): debug builds fall back to the development
project. To point a build somewhere else, override with `--dart-define` or
`--dart-define-from-file=tool\dart_defines.local.json`. The boot log records
which one applied as `config=dev-fallback|dart-define`, so a log file always
states the backend the app actually reached.

### Traps in the widget tests

Recorded because each one cost a debugging cycle, and none of them announce
themselves:

- **A file log is not a diagnostic.** `AppLogger` wrote only to the device, so
  `adb logcat` showed Flutter's IME and inset events and none of the app's
  errors — which is exactly what "there was no error" also looks like. The
  symptom was reported as a missing exception, and the exception was there. A
  debug build now tees to the console. If a log is ever the only record again,
  check that it is somewhere you can read while reacting to it.
- **`String.replaceAll` does not expand a group reference in the replacement.**
  `replaceAll(p, r'"$1":"<redacted>"')` emits the literal `$1`; the `replaceAllMapped`
  form is the one that substitutes the group. This is nastier than an ordinary
  bug, because the token *is* hidden either way — the output just relabels the
  field it redacted, so a transcript looks correct and correct-looking while
  naming the wrong key. Found by reading the probe's own output, not by a test.
- **`GET /auth/v1/settings` is a catalogue, not a report.** It lists every
  provider Supabase supports — email, apple, workos, kakao and the rest —
  whether or not the project has enabled any of them. Reading `external.email`
  there as "email login is on" is wrong, and it is what hid B4. The
  `mailer_autoconfirm` field *is* real config. To learn whether a provider is
  enabled, ask the endpoint that uses it.
- **The default test surface is 800×600 and a `ListView` only builds what is near
  the viewport.** A submit button below the fold is not merely invisible — it is
  absent from the tree, so `find` reports zero candidates and the failure reads as
  "no such widget" rather than "off screen". The inspection tests set a tall
  `tester.view.physicalSize` in one `_pump` helper.
- **A `Row` hands non-flex children unbounded main-axis constraints.** A `Column`
  holding a label therefore takes the label's full intrinsic width, which
  overflows its quarter-slot. The English labels fit; the Arabic ones are longer.
  This was a real 23-pixel overflow on the dashboard's progress track, found only
  because a test rendered it in Arabic — the exact class of bug that reaches
  production when the team reads the app in English.
- **`Spacer()` beside a long label overflows the row on a narrow screen.** The
  request card put the reference against `Spacer()` and the status chip; under
  English the "Awaiting inspector" chip — which only a *pending* row shows, and
  which none of the buyer screens ever rendered — was wider than the space the
  reference left it, painting 14 px off the edge at 420 dp. The reference now
  lives in an `Expanded` with an ellipsis, so the label can shrink and the chip
  stays whole at any phone width. Found by the inspector RTL test rendering a
  *pending* row in English; the Arabic test passed because the label is shorter.
  The buyer screens would have shipped this bug unreported.
- **`AppLocalizations.of(context)` returns null for a `MaterialApp`'s own
  context,** because `Localizations` is installed *inside* `MaterialApp`. Read it
  from a page's context.
- **Do not hard-code Arabic literals in tests.** Diacritics are lost easily —
  "منتهٍ" without its tanween is a different string — and a literal is a second
  copy of the ARB that goes stale silently. `rtl_layout_test.dart` reads expected
  strings from `AppLocalizations` and asserts "is Arabic" against the script range
  rather than against a phrase.
- **A test router needs route *names*, not just paths,** if the pages under test
  navigate with `pushNamed`. Without them the first tap fails inside go_router with
  `unknown route name`, which points nowhere near the cause.
- **`.in(...)` cannot be spelled on a `PostgrestFilterBuilder`** — `in` is a
  keyword. The method is `inFilter`.
- **Never type an Arabic string in a PowerShell assertion.** The console renders
  it as `??????` and the comparison fails for a reason that has nothing to do with
  the code. Read the value from the file instead.

`tool/dart_defines.local.json` holds the project URL and the publishable key,
both public by design, and is optional since D6. It stays gitignored as a matter
of habit so that a credential that is *not* public — a database password — can
never be committed alongside them. It is named to avoid colliding with
`.env.local`, which the Supabase CLI reads as dotenv while
`--dart-define-from-file` requires JSON — the two formats are not compatible.
