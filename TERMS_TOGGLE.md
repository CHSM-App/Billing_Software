# Terms & Conditions: on / off

Terms consent is controlled by three switches. Set all three together.

| # | File | On | Off |
|---|------|----|-----|
| 1 | `backend/src/legal.js` | `TERMS_VERSION: '2026-11-23'` (any version string, max 20 chars) | `TERMS_VERSION: null` |
| 2 | `frontend/lib/widgets/terms_consent.dart` | `kTermsConsentEnabled = true` | `kTermsConsentEnabled = false` |
| 3 | `landingPage/src/components/IosSignup.jsx` | `TERMS_CONSENT_ENABLED = true` | `TERMS_CONSENT_ENABLED = false` |

- Switch 1 makes the server record acceptances and show the "Agree or Log out" screen to existing owners.
- Switches 2 and 3 show or hide the checkbox on the sign-up forms. Sign-up happens before login, so the forms can't ask the server whether terms are on.

Optional: set the backend env var `REQUIRE_TERMS_ACCEPT=true` to make the server reject sign-ups that haven't accepted. Without it, only the forms enforce the checkbox.

## Enable

1. Make sure migration `backend/src/migrations/072_add_terms_acceptances.sql` has been applied.
2. Set the version in `legal.js`. Write the same value on the `Version:` line of `docs/legal/TERMS_OF_SERVICE.md`.
3. Set switches 2 and 3 to `true`.
4. Deploy the backend, then rebuild and release the app and the landing page.

Every existing owner is asked to accept on their next app open.

## Disable

Set `TERMS_VERSION: null` and set switches 2 and 3 to `false`, then deploy the backend and rebuild the app and landing page. Acceptances already recorded are kept.

## Changing the terms later

- **Material change:** bump `TERMS_VERSION`. Every owner is asked to accept again.
- **Typo or contact fix:** edit the documents only and leave the version alone. Nobody is asked again.

More detail: `docs/legal/DEPLOYMENT.md`.
