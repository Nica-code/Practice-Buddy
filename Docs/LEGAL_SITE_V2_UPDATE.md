# PractiQuest 2.0 — Legal and Support Site Update

Status: required before App Store submission. This is an implementation
requirements document, not legal advice. Final language should be reviewed by
qualified counsel for the countries in which PractiQuest is offered.

## Why the live pages must change

The public pages at the following URLs still describe the v1 product:

- <https://practiquest.app/privacy>
- <https://practiquest.app/terms>
- <https://practiquest.app/support>

They contain obsolete Google Play and generic advertising/analytics language
and do not describe PractiQuest 2.0 identity, social, moderation, age, messaging,
purchase, or deletion behavior. They therefore conflict with the v2 binary and
the prepared App Store privacy answers.

The website source is in a separate repository:

`/Users/nica/Downloads/Code/Apps/PractiQuest-Website`

That repository is not currently inside this coding workspace's writable root.
The pages must be updated in that repository, reviewed, deployed, and verified
at the public URLs before submission.

## Locked product facts

All public legal/support copy must match these implemented facts:

- PractiQuest is distributed through Apple's App Store.
- Core private practice is available through an anonymous Firebase account.
- Permanent accounts collect a display name, unique handle, private date of
  birth, instrument, privacy choice, Firebase user ID, and an email where the
  selected sign-in provider supplies one.
- Date of birth is private and is used to derive age-based access.
- Users under 13 are limited to private practice and cannot access social
  features.
- Teen accounts are private and cannot publish to Public Explore.
- Public Explore is disabled for the initial v2 release.
- Optional profile photos are uploaded only after the user chooses one.
- Practice audio and run-through recordings stay on the device and are not
  uploaded by PractiQuest.
- Accepted friends can exchange direct text messages.
- Generated Practice Moments contain only app-owned art and preset structured
  fields. They contain no user photos, audio, video, captions, comments,
  practice notes, or reflections.
- Moments expire after 24 hours and have no archive.
- Users can follow, request, accept, decline, mute, block, remove, and report as
  permitted by relationship and age state.
- Coarse online/last-practice activity is optional and can be disabled.
- PractiQuest stores practice sessions, goals, progression, quests, duels,
  inventory, avatar/studio layouts, relationship state, notification
  preferences, entitlements, and safety/moderation state.
- APNs and Firebase Cloud Messaging identifiers support notifications.
- Firebase App Check protects supported client operations.
- Product analytics are bounded, content-free counters stored locally; the app
  does not upload journal text, messages, audio, names, handles, dates of birth,
  bios, or raw search terms as analytics events.
- PractiQuest contains no advertising and does not track people across other
  companies' apps or websites.
- PractiQuest Pro is an auto-renewable subscription. Existing eligible Ad-Free
  monthly and Pro Lifetime purchases remain recognized as Pro.
- Account deletion is available in Settings.

## Privacy policy requirements

The replacement privacy policy must clearly cover:

### Controller and contact

- Identify the developer/data controller.
- Publish a monitored privacy email address.
- State the policy effective date and how material changes are communicated.
- Remove references to Google Play unless an Android version actually exists
  and shares this same policy.

### Data collected

Describe the following categories and distinguish required from optional data:

- account and identity: name, handle, email, provider identity, Firebase UID,
  private date of birth/derived age band, instrument, and privacy choice;
- optional public/profile content: photo and bio;
- private practice data: sessions, tasks, goals, reflections, notes, tool
  results, verification state, and on-device recordings;
- progression/economy: XP, quests, league/duel state, tokens, inventory,
  purchases, avatar loadout, and studio arrangements;
- social data: friendships, follows, requests, messages, Moments, reactions,
  blocks, mutes, reports, and coarse activity/presence;
- technical data: device/app version, notification token, App Check integrity
  information, server logs, security events, and diagnostic information
  produced by integrated Firebase services.

Explicitly state that microphone input is processed for tuner, rhythm,
intonation, run-through, and duel functionality, and that PractiQuest does not
upload practice audio.

### Purposes and lawful bases

Explain that data is used to:

- provide authentication, practice, synchronization, progression, social,
  notification, purchase, restoration, support, moderation, fraud prevention,
  security, and account-deletion functionality;
- enforce age, privacy, relationship, block, and entitlement rules;
- maintain the service and meet legal obligations.

Counsel must select and document the applicable lawful bases for each offered
region rather than using one generic basis for every purpose.

### Service providers

Identify the relevant categories of processors and link to their policies:

- Apple, including StoreKit, APNs, Sign in with Apple, and App Store services;
- Google Firebase, including Authentication, Firestore, Cloud Functions,
  Messaging, Storage, Hosting, and App Check where used.

Do not list advertising networks, ad-measurement providers, or analytics
providers that are absent from the released binary.

### Sharing and disclosure

State:

- which public-profile fields appear in search;
- which fields are visible only to approved relationships;
- that accepted friends can see messages and permitted coarse activity;
- that generated Moments are shared only with their selected eligible audience;
- that information may be disclosed to processors, for safety/legal requests,
  or during a legitimate business transfer subject to applicable safeguards;
