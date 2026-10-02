# Chat with Work for iOS

The iPhone and iPad app for [Chat with Work](https://chatwithwork.com), the
private AI assistant for your work: one place to ask about your documents,
mail and chats wherever they live, hosted in the EU or on your own servers.

The app is built with [Hotwire Native](https://native.hotwired.dev). Its
screens are the web app's own pages, so every feature the web app gains
reaches the app without a release, and it goes native wherever that makes it
feel like an iOS app: a tab bar with a navigator per tab, large titles, sheets,
a welcome screen, native menus, alerts, toasts, haptics, search, the share
sheet, sign-in through the system's secure browser sheet, push notifications
and universal links.

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
| `-CWWAssumeSignedIn YES` | start in the tab shell, as after signing in |
| `-CWWStartTab projects` | start on another tab (`chats`, `projects`, `settings`; Debug only) |

Push notifications and universal links need the Push Notifications and
Associated Domains capabilities on the App ID, which automatic signing adds
from `ChatWithWork/Resources/ChatWithWork.entitlements`.

## How it's put together

```
ChatWithWork/
  App/            launch, the scene, the environment, AppShell (what the window shows)
  Navigation/     tabs, the signed-out flow, web screens, routes
  Bridge/         the bridge components (native halves)
  Interface/      Live Wire colors, appearance, toasts, the error screen
  Notifications/  push notifications
  Resources/      Info.plist, entitlements, assets, the bundled path configuration
ChatWithWorkTests/    unit tests (Swift Testing)
ChatWithWorkUITests/  UI tests (signed out against staging, signed in against the playground)
web/              the web half of the bridge, for the Rails app to copy
Playground/       a stand-in server that behaves as the server contract says
docs/             the server contract and design notes
```

- **AppShell** owns the window and switches between the signed-out welcome
  screen (with the server's sign-in pages as sheets) and the tab shell. It is
  every navigator's delegate and watches their traffic for what the server
  says: a 401 or the sign-in page means no session, a recede while signed out
  means signed in, a link into another organization means switching. Each
  change rebuilds the shell rather than patching it.
- **Tabs**: Chats, Projects and Settings each own a navigator and load
  lazily. New chat is an action that opens the new chat page as a sheet over
  Chats.
- **Web screens** are plain `HotwireWebViewController`s configured from
  outside (`WebScreen`), never subclassed: a subclass recreating the bridge
  delegate is what crashed Cluster Headache Tracker's app. The web view
  shrinks above the keyboard, so the composer rides on it, and its page zoom
  follows the system text size. Files open in Quick Look.
- **Bridge components**: Joe Masilotti's `alert`, `review-prompt` and `theme`
  as they are; iOS versions of `button`, `menu`, `search`, `form`, `share`,
  `toast` and `haptic` with his messages, which share the navigation bar
  instead of replacing each other; and three of Chat with Work's own:
  `context-menu` (a message's actions), `auth-session` (sign-ins in the
  system browser sheet) and `notification-token` (push).
- **Path configuration**: bundled in `Resources/path-configuration.json`,
  replaced at launch by the server's `/configurations/ios_v1.json`.

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
tests, whose `PlaygroundTests` sign in, open a chat, use its menus and the
composer, and visit every tab.

## Releasing

Versions come from tags: `script/archive v1.2.3` archives Release as version
1.2.3, build 10203 (MAJOR·10000 + MINOR·100 + PATCH). Upload the archive to
App Store Connect from Xcode's Organizer.

## License

Chat with Work for iOS is dual-licensed under the [MIT License](LICENSE-MIT)
and the [Apache License, Version 2.0](LICENSE-APACHE), at your option.
