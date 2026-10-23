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
   <password file>` creates it with synthetic content, once the release
   that serves the apps is deployed.

## Building and uploading

Pushing to main is enough: Xcode Cloud's "TestFlight" workflow archives
Release and uploads it to App Store Connect, where it goes to the Internal
Testing group (see the README's Releasing). To archive by hand instead:

```sh
cp Config/Signing.xcconfig.example Config/Signing.xcconfig   # put the team ID in it
git tag v1.0.0
script/archive v1.0.0          # Release, version 1.0.0, build 10000
```

Then Xcode > Window > Organizer > the archive > Distribute App > App Store
Connect > Upload. From the command line, `xcodebuild -exportArchive` with
an `ExportOptions.plist` whose `method` is `app-store-connect` and
`destination` is `upload` does the same once Xcode is signed in to the team.
The build shows up in TestFlight after processing, about 15 minutes: add
yourself under Internal Testing to install it with the TestFlight app.

`ITSAppUsesNonExemptEncryption` is `false` in `Info.plist`: the app uses
only the system's HTTPS, so no export compliance documents are needed.

## The listing

| Field | Where |
|---|---|
| Name, subtitle, description, keywords, promotional text, What's New | `fastlane/metadata/en-US/` |
| Support URL, marketing URL, privacy policy URL | `fastlane/metadata/en-US/*_url.txt` |
| Category | Business, then Productivity (`fastlane/metadata/*_category.txt`) |
| Copyright | `fastlane/metadata/copyright.txt` |
| Screenshots | `fastlane/screenshots/en-US/`: 6.9" (1320 x 2868), 6.5" (1284 x 2778), iPad 13" (2064 x 2752) |
| App Review contact, demo login, notes | `fastlane/metadata/review_information/` (the password is in 1Password, never here) |

Screenshots come from the app itself: `ChatWithWorkUITests/StoreScreenshotTests`
signs in to staging as the synthetic screenshot account, ana@northwind.example
(`script/store/seed staging screenshots` in the Rails app), visits six
screens in dark mode with the status bar at 9:41, and keeps each as a test
attachment. `script/screenshots` runs it on the three simulators and frames
the results with their captions (`fastlane/screenshots/captions.json`):

```sh
node script/frame-screenshots.mjs build/screenshots/iphone-69 out/iphone-69 1320x2868 \
  --fonts ../chatwithwork/app/assets/fonts
```

The iPad set leaves out Schedules until the Rails app's one-column Settings
for the apps (`native.css`) is deployed: before it, the page squeezes into
a narrow column on wide screens.

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
- **4.8, sign in with Apple.** Not required: the app signs in only with
  Chat with Work's own email and password. Google, Slack, and Dropbox
  sign-ins are hidden in the apps.
- **5.1.1(v), account deletion.** Settings > Account > Delete account.
- **Permissions.** Microphone (dictation, and sound with a video),
  camera (a photo or video to attach), notifications (asked for from
  Settings > Notifications, never at launch).
