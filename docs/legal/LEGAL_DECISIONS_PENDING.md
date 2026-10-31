# Legal decisions pending: business owner

Business decisions that must be made **before** the Terms are sent for final advocate sign-off and published. Each one maps to `[[PENDING: …]]` markers in the drafts. Legal questions for the advocate are in `ADVOCATE_REVIEW_CHECKLIST.md`.

Status as of 27 October 2026. ✅ = decided, ⏳ = open.

## Company details

| # | Decision | Status | Where it's used |
|---|---|---|---|
| 1 | Exact registered name of the contracting company. The Privacy Policy already says "VENGURLA TECH PRIVATE LIMITED"; confirm it against the certificate of incorporation | ⏳ | ToS intro, Ordering Terms §1, copyright line |
| 2 | CIN and registered office address | ⏳ | ToS intro, §21, §22.5 |
| 3 | Grievance Officer: name, designation, phone | ⏳ | ToS §21 |
| 4 | Support email: support@vengurlatech.com | ✅ | everywhere |
| 5 | Copyright line. The site currently says "© 2026 Vittam". Change it to "© 2026 [verified company name]" once #1 is confirmed. **Left unchanged in the code for now.** | ⏳ | landingPage `Footer.jsx` |
| 6 | Trademark: is "Vittam" registered or applied for? Decides whether we can say "™" or "®", or only "Vittam is a trademark of…" | ⏳ | ToS §18 |

## Plans, money and refunds

| # | Decision | Status | Where |
|---|---|---|---|
| 7 | Billing frequency: annual | ✅ | ToS §5.3 |
| 8 | Price range: ₹3,499 to ₹10,000 per year | ✅ | ToS §6.1 |
| 9 | Full price list: plan names, price and what each includes (staff limit, mobile/desktop, online store, etc.) | ⏳ | ToS §5.4, §6.1 |
| 10 | Do quoted prices **include or exclude GST**? | ⏳ | ToS §6.2 |
| 11 | Price-change notice period (suggested: 30 days) | ⏳ | ToS §5.6 |
| 12 | **Grace period after expiry.** The code gives trials 0 days, and paid plans 5 days by default; the admin dashboard can change it for each business. Decide the rule to publish: "as shown in the app" (current draft), or a fixed number for all paid plans | ⏳ | ToS §6.4 |
| 13 | **Refund policy.** Preference is case-by-case review. Still to decide: who can ask, by when (e.g. within X days of payment), what is excluded, how quickly you reply, how quickly money is returned | ⏳ | ToS §7 |

## Data

| # | Decision | Status | Where |
|---|---|---|---|
| 14 | **Retention after a Subscription expires.** How long is an unpaid account's data kept before deletion? **Undecided. Don't pick 30, 90 or 180 days without an explicit decision.** | ⏳ | ToS §15.5 |
| 15 | **Backups.** The repository contains no backup configuration (see `CODEBASE_AUDIT.md`). Confirm with whoever runs the server: schedule, how long copies are kept, whether a restore has ever been tested. Until then, the ToS says "best-effort". Note that the Privacy Policy already says backups "age out on their normal rotation", which assumes backups exist | ⏳ | ToS §13.3 |
| 16 | **Account deletion process.** The app schedules deletion 30 days after the request, but nothing deletes automatically; it's a manual step from the admin dashboard. Decide who carries it out and how, and whether backups are covered. The Privacy Policy already promises erasure after the 30-day window | ⏳ | ToS §15.6 |
| 17 | What a "full data export" contains, and how quickly support provides it | ⏳ | ToS §8.5 |

## Product and process

| # | Decision | Status | Where |
|---|---|---|---|
| 18 | **Shop ordering policies.** The notice says "the shop's applicable ordering policies", but shops have no place in Vittam to write one. Options: (a) keep the wording and rely on shops telling customers directly; (b) add a "store policy" field later and link it; (c) reword the notice | ⏳ | store / QR pages, Ordering Terms §4 |
| 19 | Response time for suspension reviews, refund replies and disputes (suggested: 7 working days) | ⏳ | ToS §7.2, §15.3, §20.2; AUP §3.2 |
| 20 | Terms language: English only | ✅ | ToS §22.7 |
| 21 | Preferred courts: Sindhudurg, Maharashtra (still needs advocate confirmation) | ✅ preference | ToS §20 |
| 22 | Courts vs arbitration: decide after reading the advocate's advice | ⏳ | ToS §20.3 |
| 23 | Effective date and version number of v1, set after approval | ⏳ | all three documents + `backend/src/legal.js` |
| 24 | Should existing owners be **blocked** until they accept (current build: yes, a full page with Agree or Log out), or get a grace window first? | ⏳ (built as blocking) | app `TermsAcceptScreen` |
