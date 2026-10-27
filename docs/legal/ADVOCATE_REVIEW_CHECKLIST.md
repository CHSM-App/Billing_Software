# Advocate review checklist: Vittam legal documents

**For:** the licensed Indian advocate reviewing Vittam's legal documents before publication.
**Documents under review:** `TERMS_OF_SERVICE.md`, `ACCEPTABLE_USE_POLICY.md`, `CUSTOMER_ORDERING_TERMS.md`, and, for consistency, the existing Privacy Policy at https://vittam.vengurlatech.com/privacy.
**Prepared:** 27 October 2026. The drafts were prepared with software assistance and have not been legally reviewed. Every `[[PENDING: …]]` marker in them is either a business decision (`LEGAL_DECISIONS_PENDING.md`) or one of the questions below.

## Product summary (as verified in the code)

Vittam is billing and business-management software for Indian retailers and restaurants. It comes as an Android app, a Windows desktop app and a web version, backed by our own servers.

- **Customers.** Businesses (B2B). The Owner registers and agrees for the business; Staff log in under it.
- **Trial.** A 30-day free trial starts at registration and expires by itself. No payment details are taken, and nothing is charged automatically.
- **Paid plans.** Annual, ₹3,499 to ₹10,000. Customers pay us directly and we switch the plan on by hand. There is no payment gateway and no auto-renewal.
- **Tax features.** GST invoices, HSN codes, round-off, and GSTR-1 / GSTR-3B summaries and exports.
- **Offline use.** Billing works offline, with a cap on how long the app can stay offline before it must check its licence.
- **Online store and table QR ordering.** These are public web pages where a shop's customers order, verify their phone by WhatsApp OTP, and may pay by UPI **directly to the shop**. We never handle the money.
- **Messaging.** WhatsApp is used for bills and OTPs; push notifications go through Firebase.
- **Consent.** The consent flow is built but switched off. Owners will tick one unticked box beside the sentence "I have read and agree to the Terms of Service, Acceptable Use Policy and Privacy Policy", where each document name links to the full text. The server records the user, the bundle version, a timestamp, the IP address and the source (sign-up or re-acceptance) in an insert-only table, plus an audit-log entry. Existing owners get a full-page re-acceptance screen when the version changes. Staff are not asked.

## Questions

### Parties and formation
1. **Contracting entity.** Confirm the exact name of the entity, the details that must appear (CIN, registered office), and its authority to contract.
2. **Electronic contract formation.** Under the IT Act, 2000 (s.10A) and the Indian Contract Act, 1872, is the flow above (one unticked box covering all three linked documents, then Create Account / Agree, logged on the server) enough to form a binding contract? Should we record anything else?
3. **Who must accept.** Is it enough that the Owner accepts for the business, or must Staff also accept something (for example the AUP)?
4. **Keeping the acceptance record.** May we, or must we, keep the acceptance record (including the IP address) after an account is deleted, and for how long? Is logging the IP at acceptance proportionate? It is already logged at sign-in and disclosed in the Privacy Policy.

### Liability and risk allocation (ToS §§10, 13, 14, 16, 17)
5. **Liability cap.** Is a cap of the fees paid in the preceding 12 months enforceable for B2B customers under Indian law? Is 12 months the right period?
6. **Trial users.** They pay nothing, so the cap would be ₹0. Should there be a fixed amount instead?
7. **Exceptions to the cap.** Confirm the list (fraud, wilful misconduct, gross negligence, death or personal injury, non-excludable liability) and add anything mandatory.
8. **GST disclaimer.** Is the balance in §10 right: the owner checks outputs and files returns, but we are not excused for our own software defects where the law forbids it? Any risk in how we describe ourselves (not a tax adviser, not a GST Suvidha Provider)?
9. **Warranty disclaimer.** Is the capitalised disclaimer in §14 appropriate in Indian practice, and does it need changes for B2B?
10. **Indemnity.** Are the scope (third-party claims from the owner's content, sales, data misuse and AUP breaches) and the procedure in §17 appropriate?
11. **Backups.** With best-effort backups and no guarantee (§13.3), is this wording acceptable? Does it conflict with the Privacy Policy's statement that backups "age out on their normal rotation"?

### Disputes (ToS §20)
12. **Courts or arbitration.** For a B2B SaaS with small annual fees, which do you recommend, and why?
13. **Sindhudurg.** Can the courts at Sindhudurg, Maharashtra validly be given exclusive jurisdiction? That depends on a real connection, such as the registered office or the place the contract is made. If we choose arbitration, which seat?

### Consumer protection and e-commerce (ToS §11, Ordering Terms)
14. **E-commerce status.** Customers of our business users order through Vittam-hosted public pages. Is Vengurla Tech an "e-commerce entity" (or any other regulated role) under the Consumer Protection Act, 2019 and the Consumer Protection (E-Commerce) Rules, 2020? If so, what must the pages show, and what duties follow (for example a grievance officer, or seller details)?
15. **The ordering notice.** Is the notice next to "Place Order" adequate as written? ("By placing this order, you agree to the shop's applicable ordering policies and Vittam's Customer Ordering Terms.") Shops currently have no place to publish their own policies; see `LEGAL_DECISIONS_PENDING.md` #18.
16. Is anything in the Ordering Terms at risk of being read as waiving statutory consumer rights?

### Intermediary and grievance obligations
17. **Grievance officer.** Do the IT Act, 2000 (s.79) and the IT (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021 apply to us, given that we host shop content on public pages? Do we need a designated Grievance Officer and published timelines? Are 48 hours to acknowledge and 30 days to resolve (taken from the Privacy Policy) compliant?

### Data protection
18. **DPDP compliance.** Under the Digital Personal Data Protection Act, 2023 and the DPDP Rules, 2025, are the roles in ToS §9 correctly described? There, the business decides what customer and staff data to collect, and we process it on its instructions.
19. **Phased commencement.** Given the phased commencement of the DPDP Rules, which obligations apply on our planned effective date? Is the Privacy Policy compliant for that date?
20. **Retention and deletion.** How long must data be kept after deletion, for example under GST record-keeping rules and for limitation periods? Today, deletion is scheduled 30 days after a request and then carried out by hand; see `CODEBASE_AUDIT.md`.

### Commercial terms
21. **Refunds.** Case-by-case review is the preference. What minimum process or statutory rights must the refund section state?
22. **Suspension and termination.** Are the grounds, notice and review steps in ToS §15 and AUP §2 fair and enforceable? Is immediate suspension for security or illegality acceptable?
23. **Changes to the Terms.** Is the process in §19 sound: material changes are re-accepted in the app, and continued use is not treated as agreement?

### Distribution and notices
24. **Trademark and copyright.** What wording is correct before "Vittam" is registered?
25. **Mandatory disclosures.** Do Google Play or the Windows distribution channel require anything further? (Google Play needs a privacy policy URL, which we already have, and may expect a Terms URL.)

## What the advocate will receive
- The three drafts plus the current Privacy Policy.
- `LEGAL_DECISIONS_PENDING.md`, so the business decisions are visible.
- `CODEBASE_AUDIT.md`, which records where the product's actual behaviour differs from the existing policy wording.
