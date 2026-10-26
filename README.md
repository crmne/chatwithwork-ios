# Chat with Work for iOS

The iPhone and iPad app for [Chat with Work](https://chatwithwork.com), your
work agent: it searches, reads and, with your approval of each change, works
in the tools you already use, hosted in the EU or on your own servers.

The app is built with [Hotwire Native](https://native.hotwired.dev). Its
screens are the web app's own pages, so every feature the web app gains
reaches the app without a release, and it goes native wherever that makes it
feel like an iOS app: it opens on a new chat, with a native sidebar that
slides in from the left (your chats, projects, what waits for you, Bots, and
Settings), large titles, sheets, a welcome screen, native menus, alerts,
toasts, haptics, search, the share sheet, sign-in and connecting services
through the system's secure browser sheet, push notifications that show the
answer's start or what waits for you (fetched from the server as they arrive,
never through Apple) and universal links, a native composer with a "+" sheet
and dictation, Live Activities for answers that work on after you leave them,
a home-screen widget, and a share extension.

What the server has to do for all of that is written down in
[docs/server-contract.md](docs/server-contract.md).

## Requirements

- Xcode 26 or later (developed with Xcode 27)
- iOS 18 or later, iPhone and iPad
- Swift packages, pinned in the project: [hotwire-native-ios](https://github.com/hotwired/hotwire-native-ios)
  1.3.1 and Joe Masilotti's [bridge-components](https://github.com/joemasilotti/bridge-components) 0.14.0

## Building

Open `ChatWithWork.xcodeproj`, pick the **ChatWithWork** scheme and a
simulator, and run. The Debug build talks to a Chat with Work server on your
machine (see Configuration); to try it against staging instead, add
`-CWWBaseURL https://staging.chatwithwork.com` to the scheme's launch
arguments.

From the command line:

```sh
script/test                         # unit tests on the first available iPhone simulator
script/test <simulator-udid> ui     # UI tests (start the playground first, see below)
xcodebuild build -project ChatWithWork.xcodeproj -scheme ChatWithWork \
  -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
```

To run on a device, copy `Config/Signing.xcconfig.example` to
`Config/Signing.xcconfig` and put your team ID in it. That file is
git-ignored: this repository is public, so team IDs, certificates, keys and
provisioning profiles never go in it.

## Configuration

Each build configuration points at one server and installs as its own app,
so all three can sit on one phone:

| Configuration | Server | Bundle identifier | Name on the home screen |
|---|---|---|---|
| Debug | `https://chatwithwork.localhost` | `com.chatwithwork.app.debug` | CWW Dev |
| Staging | `https://staging.chatwithwork.com` | `com.chatwithwork.app.staging` | CWW Staging |
| Release | `https://chatwithwork.com` | `com.chatwithwork.app` | Chat with Work |

The values live in `Config/Debug.xcconfig`, `Staging.xcconfig` and
`Release.xcconfig`, on top of `Base.xcconfig`. To point a build somewhere else
on your machine only, copy `Config/Local.xcconfig.example` to
`Config/Local.xcconfig` (git-ignored), for example to reach `bin/dev` on
another computer:

```
CWW_BASE_URL = http:/$()/192.168.1.20:3000
```

(xcconfig reads `//` as a comment, hence `$()`.) The simulator only trusts
devhost's `https://chatwithwork.localhost` once its root certificate is added
with `xcrun simctl keychain booted add-root-cert <caddy-root.crt>`.

Development and staging builds also take launch arguments; production
builds ignore the first:

| Argument | Effect |
|---|---|
| `-CWWBaseURL <url>` | use another server (or set `CWW_BASE_URL` in the scheme's environment) |
| `-CWWResetState YES` | start as a fresh install: no cookies, no remembered sign-in or organization |
| `-CWWAssumeSignedIn YES` | start in the signed-in shell, as after signing in |
| `-CWWToastSeconds 30` | keep notices up that long (Debug only; the UI tests tap them away) |
| `-CWWAskForNotifications NO` | never offer notifications (UI tests that aren't about it) |

Push notifications and universal links need the Push Notifications and
Associated Domains capabilities on the App ID, which automatic signing adds
from `ChatWithWork/Resources/ChatWithWork.entitlements`. The app and its
notification service extension share the phone's notification key through a
keychain group under the team's prefix (`CWW_KEYCHAIN_GROUP`), which needs
nothing in the developer portal. The extension's own App IDs
(`com.chatwithwork.app.notifications`, `.staging.notifications` and
`.debug.notifications`) are registered there, as a new extension's must be
before Xcode Cloud signs it.

## How it's put together

```
ChatWithWork/
  App/            launch, the scene, the environment, AppShell (what the window shows)
  Navigation/     the signed-out flow, web screens, routes
  Sidebar/        the signed-in shell: one chat screen and the native sidebar
  Bridge/         the bridge components (native halves)
  Interface/      Live Wire colors, appearance, toasts, the error screen
  Notifications/  push notifications
  Composer/       the native composer, its + sheet and dictation
  LiveActivities/ starting Live Activities and telling the server their tokens
  Resources/      Info.plist, entitlements, assets, the bundled path configuration
Shared/           what the app and its extensions share: Live Activity attributes, app links, the share inbox,
                  a notification's words and the phone's notification key
Widgets/          the widget extension: Ask on the home screen, and the Live Activity
ShareExtension/   the share extension
NotificationService/  the notification service extension, which fetches a notification's words from the server
ChatWithWorkTests/    unit tests (Swift Testing)
ChatWithWorkUITests/  UI tests (signed out against staging, signed in against the playground)
web/              the web half of the bridge, for the Rails app to copy
Playground/       a stand-in server that behaves as the server contract says
docs/             the server contract and design notes
```

- **AppShell** owns the window and switches between the signed-out welcome
  screen (with the server's sign-in pages as sheets) and the sidebar shell. It is
  every navigator's delegate and watches their traffic for what the server
  says: a 401 or the sign-in page means no session, a recede while signed out
  means signed in, a link into another organization means switching. Each
  change rebuilds the shell rather than patching it.
- **SidebarShell**: one navigator whose root is always a chat (the path
  configuration replaces the root for every chat page), with the sidebar
  beside it, which slides in from the left and pushes the chat aside. The
  sidebar is SwiftUI, drawn from the server's `/native/sidebar` JSON, fetched
  with the web views' own cookies (`SidebarStore`). Bots, projects and other
  pages are pushed over the chat; Settings and forms are sheets.
- **Web screens** are plain `HotwireWebViewController`s configured from
  outside (`WebScreen`), never subclassed: a subclass recreating the bridge
  delegate is what crashed Cluster Headache Tracker's app. The web view
  shrinks above the keyboard, so the composer rides on it, its page zoom
  follows the system text size, and its title follows the page's `<title>`
  whenever it changes. Files open in Quick Look.
- **Bridge components**: Joe Masilotti's `alert`, `review-prompt` and `theme`
  as they are; iOS versions of `button`, `menu`, `search`, `form`, `share`,
  `toast` and `haptic` with his messages, which share the navigation bar
  instead of replacing each other; and four of Chat with Work's own:
  `context-menu` (a message's actions), `auth-session` (sign-ins in the
  system browser sheet), `notification-token` (push) and `sidebar` (the
  page saying the chat list changed).
- **Path configuration**: bundled in `Resources/path-configuration.json`,
  replaced at launch by the server's `/configurations/ios_v2.json`, of which
  it is an exact copy.

## The playground

`Playground/server.py` stands in for the Rails app as it will be once it
implements the server contract: fixture pages in the web app's own markup,
styled by its real stylesheet (fetched from staging), with the bridge
controllers from `web/` and the contract's authentication (401s, sign-in,
recede). Everything on its pages is made up. It needs only Python 3:

```sh
python3 Playground/server.py            # http://localhost:8765
python3 Playground/server.py --open     # every request signed in
```

then run the app with `-CWWBaseURL http://localhost:8765`, or run the UI
tests, whose `PlaygroundTests` sign in, use the sidebar, open a chat, use its
menus and the composer, and visit Bots and Settings.

## Releasing

Every push to main reaches TestFlight: Xcode Cloud's "TestFlight" workflow
(product ChatWithWork, started by changes to `main`) archives the
ChatWithWork scheme (Release, production) and uploads it to App Store
Connect, where the Internal group, which has every build, gets it after
processing. The workflow's "TestFlight External Testing" post-action also
gives each build to the "Public beta" group, the public TestFlight link
(see [docs/app-store.md](docs/app-store.md), "Public TestFlight beta"). `ci_scripts/ci_post_clone.sh` gives the build Xcode Cloud's team
and build number (`CI_TEAM_ID`, `CI_BUILD_NUMBER`), since
`Config/Signing.xcconfig` isn't in the repository. The version is
`MARKETING_VERSION` in `Config/Base.xcconfig`, the version main is working
towards: bump it once a version goes to App Review. Xcode Cloud numbers
builds itself, from 10002 up (App Store Connect, Xcode Cloud > ChatWithWork >
Settings > Build Number), so they stay above the builds uploaded by hand.
Xcode Cloud signs automatically but can't change App IDs: a new capability
in the entitlements means enabling it on `com.chatwithwork.app` in the
developer portal first.

By hand instead: `script/upload v1.2.3` archives Release as version 1.2.3,
build 10203 (MAJOR·10000 + MINOR·100 + PATCH), and uploads it to App Store
Connect for TestFlight; `script/upload <path>.xcarchive` uploads an archive
you already have. It signs in with an App Store Connect API key, never
Xcode's Accounts, so it works over SSH without signing in again
([docs/app-store.md](docs/app-store.md), "Uploading with an API key").
`script/archive v1.2.3` only archives. App Store Connect wants each build
number of a version once, growing: for a version Xcode Cloud has already
built, give a number above its latest (`script/upload v1.2.3 <build>`).
[docs/app-store.md](docs/app-store.md) has the rest of a submission: the
listing and screenshots in `fastlane/`, App Privacy answers, the age
rating, and the demo login for App Review.

## License

Chat with Work for iOS is dual-licensed under the [MIT License](LICENSE-MIT)
and the [Apache License, Version 2.0](LICENSE-APACHE), at your option.
