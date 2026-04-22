# App Review Fix Playbook — Guideline 3.1.2(c) (Custom EULA)

This playbook is for resolving App Store rejection `3.1.2(c)` when using a **custom Terms of Use**.

## Current app-side state (already configured)

- In-app Terms URL: `https://practiquest.app/terms`
- In-app Privacy URL: `https://practiquest.app/privacy`
- Terms and Privacy links are shown in both purchase flows:
  - `ShopView`
  - `StoreView`

## Required App Store Connect metadata actions

1. Go to `Apps -> PractiQuest -> General -> App Information`.
2. In `General Information`, click `Edit` next to `License Agreement`.
3. Select `Apply a custom EULA to all chosen countries or regions`.
4. Paste your custom EULA text as plain text.
5. Select all countries/regions where the app is available.
6. Click `Done`, then `Save`.
7. Open `iOS App -> Prepare for Submission` (current version).
8. In the app **Description**, add this line at the end:

   `Terms of Use: https://practiquest.app/terms`

9. Confirm `Privacy Policy URL` is:

   `https://practiquest.app/privacy`

10. Resubmit and reply in the same rejection thread.

## App Review reply text (paste)

Thank you for the feedback.

We have now configured a custom EULA in App Store Connect under App Information -> License Agreement and applied it to our selected territories.

We also updated the app description metadata to include:
Terms of Use: https://practiquest.app/terms

The in-app subscription flow already includes functional links to both Terms of Use and Privacy Policy.

## Optional App Review Notes text

Custom EULA is configured in App Information -> License Agreement.
Terms URL in metadata: https://practiquest.app/terms
Privacy URL in metadata: https://practiquest.app/privacy
In-app purchase flow includes functional Terms and Privacy links.

## Final pre-submit validation

- [ ] Custom EULA saved in App Information.
- [ ] Description includes `Terms of Use: https://practiquest.app/terms`.
- [ ] Privacy Policy URL is set and functional.
- [ ] Latest build selected (only if needed).
- [ ] Reply sent in the existing App Review thread.
