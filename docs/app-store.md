# Submitting to the App Store

Everything App Store Connect asks for, and where it lives. The listing's
words and screenshots are in `fastlane/` in the layout
[fastlane deliver](https://docs.fastlane.tools/actions/deliver/) reads, so
they can be pasted by hand or uploaded with `fastlane deliver` (not set up
here: it needs an App Store Connect API key, which never goes in this
repository).

## Before the first submission

1. **The server.** The Release build talks to `https://chatwithwork.com`,
   which must serve the server contract (`docs/server-contract.md`): the
   native layout, `/configurations/ios_v1.json`, and
   `/.well-known/apple-app-site-association`. In the Rails app's
   credentials, set `apple.team_id` (universal links and webcredentials)
   and `apple.push_key_id` and `apple.push_key` (an APNs auth key from
   Certificates, Identifiers & Profiles > Keys), then deploy.
2. **The App ID.** `com.chatwithwork.app`, with Push Notifications and
   Associated Domains. Automatic signing registers it from
   `ChatWithWork/Resources/ChatWithWork.entitlements` on the first archive
   with `-allowProvisioningUpdates`.
3. **The app record.** App Store Connect > Apps > New App: iOS, name
   "Chat with Work", primary language English (U.S.), bundle ID
   `com.chatwithwork.app`, SKU `chatwithwork-ios`, full access.
4. **The demo login** for App Review, on production: the 1Password item
   "App Review demo login" (vault chatwithwork) holds it, and the Rails
   app's `script/store/seed production review app-review@chatwithwork.com
   <password file>` makes it with synthetic content, past the first-run
   tour. It was first made on 2026-10-27. Run it again just before each
   submission: it rebuilds the demo's chats, so the morning brief reads as
   that day's and the Slack post waits again, and it takes back an
   earlier reviewer's yes to AI models, so the next one sees that question.

## Building and uploading

Pushing to main is enough: Xcode Cloud's "TestFlight" workflow archives
Release and uploads it to App Store Connect, where it goes to the Internal
Testing group (see the README's Releasing). To archive and upload by hand,
on the Mac mini or any Mac set up as below:

```sh
cp Config/Signing.xcconfig.example Config/Signing.xcconfig   # put the team ID in it
git tag v1.0.0
script/upload v1.0.0           # archive Release 1.0.0 (build 10000), sign, upload
script/upload build/ChatWithWork-1.0.0.xcarchive   # or upload an archive you have
```

`script/upload` exports with `xcodebuild -exportArchive` (`method`
`app-store-connect`, `destination` `upload`) and signs in with an App Store
Connect API key, so it works over SSH and never needs Xcode's Accounts. The
Internal group has access to every build, so the build reaches TestFlight
on its own after processing, about 15 minutes.

### Public TestFlight beta

Anybody can join the beta at https://testflight.apple.com/join/JYpuPjVn,
which chatwithwork.com links as "iPhone and iPad beta". It is the external
group "Public beta" (public link on, at most 1,000 testers, feedback on).

- **Beta information** (TestFlight > Test Information): the beta
  description, feedback email support@chatwithwork.com, the marketing and
  privacy policy URLs, and the Beta App Review contact and demo login (the
  same as App Review's, below; the password from 1Password).
- **New builds.** The Xcode Cloud workflow's "TestFlight External Testing"
  post-action adds every build to the group and submits it for Beta App
  Review. Apple reviews the first build of each version in about a day;
  later builds of the same version usually pass at once. Only one build of
  a version can wait for review at a time, so a build that finished while
  another waited needs submitting by hand once the first is through
  (TestFlight > the build > Submit for Review, or
  `POST /v1/betaAppReviewSubmissions` with the API key). Adding an external
  post-action makes Apple restrict editing the workflow to Admins and App
  Managers.
- **What to Test** for a build is its `betaBuildLocalizations` (en-US).
- The first submission, build 10004 (1.0.1), went to Beta App Review on
  2026-10-26; until it is approved, the link says the beta isn't accepting
  testers.

### Uploading with an API key

Xcode's Accounts don't work for this: over SSH the login keychain is
locked, so `xcodebuild` finds no account ("No Accounts"), and in the
desktop session Xcode's Apple Account sign-in keeps expiring ("App Store
Connect access ... is required"). The API key never expires.

- **The key.** A Team key from App Store Connect > Users and Access >
  Integrations > App Store Connect API, with the **Admin** role: exporting
  with `-allowProvisioningUpdates` uses Apple's cloud-managed distribution
  certificate, which API keys can use only as Admin. It lives in 1Password
  (vault chatwithwork, "App Store Connect API key (Mac mini uploads)"), with
  its key ID, issuer ID and the `.p8`. Never commit any of it: the
  repository is public.
- **On the Mac.** The `.p8` goes in
  `~/.appstoreconnect/private_keys/AuthKey_<key ID>.p8` (mode 600), and
  `~/.appstoreconnect/chatwithwork.env` sets `ASC_KEY_ID` and
  `ASC_ISSUER_ID`. The environment variables `ASC_KEY_ID`, `ASC_ISSUER_ID`
  and `ASC_KEY_PATH` override both.

### Signing without Xcode's Accounts

The archive is signed with an Apple Development identity before the
export re-signs it for distribution, and it has to be: an unsigned archive
loses its entitlements (push, associated domains) on export. Over SSH
codesign can't reach the identity in the locked login keychain
(`errSecInternalComponent`), so the Mac keeps one of its own in a keychain
just for building, `~/Library/Keychains/chatwithwork-build.keychain-db`,
whose password is in `~/.appstoreconnect/build-signing/keychain-password`
(mode 600). `script/archive` unlocks it and signs from it when both exist.
To set it up on another Mac:

1. Make a key and certificate request:
   `openssl genrsa -out dev.key 2048` and
   `openssl req -new -key dev.key -out dev.csr -subj "/CN=Chat with Work builds"`.
2. Create an Apple Development certificate from it, in Certificates,
   Identifiers & Profiles or with the API key (`POST /v1/certificates`,
   `certificateType` `DEVELOPMENT`).
3. Create the keychain with a random password, import both, and let
   codesign use the key without asking:
   ```sh
   security create-keychain -p "$pw" ~/Library/Keychains/chatwithwork-build.keychain-db
   security set-keychain-settings ~/Library/Keychains/chatwithwork-build.keychain-db
   security import dev.key -k <keychain> -t priv -f openssl -T /usr/bin/codesign
   security import dev.cer -k <keychain> -t cert -f x509
   security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pw" <keychain>
   security list-keychains -d user -s ~/Library/Keychains/login.keychain-db <keychain>
   ```
   Then delete `dev.key`.

`ITSAppUsesNonExemptEncryption` is `false` in `Info.plist`: the app uses
only the system's HTTPS, so no export compliance documents are needed.

## The listing

| Field | Where |
|---|---|
| Name, subtitle, description, keywords, promotional text, What's New | `fastlane/metadata/en-US/` |
| Support URL, marketing URL, privacy policy URL | `fastlane/metadata/en-US/*_url.txt` |
| Category | Business, then Productivity (`fastlane/metadata/*_category.txt`) |
| Copyright | `fastlane/metadata/copyright.txt` |
| Screenshots | `fastlane/screenshots/en-US/`: 6.9" (1320 x 2868), 6.5" (1284 x 2778), 6.3" (1206 x 2622), iPad 13" (2064 x 2752) |
| App Review contact, demo login, notes | `fastlane/metadata/review_information/` (the password is in 1Password, never here) |

Screenshots come from the app itself: `ChatWithWorkUITests/StoreScreenshotTests`
signs in to a server holding a synthetic organization (Northwind Studio,
which crmne/films' `chatwithwork/store-screenshots/capture/seed` makes in a
checkout of the Rails app, its clock set to a Monday at 9:41), walks the
sidebar shell in dark mode with the status bar at 9:41, and keeps each
screen as a test attachment. `script/screenshots` runs it on the
three simulators and exports the raw screens. They're framed, one headline
each, in crmne/films (`chatwithwork/store-screenshots`, which also makes
every other store's images), and the framed images land here. The headlines,
the words of the listing, and what backs each claim are in the Rails app's
`docs/marketing/marketplaces.md`.

## App Privacy

Answers for App Store Connect > App Privacy, true to what the app and the
server keep (the privacy policy is the reference). No data is used for
tracking, and nothing is shared with data brokers or advertisers.

| Data type | Collected | Linked to the person | Purpose | What it is |
|---|---|---|---|---|
| Contact Info > Email Address | Yes | Yes | App Functionality | The login |
| Contact Info > Name | Yes | Yes | App Functionality | The name shown to teammates |
| Identifiers > User ID | Yes | Yes | App Functionality | The account's ID; error reports name only this |
| User Content > Photos or Videos | Yes | Yes | App Functionality | Photos and videos attached to a chat |
| User Content > Audio Data | Yes | Yes | App Functionality | Dictation: sent to our servers and transcribed in the EU; the recording isn't kept, the words become the message |
| User Content > Other User Content | Yes | Yes | App Functionality | Questions, answers, chats, files, instructions, memories |
| Diagnostics > Other Diagnostic Data | Yes | Yes | App Functionality | Server error reports, with the user ID only |
| Everything else (location, contacts, health, financial info, browsing history, search history, purchases, usage data, advertising data, crash data from the device) | No | | | |

Purchases are left out because the app sells nothing: plans and credits are
bought on the web, never in the app. Push tokens are not a "Device ID" in
Apple's sense (that category is for advertising and vendor identifiers).
`ChatWithWork/Resources/PrivacyInfo.xcprivacy` declares the same types.

Two things that look like collection aren't new types:

- **Notification words.** The notification service extension fetches a
  chat's title and the start of its answer from our server as a push
  arrives (server contract, section 9): the app receives them, and sends
  only the phone's notification key, which identifies no one outside our
  server. They're the same User Content the app already shows.
- **The yes to AI models.** Before the first question goes to a model, the
  page asks once (5.1.2(i), below); the server keeps when, which wording,
  and that it was the iOS app, with the account. That's account data, not a
  type of its own.

Each extension (share, notifications, widgets) carries its own
`PrivacyInfo.xcprivacy` too: they compile `Shared/`, whose shared inbox
reads its folders' creation dates (file timestamps, reason `C617.1`, also
in the app's), and they collect nothing themselves.

## Age rating

Answer the questionnaire as: no violence, sexual content, nudity, profanity,
horror, drugs, alcohol, tobacco, gambling, contests, or medical treatment
information in the app's own content; **user-generated content: yes**
(people's chats, shared only inside their organization); **unrestricted web
access: no** (the web view only shows Chat with Work's pages; other sites
open in Safari); **messaging and chat: no** (people don't message each
other; they share chats with an assistant); AI-generated content: yes,
from the assistant's answers. Then set the age rating to **16+**, matching
the privacy policy ("not intended for children under 16"). It is not made
for kids, so it stays out of the Kids category.

## Things App Review asks about

- **3.1.1 / 3.1.3(f), purchases.** The app is a free companion to the web
  service and sells nothing. Settings > Billing shows the plan without
  checkout or links, and calls to buy credits are hidden in the apps.
- **4.2, minimum functionality.** Native tabs, sheets, menus, alerts,
  toasts, haptics, search, the share sheet, Quick Look, push notifications,
  and universal links, around the web app's pages.
- **4.8, sign in with Apple.** Not required: since 2026-10-27 the server
  offers the iPhone and iPad app no other company's sign-in (no Google,
  Microsoft, Slack, or Dropbox), only email and a password, or a passkey
  (the Rails app's `docs/security/sign-in.md`, "Apps"; decision 14).
  Connecting a service from the app (Google Drive, Slack, ...) isn't a
  login. Android and the web keep the provider sign-ins.
- **5.1.2(i), third-party AI.** Before the first question, dictation, or
  bot fill-in goes to a model, the app shows the page's dialog "Before your
  first question", naming who runs the models and where (Gemini on Google
  Vertex AI, GPT on Microsoft Azure's EU Data Zone, Claude on AWS Bedrock,
  Qwen on Hetzner, all in the EU), with Not now and Agree and continue, and
  a link to the privacy policy. It's asked once per login and recorded. The
  demo login hasn't agreed, so the reviewer sees it on their first question
  (the Rails app's `docs/model-consent.md`).
- **1.2, user-generated and AI content.** An answer's menu (the "…" under
  it) has Good answer and Bad answer; Bad answer asks what went wrong, with
  "Offensive or harmful" among the reasons and a comment, sent to our staff
  without leaving the app (the Rails app's `docs/feedback.md`). People
  don't message each other, so there's nobody to block. Contact: the
  listing's support URL and support@chatwithwork.com, which the privacy
  policy gives too.
- **5.1.1(v), account deletion.** Settings > Account > Delete account.
- **Permissions.** Microphone (dictation, and sound with a video),
  camera (a photo or video to attach), notifications (offered once after
  the first sign-in, with a short explanation before iOS's prompt, and from
  Settings > Notifications).
