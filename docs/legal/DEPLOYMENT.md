# Terms consent: deployment and rollback

Everything ships **switched off**. While `backend/src/legal.js` has `TERMS_VERSION: null`:
- `/register` records nothing (an `accept_terms` value is ignored);
- `GET /license` never asks anyone and never queries `terms_acceptances`;
- `POST /api/account/accept-terms` answers 409.

The app's consent block still appears on the register screen (an unticked box gating Create Account) and its links point to `/terms`, `/acceptable-use` and `/privacy`. **So do not release an app build with this change before the legal pages are live.**

## Prerequisites (none can be skipped)

1. The business decisions in `LEGAL_DECISIONS_PENDING.md` have been made, and the `[[PENDING]]` markers filled in.
2. A licensed advocate has reviewed and approved the final text (`ADVOCATE_REVIEW_CHECKLIST.md`).
3. The "DRAFT. Not in force." banner has been removed from the three documents, and the version and effective date set in their headers.

## Release order

1. **Database:** run migration 072 on production **before** the backend deploy:
   ```
   cd backend
   npm run migrate:status
   npm run migrate:up
   ```
   It is safe to run while the flow is off; nothing writes to the new table until a version is set.
2. **Set the version:** in `backend/src/legal.js`, set `TERMS_VERSION` to the version printed in the approved `TERMS_OF_SERVICE.md` header (e.g. `'2026-11-01'`, max 20 characters).
3. **Merge and deploy** the backend and landing site (CI builds `landingPage` into `backend/public`). Check that https://vittam.vengurlatech.com/terms, `/acceptable-use` and `/ordering-terms` load and show the approved text. The order and store pages now show the notice.
4. **Release the app** (Android + Windows) built from the same branch. On next open, owners on the new build see the full-page consent screen; staff never do.
5. **Distribution pages:** add the Terms URL to the Google Play listing (and any Windows download page).
6. **Enforce at sign-up (later):** once builds without the consent block have aged out (check `users.app_version` on the admin dashboard), set `REQUIRE_TERMS_ACCEPT=true` in the backend `.env` and restart. Older builds then get "Please accept the Terms of Service to continue" at registration.
7. **Record the release:** note the version, effective date, commit hash and date of the advocate's approval in this file's log below.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `REQUIRE_TERMS_ACCEPT` | unset (false) | `true`: `/register` refuses a sign-up without `accept_terms: true`. Has no effect while `TERMS_VERSION` is null |

## Changing the terms later

- **Material change:** update the `.md` files, bump the version in the headers and in `TERMS_VERSION`, then deploy. Every owner is asked again on their next app open. Old acceptance rows are kept.
- **Minor change** (typo, contact details): edit the `.md` and deploy **without** bumping `TERMS_VERSION`. Nobody is asked again.

## Rollback

- **Stop asking immediately:** set `TERMS_VERSION` back to `null` and deploy. Nothing breaks: the app hides the screen as soon as `/license` stops returning `terms_required`, and existing acceptance rows are kept.
- **Remove the schema** (rarely needed): first set the version to null and deploy, then run `npm run migrate:down` (rolls back 072). **This deletes the acceptance evidence.** Export `SELECT * FROM terms_acceptances` before you do.
- **Landing pages:** revert the landingPage commit and redeploy. Do this together with the app links, or the document links in the app will 404.

## Checks after each release

- [ ] A new sign-up with the box ticked creates one `terms_acceptances` row (`source='register'`) and one `audit_logs` row `terms_accepted`.
- [ ] An existing owner sees the consent page; Agree adds a row (`source='reaccept'`) and the page doesn't return on the next resume.
- [ ] A staff login never sees the page.
- [ ] The document links in the app and the footer links on the site open the right pages.
- [ ] The online store and table QR pages show the notice next to Place Order, with a working link.

## Release log

| Version | Effective date | Advocate approval date | Commit | Released |
|---|---|---|---|---|
| | | | | |
