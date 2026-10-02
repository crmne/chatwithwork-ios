# Agent guide

Chat with Work for iOS: a Hotwire Native shell around the Rails app at
`crmne/chatwithwork` (private), whose `AGENTS.md` describes the product, the
Live Wire design system and the chat UI. Read the README here first, then
`docs/server-contract.md`.

## Working style

- Work on the default branch for maintainer-directed work. Do not create a
  branch or pull request unless asked. Pull requests remain required for
  outside contributions.
- Keep history linear: one focused commit per topic, no merge commits.
- Keep changes within the requested scope and preserve existing behavior
  unless the task changes it.
- Never commit secrets, team IDs, certificates, provisioning profiles or API
  keys: the repository is public. Signing lives in the git-ignored
  `Config/Signing.xcconfig`, local overrides in `Config/Local.xcconfig`.
- Never use em dashes in user-facing text (UI strings, docs, commit
  messages): commas, colons, parentheses or full stops.

## Architecture rules

- Screens are plain `HotwireWebViewController`s configured by `WebScreen`.
  Don't subclass `HotwireWebViewController`: Cluster Headache Tracker's app
  crashed when a subclass recreated the bridge delegate. Subclassing
  `HotwireTabBarController` and `HotwireNavigationController` is fine (both
  are meant for it).
- `AppShell` owns the window's root. Changes of session or organization
  rebuild the shell rather than patching tabs.
- Navigation bar buttons go through `NavigationBarItems`, one slot per
  source, never `navigationItem.rightBarButtonItem` directly, so components
  don't replace each other.
- A bridge component's name, events and payload keys are a contract with the
  Rails app and the Android app. Change one only together with
  `docs/server-contract.md`, the reference controller in
  `web/controllers/bridge/`, its test in `ChatWithWorkTests/BridgeContractTests.swift`,
  the playground if it uses it, and a note for the Android app
  (`crmne/chatwithwork-android`). Where Joe Masilotti's bridge-components has
  the component, keep his messages and only add optional keys.
- Path configuration rules live in `ChatWithWork/Resources/path-configuration.json`;
  the server serves a copy as `/configurations/ios_v1.json`, which replaces
  the bundled one at launch. Change both, and keep `PathConfigurationTests`
  passing.
- Colors come from `Palette` (Live Wire's tokens); native text uses the
  system font. Check UI changes in light and dark mode.
- Declare every language the web app serves in `CFBundleLocalizations` and
  the String Catalogs: WKWebView only sends the device's `Accept-Language`
  for languages the app declares. Today that's English.
- Anything UIKit, SwiftUI or WebKit may call off the main thread (dynamic
  color providers, share sheet item sources, completion handlers) must be
  `nonisolated` or `@Sendable`: the target defaults to the main actor, and
  Swift traps when such code runs elsewhere.
- Pin dependencies to exact releases (`exactVersion` in the project), never
  to a branch.

## Building and testing

- `script/test` runs the unit tests on an iPhone simulator; `script/test
  <udid> ui` the UI tests. `SignedOutTests` need network access to staging;
  `PlaygroundTests` need `python3 Playground/server.py` running and skip
  themselves otherwise.
- The playground's pages are fixtures. When the server contract changes,
  update them so they keep showing what the contract asks for.
- Write the fixtures in the web app's own markup: copy each partial's
  elements, wrappers and classes from `app/views/` (`chats/_form`,
  `messages/_assistant`, `activities/_activity`...) rather than
  approximating them. The real stylesheet styles them, so a missing wrapper
  moves things: without `.model-picker`, send sat mid-bar in the composer.
- `Playground/server.py` must run on macOS's own `python3` (3.9): nothing
  newer, such as a backslash inside an f-string's `{}` or `match`.
- Never claim a platform or flow was tested unless it was actually run, and
  say whether it ran against the playground or a real server.
- Build headless when working remotely: `xcodebuild` and `xcrun simctl`
  only. Create your own simulators and manage them by UDID.

<!-- github-automation: release-notes -->
## Releases

This section is maintained account-wide by
[crmne/github-automation](https://github.com/crmne/github-automation) and is
replaced when that policy changes. Do not edit it here. If it does not fit this
repository, say so in a review or issue, and put repository-specific release
steps in a separate section, which takes precedence.

Never use em dashes in new or edited user-facing writing, including release
titles, release notes, and agent responses. Use commas, colons, parentheses,
or full stops. Existing text does not need to change just to follow this.

The rest of this section applies only when this repository publishes GitHub
releases. If it has none, skip it, and do not add tags, release workflows, or
release-notes files just to follow it.

Do not cut a release for every fix. Work accumulates on the default branch
until there is something substantial to announce: a feature, or a batch of
fixes worth a changelog entry. The exception is a regression in something just
released, which goes out as soon as it is fixed.

Before writing release notes, read the previous two stable releases and match
their style. If there are fewer, read the most recent releases that exist,
including prereleases, and follow their format.

- Start with a short plain-language summary, followed by a download line when
  the project ships binaries.
- Include screenshots or short videos of the main user-visible changes.
  Capture only synthetic demo content, never real user data. Host the media
  where earlier releases do, such as release assets or files beside the notes.
- Use `New` and `Fixed` sections as applicable, and `Known limitations` when
  there are any. Lead each item with a bold user-facing result and credit who
  did what with issue or pull request numbers ("By @x; thanks @y"),
  acknowledging reporters separately from implementers.
- Include a `Thanks` section listing contributors and reporters, and end with
  `**Full changelog**:` and a link comparing the previous tag.
- Write about what changed for the user, not the commit history. Describe
  known limitations honestly.

Every release description is these hand-written notes, never a list generated
by GitHub, a changelog tool, or commit subjects. Commit the notes before
tagging, in the repository's existing release-notes location, or as
`packaging/release-notes/vX.Y.Z.md` when it has none. Any publishing path that
uses the committed file works, for example `softprops/action-gh-release` with
`body_path` and `generate_release_notes: false`, `gh release create
--notes-file`, GoReleaser's `--release-notes`, or `gh release edit
--notes-file` when another step creates the release.

If the release path still generates its notes, switching it to the committed
file is part of preparing the next release. Make a missing notes file stop the
release before any tag or release is created.

A release is not finished until every image, video, and download link in its
notes loads. Upload the release media right after the release is published and
before announcing it, then open the published release and check every image
and link.
<!-- /github-automation: release-notes -->