- that personal data is not sold and is not used for cross-company tracking.

### Retention and deletion

Document:

- user-controlled history retention;
- 24-hour Moment expiry and deletion of reactions/feed references;
- local recording deletion on discard and account/device-management limits;
- reasonable security, fraud, support, backup, and legal-retention exceptions;
- the in-app account-deletion path;
- what is deleted versus anonymized in shared message/moderation records;
- how a user can make an access, correction, portability, or deletion request.

Do not promise instantaneous deletion from every backup if that is not
operationally true.

### Children and teens

Replace the old blanket “not designed for under 13” statement with the actual
behavior:

- date of birth is collected privately for age gating;
- under-13 accounts receive private-practice functionality only;
- social feed, messaging, follows, Moments, public profile, and duels requiring
  social identity are unavailable to under-13 users;
- teen accounts are private and cannot publish publicly;
- include the parental contact and deletion process required by counsel for the
  offered territories.

The implementation is an age gate, not verified parental consent. Do not claim
COPPA/GDPR-K certification without a separate compliance review.

### Security and international transfers

Describe authentication, access rules, App Check, transport security, and
least-data public projections accurately without promising absolute security.
Document cross-border processing and applicable transfer safeguards.

### User privacy choices

Provide clear instructions for:

- edit profile and privacy;
- friend activity sharing;
- social visibility and relationships;
- blocked accounts;
- notification settings;
- history retention;
- sign out;
- account deletion;
- contacting privacy support.

Use this section as the target for App Store Connect's optional User Privacy
Choices URL if the site gains stable fragment URLs.

## Terms of use requirements

The v2 terms must add or update:

- eligibility, declared age, and age-based feature restrictions;
- anonymous versus permanent accounts and responsibility for account security;
- acceptable display names, handles, bios, messages, and social conduct;
- prohibited harassment, threats, impersonation, sexual content, exploitation,
  spam, fraud, illegal activity, and attempts to bypass age/privacy controls;
- license and responsibility for optional profile photos and user-entered
  content;
- generated Moment behavior, audience, reactions, and 24-hour expiry;
- moderation rights, reporting, blocking, content removal, suspension, and
  termination;
- no random/anonymous messaging and friends-only direct messages;
- fair-play requirements for verified practice, quests, duels, rewards, and
  tokens;
- virtual items having no cash value and being subject to entitlement rules;
- PractiQuest Pro subscription billing, renewal, cancellation through Apple,
  restoration, legacy entitlement recognition, and Apple's refund process;
- user responsibility for safe device use and volume levels while practicing;
- availability, service changes, backups, disclaimers, liability limits,
  indemnity, governing law, and dispute provisions selected by counsel;
- account deletion and the surviving provisions/records required for safety or
  law.

If Apple's standard EULA is used, say so accurately and link to it. If custom
terms supplement the standard EULA, make their relationship explicit.

## Support and moderation page requirements

The support page must provide:

- a monitored support contact and expected response window;
- a separate or clearly routed privacy contact;
- in-app paths for report profile, report Moment, report message, block, mute,
  remove friend/follower, and account deletion;
- a plain-language Community Standards summary;
- urgent-safety guidance that directs immediate danger to local emergency
  services without presenting PractiQuest as an emergency service;
- subscription management, cancellation, restoration, and purchase-support
  instructions for Apple's App Store;
- microphone, notification, Live Activity, Family Controls, and recording
  troubleshooting;
- data export and account-deletion help;
- supported languages and accessibility contact;
- current app name, bundle-facing terminology, and Apple-only platform links.

The moderation contact must be operational before review. Apple's user-generated
content rules require filtering, reporting, blocking, timely responses, and
published contact information; an unmonitored form or placeholder email is not
sufficient operational readiness.

## App Store consistency checklist

Before submission:

- [ ] Deploy the reviewed privacy, terms, and support pages.
- [ ] Confirm all three public URLs return HTTP 200 without a login.
- [ ] Confirm mobile layout, dark appearance, keyboard navigation, and readable
      text.
- [ ] Remove stale advertising, Google Play, and generic analytics claims.
- [ ] Confirm the privacy policy describes every App Store privacy data type.
- [ ] Confirm support publishes a monitored moderation contact.
- [ ] Confirm terms describe Apple subscription renewal/cancellation.
- [ ] Confirm under-13 and teen language matches implemented behavior.
- [ ] Confirm account deletion instructions match the in-app path.
- [ ] Confirm legal entity/contact/jurisdiction details with counsel.
- [ ] Re-run link checks from the exported IPA and App Store metadata.

## Source references

- Apple App Review Guidelines, especially 1.2, 1.5, 1.6, 3.1.2, and 5.1:
  <https://developer.apple.com/app-store/review/guidelines/>
- Apple App Privacy:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
- Apple age-rating values:
  <https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions>
- Firebase Apple-platform data disclosure:
  <https://firebase.google.com/docs/ios/app-store-data-collection>
