# Codebase audit: legal terms and consent

Audit of the repository against the T&C implementation brief (27 October 2026). Each statement is labelled **verified** (read in the code) or **assumption**.

## 1. What already existed

| Area | Finding | Source |
|---|---|---|
| Privacy Policy | Live at `/privacy`. Termly-style policy that includes a DPDP Act section. "Last updated: September 2026" | `landingPage/src/components/privacyPolicy.jsx` (verified) |
| Account deletion | `/delete-account` page + `POST /api/account/deletion/{request,confirm,cancel}`, authenticated by WhatsApp OTP | `backend/src/routes/account.js` (verified) |
| Trial | Created automatically at registration: `is_trial=1`, expires after 30 days, `grace_period_days=0`, `max_offline_days=1` | `backend/src/routes/auth.js` `/register` (verified) |
| Paid plans | Switched on by hand from the admin dashboard. Table defaults are `grace_period_days=5`, `max_offline_days=30`, and both can be changed for each business. No payment gateway, no auto-renewal | migration 009, `routes/admin.js` (verified) |
| Licence check | `GET /api/license` runs after login and on every app open or resume. It returns the subscription, entitlements and current role | `routes/license.js`, `frontend/lib/services/license_service.dart` (verified) |
| Audit log | `audit_logs` with a CHECK list of event types (last rebuilt in migration 037); writer is `audit.writeAudit`, which never throws | `backend/src/audit.js` (verified) |
| Sign-in IP logging | `login_logs` records the IP address and user agent at sign-in, and the Privacy Policy discloses it | migration 026 (verified) |
| Public ordering | `/store/<token>` (online store) and `/order/<qrToken>` (table QR), served as static HTML. UPI is paid directly to the shop; a typed transaction id is a "claimed" status, never verified | `backend/src/static/{store,order}/index.html`, migration 037 (verified) |
| Shop's own bill terms | The "Terms & Conditions" text in Bill Settings is the shop's own wording for its bills. **Unrelated to Vittam's terms and not touched** | `billSetupTerms*` l10n keys, `billSettings.js` (verified) |

## 2. What was missing

- No Terms of Service, Acceptable Use Policy or Customer Ordering Terms, and no `/terms` route or footer link (verified).
- No consent at sign-up: no checkbox on `register_screen.dart`, and `/register` recorded nothing (verified).
- No record of acceptance anywhere in the schema (verified).
- No notice on the ordering pages (verified).

## 3. Unsafe or inconsistent with the existing wording

1. **Deletion is scheduled but never carried out automatically.** `deletion/confirm` writes `account_deletion_requests.scheduled_for = now + 30 days`. No job, cron or `setInterval` in `server.js` acts on it; the admin dashboard only *displays* pending requests (`routes/admin.js`). `audit.logAccountDeleted` says "by scheduled cleanup", but nothing calls it. Meanwhile the Privacy Policy says that after the 30-day window the account "and its business data are erased from our active systems". **Risk:** a published promise that depends on a manual step nobody is assigned to. (verified)
2. **No backups in the repository.** `docs/server-spec.html` §7: "There is no backup or disaster-recovery configuration in this repository — no backup script, no scheduled job, no snapshot policy, no restore runbook." The Privacy Policy says backup copies "age out on their normal rotation". Whether backups exist outside the repo, for example at the hosting provider, is unknown (**assumption: none verified**). The ToS draft therefore says "best-effort" only.
3. **The grace period is not one number.** Trials get 0 days; paid plans default to 5 but can be changed for each business. The ToS refers to "the grace period your plan allows" and gives no figure. (verified)
4. **Manual deletion is blocked by foreign keys.** `login_logs.user_id` and (new) `terms_acceptances.user_id` are `ON DELETE NO ACTION`, so whoever deletes an account by hand must remove those rows first, or delete the business (which cascades) before the users. That is the existing behaviour, and the new table follows it on purpose. (verified)
5. **Privacy Policy.** It needs one added line saying that the IP address and time are recorded when terms are accepted. **Not edited.** It waits for the advocate (see the checklist, Q4). (verified)

## 4. Files and database objects changed (branch `feature/terms-consent`)

**Database**
- `backend/src/migrations/072_add_terms_acceptances.sql` (+ `_rollback.sql`): new insert-only table `terms_acceptances` (`user_id`, `business_id`, `terms_version`, `source` ∈ {register, reaccept}, `ip_address`, `accepted_at`), unique on `(user_id, terms_version)`; `CK_audit_logs_event_type` rebuilt with `terms_accepted`.

**Backend**
- `backend/src/legal.js` (new): `TERMS_VERSION = null`. The single switch; null means the flow is off.
- `backend/src/routes/auth.js`: `/register` takes `accept_terms: true`, records the acceptance and the audit row inside the registration transaction; `REQUIRE_TERMS_ACCEPT=true` makes acceptance mandatory.
- `backend/src/routes/license.js`: returns `terms_version` and `terms_required` (owners only). It queries `terms_acceptances` only when a version is set.
- `backend/src/routes/account.js`: `POST /api/account/accept-terms` (JWT; owner only; server-side version check; idempotent).
- `backend/src/audit.js`: `logTermsAccepted`.
- `backend/src/static/_shared/menu-list.js`, `static/order/index.html`, `static/store/index.html`: Ordering Terms notice by the Place Order button.
- `backend/tests/routes/terms.test.js` (new), plus off-state cases in `license.test.js` and `auth.test.js`.

**Flutter**
- `frontend/lib/widgets/terms_consent.dart` (new): consent block, a single unticked checkbox: "I have read and agree to the Terms of Service, Acceptable Use Policy and Privacy Policy", with each name linking to its page.
- `frontend/lib/screens/terms_accept_screen.dart` (new): full-page re-acceptance for existing owners (Agree / Log out; can't be backed out of).
- `frontend/lib/screens/register_screen.dart`: consent block above Create Account; the button stays disabled until the box is ticked.
- `frontend/lib/screens/main_shell.dart`: shows the screen when `terms_required` is set (on startup and on resume).
- `frontend/lib/services/license_service.dart`, `frontend/lib/api.dart`, `frontend/lib/screens/settings_screen.dart` (Terms and AUP links), `frontend/lib/l10n/app_{en,mr}.arb` (English text in both, as the terms are English-only).
- `frontend/test/widgets/terms_consent_test.dart` (new).

**Landing site**
- `landingPage/src/components/LegalPage.jsx` (new): renders the `.md` files from `docs/legal/` with `marked` (new dependency).
- `landingPage/src/App.jsx`, `seo.js`, `components/Footer.jsx`, `index.css`, `vite.config.js`: routes `/terms`, `/acceptable-use`, `/ordering-terms`, plus their SEO entries and footer links.

## 5. Differences from the brief

- **`terms_required` comes from `GET /license`, not from the login and refresh responses.** The licence check already runs after every login and on every app open or resume, and the app already acts on its result. Refresh returns only an access token and runs silently in the background, so it is the wrong place to trigger a screen.
- **One version for the bundle** (ToS + AUP + Privacy Policy), not one per document. Split the versions if the documents ever need to change on separate schedules.
- **Sign-up sends a yes/no (`accept_terms: true`), not a version.** The app can't know the version before login. The server records its own `TERMS_VERSION`, and the document links always open the live (current) pages. Re-acceptance does echo the version, and a mismatch gets a 409.
- **The ordering pages record no acceptance per order.** The notice is shown but not logged. Add `terms_version` to `online_orders` if the advocate wants it recorded.
- **The copyright line was left unchanged** until the entity name is verified.

## 6. Assumptions needing confirmation

- No backups exist outside the repository (§3.2).
- The landing site deploys from CI into `backend/public` (gitignored), so the legal routes go live only when this branch is merged and deployed.
- Google Play listing: a Terms URL is to be added by hand after publication.
