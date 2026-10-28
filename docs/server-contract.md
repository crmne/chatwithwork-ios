# Server contract

What the Rails app (`crmne/chatwithwork`) adds so the iOS app feels native.
The Android app (`crmne/chatwithwork-android`) relies on the same contract;
where the two differ, this document says so. Every name here (user agent
tokens, paths, bridge component names, events, payload keys) is part of the
contract: change it on both sides at once, or version it.

Nothing here changes what a browser sees. Every difference is keyed to the
app's user agent or to what the running app says it can draw.

The iOS repository carries working references for the web half:

- `web/controllers/bridge/*.js`: the Stimulus bridge controllers, ready to
  copy into `app/javascript/controllers/bridge/`.
- `web/native.css`: the stylesheet for the apps, ready to copy into
  `app/assets/tailwind/components/native.css`.
- `Playground/server.py`: a stand-in server that behaves as this document
  says, with fixture pages written in the web app's own markup. Its pages
  are the quickest way to see what each change should produce (README,
  "Playground").

## Order of work

| Step | What | Needed for |
|---|---|---|
| 1 | [Recognize the apps](#1-recognize-the-apps), [layout](#2-the-layout-in-the-apps), [native.css](#3-the-stylesheet) | Anything to look native |
| 2 | [Authentication](#4-authentication) | Signing in and out cleanly |
| 3 | [Path configuration](#5-path-configuration) | Sheets and pull to refresh as designed, changeable without a release |
| 4 | [Bridge controllers](#6-bridge-components), then [page by page](#7-page-by-page) | Native buttons, menus, toasts, alerts, haptics, search |
| 5 | [Universal links](#8-universal-links) | Links in emails opening the app |
| 6 | [Push notifications](#9-push-notifications) | "A change is waiting for your approval" |
| 7 | [Sign-in with a provider and connecting services](#10-sign-in-with-a-provider-and-connecting-services) | Google sign-in and connector OAuth from the app |
| 8 | [The sidebar](#11-the-sidebar) | builds that list `sidebar`: no tabs, one chat screen, the native sidebar |
| 9 | [The composer](#12-the-composer) | builds that list `composer`: the app draws the composer and drives the web one |
| 10 | [Live Activities, widgets and sharing](#13-live-activities-widgets-and-sharing) | an answer followed on the Lock Screen, "Ask anything" on the home screen, and the share sheet |

Steps 1 to 4 are enough for a first TestFlight build. Until step 7 ships,
hide the "Sign in with …" buttons and the connectors' Connect buttons in the
apps (section 10 says how), because Google refuses OAuth inside a web view.

---

## 1. Recognize the apps

### The user agent

The apps put a prefix before Hotwire Native's own tokens:

```
Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)
  Chat with Work; platform=ios; version=1.2.0; build=10200;
  Hotwire Native iOS; Turbo Native iOS;
  bridge-components: [alert review-prompt theme button menu search form share toast haptic context-menu auth-session notification-token]
```

(one line in reality). Android sends `platform=android` and `Hotwire Native
Android; Turbo Native Android;`. `version` is the marketing version
(`MAJOR.MINOR.PATCH`), `build` an integer. `bridge-components` lists what this
build can draw; the bridge JavaScript reads it too.

turbo-rails already provides `hotwire_native_app?` (`/(Turbo|Hotwire)
Native/`). Add what it doesn't know, as a model (`app/models/native_app.rb`):

```ruby
# The Chat with Work app on a phone, from its user agent:
#   "Chat with Work; platform=ios; version=1.2.0; build=10200; ... bridge-components: [button menu]"
class NativeApp
  PATTERN = /Chat with Work; platform=(?<platform>ios|android); version=(?<version>[0-9][0-9A-Za-z.\-]*); build=(?<build>\d+);/
  COMPONENTS = /bridge-components: \[(?<names>[^\]]*)\]/

  attr_reader :platform, :version, :build, :components

  def self.from(user_agent)
    if match = PATTERN.match(user_agent.to_s)
      components = COMPONENTS.match(user_agent.to_s)&.[](:names).to_s.split
      new(platform: match[:platform], version: match[:version], build: match[:build].to_i, components: components)
    end
  end

  def initialize(platform:, version:, build:, components:)
    @platform, @version, @build, @components = platform, Gem::Version.new(version), build, components
  end

  def ios? = platform == "ios"
  def android? = platform == "android"

  # Whether this build draws a bridge component, for markup that only makes
  # sense with it (a hidden element the component clicks).
  def supports?(component) = components.include?(component.to_s)

  def at_least?(version) = self.version >= Gem::Version.new(version)
end
```

and a concern for controllers (`app/controllers/concerns/native_app_detection.rb`,
included in `ApplicationController`):

```ruby
module NativeAppDetection
  extend ActiveSupport::Concern

  included do
    helper_method :native_app, :native_app?
  end

  private
    def native_app
      return @native_app if defined?(@native_app)
      @native_app = NativeApp.from(request.user_agent)
    end

    def native_app?
      native_app.present?
    end
end
```

`native_app?` is the switch everywhere below. `hotwire_native_app?` also
matches other Hotwire Native apps (and old Turbo Native ones); prefer
`native_app?` for anything specific to Chat with Work's apps.

Pages rendered for the apps must not be cached as browser pages: signed-in
pages already send `Cache-Control: no-store` (`prevent_response_storage`).
If a public page ever renders differently for the apps, add
`Vary: User-Agent` to it.

## 2. The layout in the apps

`app/views/layouts/application.html.erb`, when `native_app?`:

1. **Mark the document** so CSS can tell: `<html lang="en"
   <%= tag.attributes(data: { native_app: native_app.platform }) if native_app? %>>`.

2. **Viewport**: keep `<meta name="viewport" content="width=device-width,
   initial-scale=1">` (`maximum-scale=1` where the page sets it). Don't add
   `viewport-fit=cover`: without it, WebKit insets the page below the app's
   navigation bar and above its tab bar or the home indicator, keeps those
   insets in step with the bars (a large title collapsing, a search bar
   arriving), and lays `position: fixed` elements out inside them. With it,
   the page would start under the bars and have to pad itself with
   `env(safe-area-inset-*)`, which can't follow a collapsing title.

   Two things the app does to every page: it scales it with the system's
   text size (page zoom, 85% to 120%), so layouts must hold down to about
   335 CSS pixels wide (a 402-point phone at 120%); and it sends
   `Accept-Language` in the device's language only if the app declares that
   language. The app declares English, the web app's one language today:
   when the web app adds a language, the apps add it in the same release
   (iOS: `CFBundleLocalizations` and the String Catalogs).

3. **Title**: the app shows `<title>` as the screen's title, so it must be
   the page's own short name: no environment prefix, no "Chat with Work"
   suffix. Change `document_title` (`MarketingMetadataHelper`):

   ```ruby
   def document_title
     return content_for(:title).presence || "Chat with Work" if native_app?
     safe_join([ Rails.configuration.x.environment_label, page_title ].compact, " · ")
   end
   ```

   and give every page the apps reach a `content_for :title`. A page may
   retitle itself later: a chat's `<title>` follows the chat's title as it
   changes (the automatic title arriving after the first answer, a rename
   elsewhere), and the app retitles the screen whenever `<title>` changes,
   not only when a visit renders. The page's part is a hidden copy of the
   bar's title that `Chat#broadcast_title` updates, whose
   `document-title` controller rewrites `<title>`.

   Every page's title:

   | Page | Title |
   |---|---|
   | `chats/index` | Chats |
   | `chats/show` | the chat's `display_title` |
   | `chats/new` | New chat |
   | `chats/edit` | Rename chat |
   | `chats/projects/edit` (move to project) | Move to project |
   | `projects/index` | Projects (already) |
   | `projects/show` | the project's name (already) |
   | `projects/new` / `edit` | New project / Project settings |
   | `settings/show` without `tab` | Settings (already) |
   | `settings/show` with `tab` | the tab's label: Account, People, Projects, Billing, Usage, Models, Connectors, Notifications, Sharing |
   | `accounts/index` | Organizations |
   | `devise/sessions/new` | Sign in |
   | `devise/registrations/new` | Create an account |
   | `devise/passwords/new` | Reset your password |
   | `devise/passwords/edit` | Choose a new password |
   | `users/confirmations/sent` | Check your email |
   | `shared_chats/show` | the chat's title |
   | `messages/results/show` | the tool's name, e.g. "Google Drive" |

4. **No web chrome the app replaces.** In `LayoutConfiguration`, make the
   defaults answer `false` in the apps: `show_header?`, `show_footer?` and
   `show_support_launcher?` (the floating Chatwoot launcher would sit on the
   tab bar). Keep `show_sidebar?` as it is, but render
   `application/_sidebar` differently (next point).

5. **No drawer.** The sidebar layout wraps every app page in a fixed-height
   drawer whose `.app-main` pane scrolls. In the apps the document itself
   must scroll, so the native bars can collapse their large titles and tint
   as content passes under them, and the app's pull to refresh works. In
   `application/_sidebar.html.erb`:

   ```erb
   <% if native_app? %>
     <% if Current.user && !Current.user.guest? %>
       <%= render "shared/service_reconnection_modal" %>
       <%= render "shared/usage_limit_modal" %>
       <%= turbo_stream_from Current.account, :usage_progress %>
     <% end %>
     <main class="native-main" data-controller="scroll"><%= yield %></main>
   <% else %>
     …the drawer, unchanged…
   <% end %>
   ```

   The `scroll` controller (the conversation's auto-scroll and its "latest
   message" button) then has to scroll the document: where it reads or sets
   `this.element.scrollTop`/`scrollHeight`/`clientHeight`, use
   `document.scrollingElement` when the element doesn't scroll itself
   (`getComputedStyle(this.element).overflowY` is `visible`), and its action
   becomes `scroll@window->scroll#updateScrollButtonVisibility`.

   The sidebar's contents (Recent, Pinned, the account switcher) aren't
   rendered in the apps: Chats is the app's Recent, and the switcher moves
   to Settings (section 7).

6. **Hide the environment label.** It's fixed to the top edge, which in the
   apps lies under the status bar and the navigation bar's glass. Staging
   and development builds are named "CWW Staging" and "CWW Dev" on the home
   screen, and their welcome screen shows the server's host.

7. **Confirms**: `<body … data-controller="bridge--confirm …">` (merge with
   the existing `timezone-sync`), so `data-turbo-confirm` shows a native
   alert (section 6).

8. **Flash as toasts**: `application/_flash.html.erb` renders, in the apps,
   a hidden element per message instead of the web toast:

   ```erb
   <% if native_app&.supports?(:toast) %>
     <% %i[ notice info alert error ].each do |type| %>
       <% next if flash[type].blank? %>
       <%= tag.div flash[type], hidden: true,
             data: { controller: "bridge--toast", bridge_type: type, turbo_temporary: true } %>
     <% end %>
   <% else %>
     …the web toasts, unchanged…
   <% end %>
   ```

   It stays inside the `flash-messages` frame, so flashes that arrive over
   the session's Turbo Stream (`FlashMessages#broadcast_flash_messages`)
   become toasts too. `data-turbo-temporary` keeps a toast from showing
   again when Turbo restores the page from its cache.

## 3. The stylesheet

Copy `web/native.css` to `app/assets/tailwind/components/native.css` and
import it last in `application.css`. It:

- hides, in the apps, `.native-hidden`, the drawer toggle
  (`.app-main__toggle`), the staging band (`.environment-label`), tooltips
  (`.tooltip`'s bubbles), and keyboard-shortcut hints (`.kbd-hint`, such as
  the composer's "⌘ /" or "Ctrl /"), which mean nothing on a touch screen;
- lets the document scroll, with the platform's gutter;
- keeps the conversation's composer at the bottom of what's visible: above
  the home indicator, and above the keyboard while it's up (the app resizes
  the web view, so the composer's `position: fixed; bottom: 0` lands on top
  of it);
- hides each web element a bridge component replaces, but only once
  `<html data-bridge-components>` says the running app draws it.

`.native-hidden` is the class to put on anything the native shell replaces
(page headings under a native large title, buttons that became navigation
bar buttons). Its rules are `!important` because daisyUI's component rules
sit in the later utilities layer.

## 4. Authentication

The app shows a native welcome screen when there's no session, the server's
sign-in and sign-up pages as sheets over it, and rebuilds its shell after a
sign-in. The server's part:

### 401 instead of a redirect

A request from the app without a session gets `401 Unauthorized`, not a
redirect to the sign-in page. The app then shows its welcome screen and opens
sign-in. (The app also copes with the redirect, but a 401 is cleaner: the
failed screen never shows the sign-in form in a tab.)

`lib/native_authentication_failure.rb`:

```ruby
# Devise's failure app, answering the Chat with Work apps with 401 so they
# present their own sign-in instead of following a redirect into a tab.
class NativeAuthenticationFailure < Devise::FailureApp
  def http_auth?
    super || NativeApp.from(request.user_agent).present?
  end

  def http_auth_body
    "You need to sign in."
  end
end
```

and in `config/initializers/devise.rb`:

```ruby
config.warden do |manager|
  manager.failure_app = NativeAuthenticationFailure
end
```

### Where sign-in ends

Every way of signing in (password, Google, Slack or Dropbox sign-in, a
password reset, accepting an invitation, confirming an email that signs in)
ends in `after_sign_in_path_for`. In the apps it answers with Turbo's recede
location, which the app takes as "signed in, rebuild the shell":

```ruby
# app/controllers/concerns/authentication.rb
def after_sign_in_path_for(identity)
  if native_app?
    stored_location_for(identity) || turbo_recede_historical_location_path
  else
    stored_location_for(identity) || landing_path_for(identity)
  end
end
```

`/recede_historical_location` is turbo-rails' route
(`Turbo::Native::NavigationController#recede`); nothing else to add. If a
stored location exists (an invitation link opened before signing in), the app
opens that page in its sign-in sheet; once it leads into an organization, the
app rebuilds the shell there.

The app recognizes a successful sign-in in three ways, so any of them works:
a visit to `/recede_historical_location`, a page inside an organization
(`/482139075/...`), or `/accounts`. A page that stays on `/users/...` keeps
the sheet open (wrong password, confirmation needed).

### Staying signed in

A phone app should stay signed in. In the apps:

- sign-in forms send `remember_me`, always: replace the checkbox with
  `hidden_field_tag "identity[remember_me]", "1"` when `native_app?`;
- `sign_in` calls made in code for the apps (`Invitations::AcceptancesController`,
  `Users::WorkToolAuthorizationsController`, the native sign-in redemption in
  section 10) pass `remember_me(identity)` after signing in;
- consider `config.extend_remember_period = true`, so someone who opens the
  app at least every two weeks never signs in again.

### Signing out

`after_sign_out_path_for` answers `new_identity_session_path(script_name:
nil)` in the apps. The app sees the sign-in page arrive as the redirect after
the logout form, switches to its welcome screen, and doesn't open the sign-in
sheet (it does when a session expires instead).

Before signing out, delete this device's push registration (section 9).

### Pages without web chrome

The Devise pages (`sessions/new`, `registrations/new`, `passwords/new`,
`passwords/edit`, `confirmations/new`, `confirmations/sent`) show in a native
sheet with a native title and close button. In the apps, don't render their
`.auth` page heading strip ("Sign in" eyebrow and "Welcome back") as a large
heading: mark it `.native-hidden`, or keep only the form. Keep the links
between them (forgot password, create an account): they push inside the
sheet.

## 5. Path configuration

The apps ship rules for how each URL is presented (pushed, or as a sheet; with
or without pull to refresh), and load the server's copy on every launch, which
**replaces** the bundled one entirely once it loads. Serve them as static
files:

- `public/configurations/ios_v2.json`: the rules of the sidebar builds
  (section 11). `ChatWithWork/Resources/path-configuration.json` in the iOS
  repo is an exact copy of it (a server test compares them).
- `public/configurations/ios_v1.json`: the tab builds' rules, kept for builds
  from before the sidebar, unchanged.
- `public/configurations/android_v2.json` and `android_v1.json`: the Android
  repo's equivalents.

Change a file to change navigation without an app release. Bump the name
only when old app builds must not read the new rules (as v2 did: a tab build
reading "replace the root" for every chat would lose its list); keep serving
the old name for them.

The iOS rules (v2), in order (later matches override earlier ones; patterns
are regular expressions matched against the path and query, without
anchoring unless written):

| Pattern | Context | Presentation | Pull to refresh | Notes |
|---|---|---|---|---|
| `.*` | default (push) | | on | |
| `/new(\?\|$)`, `/edit(\?\|$)` | modal (`large` sheet) | | off | every new and edit form |
| `^/users/sign_in`, `^/users/sign_up`, `^/users(\?\|$)`, `^/users/password…`, `^/users/confirmation…`, `^/users/unlock…` | modal | | off | the sign-in pages |
| `/chats/new(\?\|$)`, `/chats/\d+(\?\|#\|$)` | default | `replace_root` | off | a chat is always the one screen; nothing stacks under it |
| `^/shared/` | default | | off | |
| `/settings(\?\|$)` | modal (`large` sheet) | | on | swipe down dismisses; its sections push inside the sheet |
| `/chats(\?\|$)`, `/projects(\?\|$)`, `/bots(\?\|$)` | default | | on | pushed over the chat |
| `/chats/\d+/files/` | modal (`full`) | | off | a chat's file in its viewer, over the chat ([A file](#a-file-chatsfilesshow)) |

v1, for the tab builds, opened `/chats/new` as a sheet, pushed chats, and
treated `/chats`, `/projects` and `/settings` as tab roots.

Hotwire Native adds its own rules for `/recede_historical_location`,
`/resume_historical_location` and `/refresh_historical_location` after these.

## 6. Bridge components

### Installing

1. Vendor the bridge (no CDN, so visitors' IPs don't leak to one):
   `bin/importmap pin @hotwired/hotwire-native-bridge --download`
   (version 1.2.2 or later).
2. Copy `web/controllers/bridge/*.js` into
   `app/javascript/controllers/bridge/`. `pin_all_from
   "app/javascript/controllers"` and the eager loader register them as
   `bridge--button`, `bridge--menu`, and so on. Each one loads only in an app
   that lists its component in the user agent (`BridgeComponent.shouldLoad`),
   so browsers never run them.
3. Copy `web/native.css` (section 3).

### The components

Names, events and payload keys match Joe Masilotti's
[bridge-components](https://github.com/joemasilotti/bridge-components)
where a component exists there, so the Android app uses his components
unchanged. iOS draws its own versions of `button`, `menu`, `search`,
`form`, `share`, `toast` and `haptic` (so several can share the navigation
bar, and to look right on iOS) with the same messages; extra keys, which
Android ignores, are marked "iOS". Every message the bridge sends also carries
`metadata.url`.

| Component | Web → app | App → web | Stimulus controller |
|---|---|---|---|
| `button` | `left` or `right` `{title, iosImage?, androidImage?, color?, nativeAction?}`; `disconnect` | reply to `left`/`right` when tapped: click the element. Sidebar builds leave out a button whose `nativeAction` is `new-chat`: their bar has its own | `bridge--button` |
| `menu` | `connect` `{items: [{title, iosImage?, androidImage?, destructive?, checked?, nativeAction?}], color?, side?, label?, iosImage?, header?}`; `disconnect` | reply to `connect` `{index}`: click that item | `bridge--menu` |
| `search` | `connect` `{placeholder?}` | reply to `connect` `{query}` on every change | `bridge--search` |
| `form` | `connect` `{title, color?}`; `disableSubmit`; `enableSubmit`; `disconnect` | reply to `connect` when tapped: click the submit button | `bridge--form` |
| `share` | `connect` `{url?, title?, text?, color?}` (a bar button); `share` (same data, the sheet at once); `disconnect` | reply to `share` `{completed, activityType}` (iOS) | `bridge--share` |
| `toast` | `show` `{message, type?}`, type `notice` \| `info` \| `alert` \| `error` | none | `bridge--toast` |
| `haptic` | `vibrate` `{feedback}`: `success` \| `warning` \| `error`, plus (iOS) `selection` \| `light` \| `medium` \| `heavy` \| `soft` \| `rigid` | none | `bridge--haptic` |
| `alert` | `show` `{title, description?, destructive, confirm, dismiss}` | reply to `show` only when confirmed | `bridge--confirm` (Turbo confirms) |
| `theme` | `connect` `{theme: "light" \| "dark" \| null}` | none | not used yet: the web and the app both follow the system |
| `review-prompt` | `prompt` | none | not used yet |
| `context-menu` | `show` `{items: [{title, iosImage?, androidImage?, destructive?, copy?, copyHtml?, nativeAction?}], rect: {x, y, width, height}, scroll: {x, y}, title?}` | reply to `show` `{index}`: click that item (not for `copy` items) | `bridge--context-menu` |
| `auth-session` | `start` `{url, ephemeral?}`; `cancel` | reply to `start` `{url}` (the callback URL) or `{error}`: `canceled` \| `invalid_url` \| `unavailable` \| `failed` | `bridge--auth-session` |
| `notification-token` | `connect`; `get`; `offer` `{reason}` (`approval` or `answer`); `openSettings`; `key` `{key, token}` | reply to `connect`, `get` and `offer`: `{status, token?, platform, environment, appId, needsKey}` | `bridge--notification-token` |
| `sidebar` | `connect` `{}`; `changed` `{}` | reply to `connect` `{action: "perform", url, method, confirm?, destructive?}`: send a chat's action from the sidebar | `bridge--sidebar` (section 11) |
| `composer` | `connect` and `state` with the composer's state | reply to the latest `connect` `{action, ...}` | `bridge--composer` (section 12) |
| `file` | `connect` `{files: [{url, name, contentType?, title?}]}`; `disconnect` | none | `bridge--file` ([A file](#a-file-chatsfilesshow)) |

Rules for every component:

- **Once per page.** A page renders each component's controller once (one
  `bridge--button`, one `bridge--menu`, one `bridge--form`, one
  `bridge--search`...). The app keeps one native control per component and
  page, so a second element overwrites the first: the last payload wins.
  Watch for layouts that render the same partial twice (a desktop and a
  phone variant): render the controller in one of them only, or in a hidden
  holder. `toast`, `haptic` and `context-menu` send one-off events instead,
  so they may appear on as many elements as needed (every message has its
  own context menu).
- **Behavior never follows a title.** Titles are for people and will be
  translated; the apps never decide what to do from one. Where the app must
  do something itself beyond clicking the element (none yet; printing would
  be the first), the element sends a stable id, `nativeAction` (from
  `data-bridge-native-action`, for example `"print"`), and the app keys off
  that. `copy` on a context menu item is the one such action today, and it
  has a key of its own.

Details the table can't hold:

- **`button`**: one per page. The title doubles as the accessibility label
  when there's an image. Images are SF Symbol names (`iosImage`) and Material
  Symbols names (`androidImage`).
- **`menu`**: one per page; the items re-send whenever an item target
  connects or disconnects, so a Turbo Stream that turns Pin into Unpin updates
  the native menu. Put the item elements in a hidden holder
  (`<div class="native-actions" hidden>`), or reuse elements already on the
  page. A menu with `side: "left"` or a `header` is a chooser (the
  organization switcher, section 7): its button shows `label` as text, the
  current choice, and the chosen item has `checked`. Any other menu is an
  ellipsis (or `iosImage`), and `label` is its accessibility label. Android
  has no left side for actions, so it shows a chooser as a labelled action
  that opens a sheet titled with the `header`.
- **`context-menu`**: `rect` is the anchor's `getBoundingClientRect()` and
  `scroll` the window's `scrollX`/`scrollY`, both in CSS pixels; the app
  anchors its menu there. An item with `copy` text is copied by the app
  itself (with a "Copied" toast), because a page can't write the clipboard
  from a callback no tap of its own started. `copy` is the Markdown source;
  an answer's Copy item also sends `copyHtml`, the answer rendered as HTML,
  unless its reader chose "Copy answers as: Markdown" in Settings. With it,
  the app puts both on the pasteboard as one item (`public.html` and
  `public.utf8-plain-text`), so rich editors keep the formatting.
- **`alert`**: through `bridge--confirm` on `<body>`, every
  `data-turbo-confirm` becomes a native alert. The confirm text is the
  alert's title. A DELETE (or `data-bridge-destructive="true"` on the form
  or button) gets a destructive button labelled "Delete"; set the label
  with `data-bridge-confirm="Disconnect"`, add detail with
  `data-bridge-description`. A dismissed alert sends nothing, which leaves
  Turbo's submission unstarted: that's what cancelling is.
- **`notification-token`** and **`auth-session`**: sections 9 and 10.
- **`file`**: one per page, in a file's viewer. The app puts Share in the
  bar (iOS `square.and.arrow.up`, Android `share`); with one file it shares
  that file, with more (an Office file, then the PDF of its pages) its menu
  lists each by `title` first. Sharing downloads `url` with the web views'
  cookies, only from the app's own server, and hands the file itself, named
  `name`, to the share sheet (Save to Files, Print, AirDrop, other apps on
  iOS; the chooser on Android, whose overflow menu also has "Save to
  device"). The element sends `connect` again whenever it reconnects, so a
  frame that swaps it (the pages once rendered, adding the PDF) updates the
  button. native.css hides the page's own Download and the chips' Download
  once the app lists the component.

## 7. Page by page

What each page renders in the apps. "Hidden holder" means
`<div class="native-actions" hidden>`, whose elements only native components
click.

### Chats (`chats/index`)

- The header (`.chat-history__header`: "Chats", the count, New chat) gets
  `.native-hidden`: the app shows a large "Chats" title.
- New chat becomes a navigation bar button: the existing `link_to
  new_chat_path` gets `data: { controller: "bridge--button", bridge_title:
  "New chat", bridge_ios_image: "square.and.pencil", bridge_android_image:
  "edit_square" }` (and `.native-hidden`). Skip it when the composer is
  locked.
- Search becomes the native search bar: put `bridge--search` beside the
  existing `search` controller and mark the input as its target
  (`data-bridge--search-target="input"`); wrap the field in
  `.native-search-field`. Each query lands in the input as if typed, so
  `search#filter` runs unchanged.
- Each row's delete button only shows on hover: in the apps show it always,
  or drop it (Delete is in the chat's menu).

### A chat (`chats/show`)

- The pin button (`.app-main__actions`) goes; the chat's actions move to the
  navigation bar, in a hidden holder:

  ```erb
  <% if native_app? %>
    <div class="native-actions" hidden>
      <% if @chat.drivable_by?(Current.user) %>
        <%= link_to "New chat", new_chat_path(project_id: @chat.project&.number),
              data: { controller: "bridge--button", bridge_ios_image: "square.and.pencil",
                      bridge_android_image: "edit_square" } %>
      <% end %>
      <div data-controller="bridge--menu" data-bridge-label="Chat options">
        <%= render "pins/menu_item", pinnable: @chat %>                    <%# data-bridge--menu-target="item", bridge-title Pin/Unpin, ios-image pin/pin.slash %>
        <% unless @chat.in_project? %>…Share link (opens the share dialog)…<% end %>
        <% if own chat %>…Rename (edit_chat_path), Move to project (edit_chat_project_path), Delete (chat_path(@chat, recede: 1), turbo_method delete, turbo_confirm, bridge-destructive)…<% end %>
      </div>
    </div>
  <% end %>
  ```

  Each item needs `data-bridge--menu-target="item"`, a `data-bridge-title`,
  and `data-bridge-ios-image`/`-android-image`: Pin `pin`/`keep`, Unpin
  `pin.slash`/`keep_off`, Share link `link`/`link`, Rename `pencil`/`edit`,
  Move to project `folder`/`drive_file_move`, Delete `trash`/`delete` with
  `data-bridge-destructive="true"`. The pin item must keep the id that
  `pins/update.turbo_stream.erb` replaces, so the menu updates in place.
- **Message actions** (`messages/_assistant`, `messages/_user`): add
  `bridge--context-menu` to the message's own controllers
  (`data-controller="markdown clipboard bridge--context-menu"` on
  `.message--assistant`, `"clipboard bridge--context-menu"` on
  `.message--user`). It goes on the message, not on `.message__actions`,
  because the hidden copy source it reads sits beside the actions, and a
  Stimulus target has to be inside its controller's element. Then mark the
  copy source (`_assistant`'s `<pre data-clipboard-target="source">`,
  `_user`'s `<div data-clipboard-target="source">`) as
  `data-bridge--context-menu-target="copySource"`, mark each action in
  `.message__actions` `data-bridge--context-menu-target="item"` with a short
  `data-bridge-title` and symbols (Copy `doc.on.doc`/`content_copy` with
  `data-bridge-copy="true"`, Retry `arrow.clockwise`/`refresh`, Branch into a
  new chat `arrow.triangle.branch`/`call_split`, Share link `link`/`link`),
  and add one more button at the end of `.message__actions`, shown only in
  apps that draw the menu:

  ```erb
  <button type="button" class="message__action message__more" aria-label="More actions"
          data-bridge--context-menu-target="trigger" data-action="bridge--context-menu#show">
    <%= icon_tag "dots-three" %>
  </button>
  ```

  native.css hides the other icons and shows this one once the app says it
  draws `context-menu`.
- **Rating and reporting an answer (2026-10-27).** The answer's thumbs
  (`messages/feedbacks/_buttons`) are items of its menu too, after Copy:
  Good answer (`hand.thumbsup`/`thumb_up`) and Bad answer
  (`hand.thumbsdown`/`thumb_down`), each a `button_to` the app clicks like
  Retry; once pressed, its title is "Remove your rating" and its symbols the
  `.fill` ones. A thumb opens the reasons under the answer, in the page, and
  Bad answer's include "Offensive or harmful": that's the in-app report
  Google Play's AI-Generated Content policy and the App Store's guideline 1.2
  ask for. Nothing changes in the app: the menu shows whatever items come.
- **Retry** asks through the retry dialog today. In the apps, render the
  retry action as the dialog's own `button_to` with
  `form: { data: { turbo_confirm: "Retry this answer?", bridge_confirm: "Retry",
  bridge_description: "Everything after the question, including this reply,
  will be removed, and the assistant will answer it again." } }` instead of
  the button that opens the dialog: the native alert asks.
- **Approvals** (`messages/tool_calls/_approval`): add haptics to the two
  forms: the approval form `data: { controller: "bridge--haptic",
  bridge_feedback: "success", action: "turbo:submit-start->bridge--haptic#vibrate" }`,
  the denial form the same with `bridge_feedback: "warning"`. The input request
  form (`_input_request`) gets `success` on Send.
- **Composer** (`chats/_form`): add `bridge--haptic` with
  `data-bridge-feedback="light"` to `#new_message`, and
  `turbo:submit-start->bridge--haptic#vibrate` to the form's actions.
  The composer itself stays the web's (the rainbow edge is the brand); the
  app keeps it above the keyboard and above the home indicator. Its
  keyboard-shortcut hint (`.kbd-hint`, "⌘ /" or "Ctrl /") stays in the
  markup: native.css hides it in the apps, where it means nothing.
- **Share link dialog** (`chats/share_links/_dialog`): next to Copy link, a
  Share button for the public link, so it can go to Messages or Mail:
  `data: { controller: "bridge--share", action: "bridge--share#share",
  bridge_url: shared_chat_url(token), bridge_title: @chat.display_title }`,
  rendered only when `native_app&.supports?(:share)`.

### New chat (`chats/new`)

In sidebar builds it's the shell's root, where the app opens; in tab builds
it opens as a sheet. After the first message the server redirects to the new
chat (as now); the chat replaces it as the root (a tab build closes the
sheet and pushes the chat). Nothing else to
change, except that `MessagesController#create`'s HTML fallback
(`redirect_to @chat`) must stay a 303 for Turbo.

### Projects (`projects/index`, `projects/show`)

- `projects/index`: the heading's kicker and `<h1>` get `.native-hidden`
  (the app shows a large "Projects" title), and the lede under them stays;
  New project becomes a `bridge--button` (`plus`/`add`), its
  `.page__actions` hidden.
- `projects/show`: keep the header's summary and description; New chat here
  becomes the `bridge--button` (`square.and.pencil`/`edit_square`); Pin,
  Settings, Leave and Archive go into a `bridge--menu` in a hidden holder.

### Settings (`settings/show`)

The web's settings is a side navigation beside the open tab. In the apps:

- `/settings` without `tab` renders the list of sections, one `.rows__row`
  link per `settings_nav_link` (icon, label, `caret-right`), like iOS
  Settings. Below them, a Log out row (`button_to
  destroy_identity_session_path(script_name: nil), method: :delete, form: {
  data: { turbo_confirm: "Log out of Chat with Work?", bridge_confirm: "Log out" } }`).
- `/settings?tab=…` renders only that tab, without `.settings__nav` and
  `.settings__header` (the app titles it).
- The organization switcher (`application/_account_switcher`) moves to the
  top of `/settings` as a `bridge--menu` on the left of the navigation bar,
  when the person is in more than one organization:

  ```erb
  <div class="native-actions" hidden>
    <div data-controller="bridge--menu" data-bridge-side="left" data-bridge-label="<%= Current.account.name %>"
         data-bridge-header="Organizations">
      <% accounts.each do |account| %>
        <%= link_to account.name, chats_path(script_name: account.slug),
              data: { bridge__menu_target: "item", bridge_checked: account == Current.account } %>
      <% end %>
      <%= link_to "New organization", new_account_path(script_name: nil), data: { bridge__menu_target: "item", bridge_ios_image: "plus" } %>
    </div>
  </div>
  ```

  Link to `chats_path` rather than `new_chat_path`: the app rebuilds its shell
  inside the organization a link leads into. A tab build lands on the chat
  list; a sidebar build on that organization's new chat (the sidebar's own
  switcher links to `new_chat_path` directly).
- Forms that save (Account, notification preferences, MCP servers) keep their
  web buttons; the ones in sheets (new and edit pages) use `bridge--form`.

### Forms in sheets (every `new` and `edit`)

- The submit button moves to the navigation bar: `data-controller="bridge--form"`
  and `data-action="turbo:submit-start->bridge--form#submitStart
  turbo:submit-end->bridge--form#submitEnd"` on the form,
  `data-bridge--form-target="submit"` and a short `data-bridge-title`
  ("Create", "Save", "Move") on the submit.
- On success, in the apps, answer with `recede_or_redirect_to` (turbo-rails)
  and a notice: the app closes the sheet and shows the notice as a toast. A
  create that should land on the new record (a project) keeps redirecting to
  it: the app closes the sheet and pushes the record.
- On failure, render with `:unprocessable_entity` as now: the sheet stays.

Turbo asks for a Turbo Stream first on every form it submits, so actions
that answer both formats (`ChatsController#update`, `#destroy`) would send
the app their stream. The native-only markup says what it wants instead: the
forms in sheets and the items in a page's native menu carry `recede=1` (a
hidden field, or a query parameter on `data-turbo-method` links), and the
action goes back first:

```ruby
# app/controllers/concerns/native_app_detection.rb
def recede_in_app?
  native_app? && params[:recede].present?
end
```

```ruby
# ChatsController
def update
  if @chat.update(chat_params)
    return recede_or_redirect_to(@chat, notice: "Chat renamed.") if recede_in_app?
    …as now…
end

def destroy
  @chat.deactivate
  return recede_or_redirect_to(chats_path, notice: "Chat deleted.") if recede_in_app?
  …as now…
end
```

### Deleting

The chat's Delete menu item (`chat_path(@chat, recede: 1)` with
`data-turbo-method="delete"`) pops the chat in tab builds and shows "Chat
deleted." as a toast. Sidebar builds have nothing under their one chat
screen, so the server answers them with a new chat in the deleted chat's
list (`/chats/new?project_id=…`, which replaces the root) and the notice as
a toast: nothing of the deleted chat, its title included, stays. Should a
recede still reach the root (an older server), the app starts a new chat
itself. Deleting another chat (from the chat list, or the sidebar's long
press while a different chat shows) keeps its Turbo Stream and leaves the
screen as it is. The same for other destroys reached from their own page
(`ProjectsController#destroy` from a project's menu).

### A file (`chats/files/show`)

A chat's file chips (`messages/files/_chip`) and an answer's links to files
it made open the file's viewer, `/:account/chats/:number/files/:signed_id`
(the server's `docs/file-store.md`, "Previews"): a PDF's or an Office file's
pages as pictures rendered on the server (LibreOffice and poppler in a
sandbox, with the file's own fonts), a CSV as a table, Markdown and text as
an answer shows them, pictures, and HTML in a frame where nothing runs. So a
deck the assistant made shows as its slides without PowerPoint on the phone.

- The path configuration presents it full screen over the chat (`modal`,
  `full` on iOS; `hotwire://fragment/web/modal` on Android), titled with the
  file's name from `<title>`, with the app's close button. The page's own
  title and close are `native-hidden`, and its bar, then holding only
  Download, goes too once the app lists `file`.
- Share is the `file` component's: `connect` `{files}` with the file, then
  the PDF of its pages once they're rendered. Each `title` says what the
  file is, as its chip does (`"PowerPoint"`, `"PDF"`), and the apps add the
  verb: with two files, iOS's Share menu and Android's Share and Save
  dialogs list them by it. A build without the component gets the page's
  own Download, which opens as files always did (below).
- While the pages render, the page asks for its frame
  (`file_preview_pages`) again every second or so; nothing native.
- The page allows zooming (no `maximum-scale`); Android turns on its web
  view's pinch zoom for these pages only.

### Links the app handles itself

Nothing to do, but worth knowing:

- Links to another site open in an in-app browser. Links to files
  (`/rails/active_storage/...`, like a viewer's Download in a build without
  `file`) are downloaded with the person's session and open in Quick Look,
  which shows PDFs, images and Office documents with Share, Save to Files
  and Print. A chat's files themselves open in their viewer (above).
- In tab builds, a link to another tab's list (`/482139075/projects` from a
  chat) switches tabs instead of pushing a copy of the list. Sidebar builds
  push it over the chat.
- A link into another organization rebuilds the shell there.
- `recede_or_redirect_to(url, notice:)`, `refresh_…` and `resume_…` show the
  notice (or `alert`) as a toast.

## 8. Universal links

Links to chatwithwork.com in emails and messages should open the app.

Serve `GET /.well-known/apple-app-site-association` over HTTPS with
`Content-Type: application/json`, no redirect, and no authentication (Apple's
CDN fetches it). A controller outside any account (`disallow_account_scope`,
`skip_forgery_protection`), building the JSON from configuration so the team
ID stays out of the public app repository:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAMID.com.chatwithwork.app"],
        "components": [
          { "/": "/native/*", "exclude": true },
          { "/": "/users/auth/*", "exclude": true },
          { "/": "/*callback*", "exclude": true },
          { "/": "/oauth/*", "exclude": true },
          { "/": "/mcp/*", "exclude": true },
          { "/": "/rails/*", "exclude": true },
          { "/": "/admin*", "exclude": true },
          { "/": "/support/*", "exclude": true },
          { "/": "/chats*" },
          { "/": "/projects*" },
          { "/": "/settings*" },
          { "/": "/accounts*" },
          { "/": "/device*" },
          { "/": "/invitations/*" },
          { "/": "/shared/*" },
          { "/": "/users/password/edit*" },
          { "/": "/users/confirmation*" },
          { "/": "/*/chats*" },
          { "/": "/*/projects*" },
          { "/": "/*/settings*" },
          { "/": "/*/join/*" },
          { "/": "/*/device*" }
        ]
      }
    ]
  },
  "webcredentials": {
    "apps": ["TEAMID.com.chatwithwork.app"]
  }
}
```

- `TEAMID` is the Apple Developer team ID (`Rails.application.credentials.dig(:apple, :team_id)`).
- Staging serves the staging and development builds instead:
  `TEAMID.com.chatwithwork.app.staging` and `TEAMID.com.chatwithwork.app.debug`.
- Everything not listed (the marketing site, OAuth callbacks, the native
  handoff URLs) keeps opening in the browser. The callbacks matter most: an
  OAuth flow running in Safari must come back to Safari.
- `webcredentials` lets iOS offer the person's saved chatwithwork.com
  passwords in the sign-in sheet.

The Android app's `/.well-known/assetlinks.json` is in the Android repo's
contract.

## 9. Push notifications

The first notification: **"A change is waiting for your approval"**, when a
reply parks at a tool call waiting for its driver. Then "A question is
waiting for your answer" for MCP elicitation.

### Asking

The app offers notifications once per install, at the moment they help, never
right after signing in. The layout's hidden `notification-token` element
(with `data-bridge--notification-token-offers-value="true"`) sends `offer`
the first time a chat page shows a change or question waiting for the person
(`.thinking--approval`, reason `approval`), or an answer still working after
15 seconds (reason `answer`). The app then shows a short native explanation,
"Want a nudge when it's ready?", worded for the reason:

- `approval`: "Chat with Work can tell you when a change waits for your
  approval, so you can leave the app while it works."
- `answer`: "Chat with Work can tell you when an answer is ready, so you can
  leave the app while it works."

with Not now and Continue, then iOS's own prompt if the person continues. It
replies to `offer` as to `get`. An offer the app doesn't make (it offered
before, or iOS has its answer) replies at once with the current state. iOS
asks only once anyway; afterwards Settings › Notifications is the way to turn
them on. Android does the same on Android 13 and later, where
`POST_NOTIFICATIONS` is a runtime permission; earlier versions have nothing
to ask. (Builds before `offer` asked once after the first sign-in.)

### Registering a device

The app never talks to the server on its own. A page asks it for a token
through `notification-token` and posts it with the person's session and CSRF
token (`web/controllers/bridge/notification_token_controller.js`). When the
person allows notifications anywhere but the page itself (an offer, or
another page's Turn on), the app answers the latest `connect` of
every `notification-token` on screen again with the new state, so the page
registers the token without waiting for the next page (the bridge keeps a
message's callback, so a second reply reaches it):

- In Settings › Notifications, a "Push notifications" row in the apps, with
  `data-controller="bridge--notification-token"` and
  `data-bridge--notification-token-url-value="<%= native_push_registrations_path %>"`,
  and a Turn on button (`bridge--notification-token#enable`, which shows
  iOS's permission prompt the first time) and an Open Settings button
  (`#openSettings`, for someone who turned them off). native.css shows the
  right one from `data-push-status`.
- In the app layout, a hidden element with the same controller and no
  buttons, so a token that changed reaches the server (at most once a day per
  token, tracked in `localStorage`).

`POST /native/push_registrations` (JSON, signed in, CSRF-protected, outside
any account):

```json
{ "push_registration": { "token": "a1b2…", "platform": "ios", "environment": "sandbox", "app_id": "com.chatwithwork.app.debug" } }
```

- `token`: hex for APNs, the FCM registration token for Android.
- `environment`: `sandbox` or `production` (which APNs gateway); Android
  sends `production`.
- `app_id`: the bundle identifier (iOS), which is the APNs topic, or the
  package name (Android).

Answer `201` with `{ "id": …, "notification_key": "…" }`. Upsert by
`(platform, token)`: a token moves to whoever registers it last (someone else
signed in on that phone). Remember it in the session
(`session[:native_push_token] = token`).

**The notification key (2026-10-26).** `notification_key` is the phone's key
for fetching what its notifications say (below, "The words"): the same for as
long as the token stays its person's, so pages registering at once all get the
same one; signing out deletes it with the registration, and someone else
registering the token gets another. The page hands it to the app with
`notification-token`'s `key` `{key, token}`, and the app keeps it with the
token it belongs to, in a keychain group the app shares with its notification
service extension (`CWW_KEYCHAIN_GROUP`, readable after the phone's first
unlock, never in a backup). Until the app holds a key for the current token,
its replies say `needsKey: true`, and the page registers at once instead of
once a day. Signing out forgets it.

The model, outside any account (one phone gets every organization's
notifications for its person):

```ruby
# bin/rails generate model PushRegistration identity:references platform:string token:string environment:string app_id:string app_version:string last_registered_at:datetime
# add_index :push_registrations, [ :platform, :token ], unique: true
class PushRegistration < ApplicationRecord
  belongs_to :identity
  enum :platform, { ios: "ios", android: "android" }, validate: true
  validates :token, :environment, :app_id, presence: true
end
```

`Users::SessionsController#destroy`, before `super`: delete the registration
whose token is `session[:native_push_token]`, so the next person on that
phone doesn't get the last one's notifications.

### Sending

APNs over HTTP/2 with token authentication (a `.p8` key): the `apnotic` gem
is the usual client. Credentials: `apple.team_id`, `apple.push_key_id`,
`apple.push_key` (the `.p8` contents). Topic: the registration's `app_id`.
Gateway: `api.sandbox.push.apple.com` for `sandbox`, `api.push.apple.com`
for `production`. Android: Firebase Cloud Messaging HTTP v1 (the Android
contract).

A job per notification (`PushDeliveryJob`, shallow: find the
`PushRegistration`, call `deliver_now(payload)`). APNs answers `410
Unregistered` or `400 BadDeviceToken` for a token that's gone: destroy the
registration.

### The payload

Notifications go through Apple's and Google's servers, so they carry **no
content**: never a chat title, a question, an answer, a tool's arguments or a
file name. The organization's name and the service's name are fine.

```json
{
  "aps": {
    "alert": { "title": "Acme", "body": "A change is waiting for your approval in Slack." },
    "sound": "default",
    "thread-id": "chat-482139075-42",
    "category": "approval_waiting",
    "mutable-content": 1
  },
  "path": "/482139075/chats/42",
  "kind": "approval_waiting",
  "notification_id": "Zm9vYmFy--YmF6--cXV4"
}
```

- `path` (required): the page to open, on this server, starting with `/`.
  The app opens it inside the right organization (a chat as the root of the
  sidebar shell, other pages over it).
- `thread-id` groups a chat's notifications.
- `category` is the kind; the app registers one category per kind, each with
  what the notification says when the person hides previews in iOS's
  settings ("Your answer is ready."), never the chat's words.
- `kind`: `approval_waiting` or `input_requested` (body: "A question is
  waiting for your answer in Notion."), `answered`, `failed`, `handed_off`,
  `decisions_waiting`.
- `notification_id` and `mutable-content` (2026-10-26): an id the app can't
  read, for fetching the notification's words, sent only to someone whose
  "Show the chat and its answer" is on.

### The words (2026-10-26)

A notification shows the chat's title and the start of the answer, or, for a
change or question, what waits and what's to decide, like the web's browser
notifications, without those words passing through Apple: the app's
notification service extension (`NotificationService/`, the target
`ChatWithWorkNotifications`) fetches them from the server as the push
arrives, before iOS shows it:

```
GET /native/notifications/<notification_id>
Authorization: Bearer <the phone's notification key>
Accept: application/json

200 {"title": "Acme launch", "subtitle": "Waiting for your approval in Slack", "body": "Post the launch recap to #acme-launch"}
```

`subtitle` comes only for what waits ("Waiting for your approval in Slack",
"Waiting for your answer in Notion", "3 decisions are waiting for you").
`body` is at most 180 characters of plain text. The server answers only the
notification's recipient's phone, while they can still read the chat, and
gives their phone only what happened (the push's own words) once they turn
"Show the chat and its answer" off; anything else (no key, a key that isn't
theirs, an id that's wrong or more than a day old) is `401` or `404`. There's
no session or cookie, `Cache-Control: no-store`, and the id stays out of the
server's request logs. The extension waits at most 8 seconds, and shows the
push as it came when there's no key, the server answers anything but `200`,
or nothing comes in time. iOS hides title, subtitle and body when the person
turns previews off.

**Decisions digest (server, 2026-10-26).** Once 3 or more decisions wait for
someone, a new one's push becomes `decisions_waiting` instead of
`approval_waiting` or `input_requested`, at most every 30 minutes: title the
organization, body "4 decisions are waiting for you.", `path` the
organization's `/decisions`, `thread` `decisions-<account>`. The server keeps
sending Android each wait's own push until this app says it knows
`decisions_waiting`; iOS gets the digest now, and opens its `path` like any
other.

### When

In `Chat::ToolApprovals`, where a reply parks at calls waiting for a person
(`show_waiting_tool_calls`), queue one notification to the driver's identity
per chat and waiting call, unless that person has a push registration and
answered in the last minute (they're looking at it). Same for
`Chat::ToolInputs`. Add a toggle to Settings › Notifications ("Approvals and
questions on your phone") before adding any other kind.

## 10. Sign-in with a provider and connecting services

Google refuses OAuth inside an embedded web view
(`disallowed_useragent`), passkeys don't work there, and a provider's session
in Safari can't be reused. So both flows run in the system's secure browser
sheet (`ASWebAuthenticationSession` on iOS, an Auth Tab on Android), whose
cookies are Safari's, not the app's. The server hands the flow over to that
sheet with a one-time URL, and the sheet hands the result back by redirecting
to the app's callback scheme, `chatwithwork://`.

**iPhone and iPad (2026-10-27).** The server offers `platform=ios` no
provider sign-in at all, on the sign-in and sign-up pages alike: the App
Store asks an app that signs in with another company's account to offer
Sign in with Apple beside it (guideline 4.8). Email and a password, or a
passkey, sign in; the sign-in page tells someone who signed up with a
service to choose a password first. Android keeps them. Connecting services
(below) is unchanged on both.

**Sidebar builds** (section 11) get these flows from the ones Chat with
Work Desktop uses (`Native::SignInsController`, `Native::HandoffsController`,
`DesktopHandBack`), which also accept the apps' callbacks
`chatwithwork://sign-in` and `chatwithwork://handoff`. The page hands any form
that leaves for a vendor's sign-in to `auth-session` `start` with a
`/native/handoffs/<token>` URL, and provider sign-in forms with a
`/native/sign_ins/new?...&callback=chatwithwork://sign-in` URL, both
**non-ephemeral**, so the sheet uses Safari's own chatwithwork.com session:
the person signs in there once, and each later connection is one tap. The
callback URLs below are unchanged. The rest of this section is the original
design, kept for the record.

**In tab builds**, hide in the apps the "Sign in with Google / Slack /
Dropbox" buttons (`devise/sessions/new`, `devise/registrations/new`) and each
connector's Connect and Reconnect buttons (`shared/_connector`,
`shared/_connect_choice`, the connect dialog), replacing them with "Connect
services from chatwithwork.com on a computer". Disconnecting, pausing and
changing access work in the app as they are.

### Signing in with a provider (signed out)

1. On the sign-in and sign-up pages, in the apps, each provider form gets:

   ```erb
   data: { controller: "bridge--auth-session", action: "submit->bridge--auth-session#signIn",
           bridge__auth_session_url_value: new_native_sign_in_path(provider: "google_oauth2") }
   ```

   (`provider`: `google_oauth2`, `slack` or `dropbox`). The controller makes
   a PKCE pair, keeps the verifier, and asks the app to open
   `/native/sign_ins/new?provider=google_oauth2&challenge=…` in the sheet.

2. `GET /native/sign_ins/new` (in the sheet, so in Safari's session):
   validate `provider` against the three, store
   `session[:native_sign_in] = { "provider" => …, "challenge" => …, "started_at" => … }`,
   and render a page that posts to the provider's existing sign-in action
   (`/users/auth/google_oauth2`, `/slack_authorization` or
   `/dropbox_authorization`) with this session's CSRF token: a form submitted
   by script, with a visible Continue button for no-script.

3. The provider's flow runs as on the web and ends in a sign-in
   (`sign_in_and_redirect` in `OmniauthCallbacksController`, `sign_in` in
   `WorkToolAuthorizationsController`) and a redirect. One `after_action`
   in `ApplicationController` turns that redirect into the hand-back:

   ```ruby
   after_action :hand_sign_in_back_to_app, if: -> { session[:native_sign_in].present? && redirecting_within_site? }

   # A redirect to the provider is the flow still on its way; one back into
   # our own pages is where it ends.
   def redirecting_within_site?
     return false unless response.redirect?
     host = URI(response.location).host
     host.nil? || host == request.host
   end

   def hand_sign_in_back_to_app
     pending = session.delete(:native_sign_in)
     if current_identity
       token = NativeSignIn.issue(identity: current_identity, challenge: pending["challenge"])
       sign_out(:identity)                  # Safari keeps no session of ours
       response.location = "chatwithwork://sign-in?token=#{token}"
     else
       response.location = "chatwithwork://sign-in?" + { error: "failed", message: flash[:alert].to_s }.to_query
     end
   end
   ```

   (Redirects to `chatwithwork://` need `allow_other_host`; setting
   `response.location` directly sidesteps the check, so keep the target
   fixed as here.)

4. The sheet closes on the `chatwithwork://` redirect; the app hands the URL
   back to the page. The controller posts `token` and `verifier` (and the
   page's CSRF token) to `POST /native/sign_ins` in the web view, as a full
   page submission.

5. `POST /native/sign_ins`: find the `NativeSignIn` by the token's digest,
   check it's unexpired (two minutes) and unused, and that
   `Base64.urlsafe_encode64(Digest::SHA256.digest(params[:verifier]), padding: false)`
   equals its `challenge`; mark it used; `sign_in` and `remember_me` its
   identity; `redirect_to after_sign_in_path_for(identity)` (the recede, so
   the app rebuilds). On any failure, `redirect_to new_identity_session_path,
   alert: "That sign-in didn't finish. Try again."`.

   ```ruby
   # bin/rails generate model NativeSignIn identity:references token_digest:string:uniq challenge:string expires_at:datetime used_at:datetime
   class NativeSignIn < ApplicationRecord
     belongs_to :identity

     def self.issue(identity:, challenge:)
       token = SecureRandom.base58(32)
       create!(identity:, challenge:, token_digest: Digest::SHA256.hexdigest(token), expires_at: 2.minutes.from_now)
       token
     end
   end
   ```

   The verifier never leaves the web view, so a token that leaks (a link
   another app intercepted) can't be redeemed anywhere else.

### Connecting a service (signed in)

1. In the apps, each connector's Connect form (and Reconnect, and Add another
   account) gets `data: { controller: "bridge--auth-session", action:
   "submit->bridge--auth-session#handoff" }`. On submit the controller posts
   the form's action path and fields to `POST /native/handoffs`:

   ```json
   { "handoff": { "path": "/482139075/google_workspace_authorization", "params": { "access": "change" }, "return_to": "/482139075/settings?tab=connectors" } }
   ```

2. `POST /native/handoffs` (signed in, CSRF-protected): check `path` is one
   of the connector authorization actions (the `*_authorization` routes, the
   hosted MCP route, `/users/auth/google_oauth2` with a connector param),
   create a `NativeHandoff` (identity, user, path, params, `return_to`
   checked with `safe_return_path`, a token digest, five minutes, single use)
   and answer `{ "url": native_handoff_url(token) }`.

3. The controller asks the app to open that URL in the sheet.
   `GET /native/handoffs/:token`: mark the handoff used, sign its identity in
   for this browser session only (no remember), set
   `session[:native_handoff] = handoff.id`, and render the same kind of
   auto-submitting page as above, posting `params` to `path` with this
   session's CSRF token.

4. The connector's flow runs as on the web and ends in a redirect back into
   the app's pages (Settings › Connectors with a notice, or with an alert on
   failure). A second `after_action` hands it back:

   ```ruby
   after_action :hand_connection_back_to_app, if: -> { session[:native_handoff].present? && redirecting_within_site? }

   def hand_connection_back_to_app
     handoff = NativeHandoff.find_by(id: session.delete(:native_handoff))
     status = flash[:alert].present? ? "failed" : "connected"
     sign_out(:identity)
     response.location = "chatwithwork://handoff?" + { status:, message: (flash[:alert] || flash[:notice]).to_s, return_to: handoff&.return_to }.compact.to_query
   end
   ```

5. The sheet closes; the controller visits `return_to` with
   `Turbo.visit(…, { action: "replace" })`, and the page shows the new
   connection. A canceled sheet changes nothing.

### The callback URLs

| URL | Meaning |
|---|---|
| `chatwithwork://sign-in?token=T` | signed in with a provider; redeem T with the verifier |
| `chatwithwork://sign-in?error=failed&message=M` | the provider's sign-in failed; M is the alert |
| `chatwithwork://handoff?status=connected&message=M&return_to=P` | the service is connected |
| `chatwithwork://handoff?status=failed&message=M&return_to=P` | it isn't; M says why |

The scheme is `CWW_CALLBACK_SCHEME` in the iOS build settings; the same on
Android.

## 11. The sidebar

Builds that register the `sidebar` bridge component (so the user agent's
`bridge-components` lists it) drop the tab bar. `native_app.supports?(:sidebar)`
is the server's switch for anything that differs.

### The shape

- **One chat screen.** One navigator whose root is always a chat: the app
  opens on the organization's new chat (`links.new_chat` from the JSON below,
  remembered per organization, so it starts in the last list's project), or,
  launched again within ten minutes of leaving a chat that is still answering
  or waiting, on that chat. `/chats/new` and `/chats/<number>` replace the root
  (path configuration v2), so switching chats never stacks screens and the
  web view, shared by every screen, never reloads the app. Bots, projects and
  other pages are pushed over the chat; Settings and every form are sheets.
- **The bar.** The sidebar button on the leading side of the root
  (`sidebar.left`), New chat on the trailing side of every main screen
  (`square.and.pencil`), and the page's own `button`, `menu`, `form` and
  `share` beside them. A page's `button` with `nativeAction: "new-chat"` is
  left out.
- **The sidebar** slides in from the left and pushes the chat aside, opened by
  the bar's button or a swipe from the screen's left edge (on a root screen
  with nothing over it), closed by a tap or a swipe on the chat, or by picking
  something. Top to bottom: Decisions (below), the Chats | Bots switch (below), the list switcher (`list`, "Project" or
  "Showing"; its menu lists `lists`, then All projects… and New project), a
  search field (titles, natively; the first search loads `all=1`), New chat,
  from a server with neither `waiting.url` nor `links.decisions` the Decisions row (the list of
  `waiting.items`; earlier builds called it "Waiting for you"), from a server
  without `bots.items` the Bots row instead of the switch (`links.bots`, with
  `bots`' count, dot, or next run), Pinned (`pins`), the person's own sections (`sections`, below),
  then the chats under their `group` headings (under one "Other chats"
  heading instead when there are sections, as on the web)
  with a live dot while `state` is `processing` and an attention dot while
  `waiting`, the next page loading from `next` near the end. At the foot,
  the person and the organization; its menu lists `organizations` (each
  opening its `url`), All organizations, New organization, and Settings.

### The JSON

`GET /:account/native/sidebar` (`Native::SidebarsController`), with
`Accept: application/json`, the web view's cookies and the app's user agent:
no token of its own. `list=<key>` picks the list (the app remembers the
choice per organization), `all=1` returns every chat in it, and `next` is the
path of the following page. A signed-out request gets `401`.

```json
{
  "organization": {"id": "482139075", "name": "Northwind Studio", "initials": "NS"},
  "organizations": [{"id": "482139075", "name": "Northwind Studio", "initials": "NS", "current": true, "role": "admin", "url": "/482139075/chats/new"}],
  "person": {"name": "Maya Hart", "email": "maya@northwind.example", "initials": "MH", "avatar_url": null},
  "list": {"key": "recent", "name": "Private chats", "kind": "recent", "hq": false},
  "lists": [{"key": "recent", "name": "Private chats", "kind": "recent", "hq": false, "pinned": false, "current": true}],
  "links": {"new_chat": "/482139075/chats/new", "bots": "/482139075/bots", "settings": "/482139075/settings",
            "projects": "/482139075/projects", "new_project": "/482139075/projects/new",
            "organizations": "/accounts", "new_organization": "/accounts/new"},
  "waiting": {"count": 2, "url": "/482139075/decisions", "items": [
    {"key": "tool_call-311", "title": "Launch date in #launch", "url": "/482139075/decisions?decision=tool_call-311",
     "kind": "approval", "decision": "approval", "summary": "Post the launch date in #launch", "chat_url": "/482139075/chats/42",
     "project": "Website relaunch", "since": "2026-10-25T08:14:00Z",
     "asker": {"kind": "chat", "name": "Launch date in #launch", "project": "Website relaunch"}},
    {"key": "tool_call-318", "title": "Refund for order 1182", "url": "/482139075/decisions?decision=tool_call-318",
     "kind": "bot", "decision": "approval", "summary": "Refund order 1182 in full", "chat_url": "/482139075/chats/57",
     "project": "Website relaunch", "since": "2026-10-25T09:02:00Z",
     "asker": {"kind": "bot", "name": "Front desk", "project": "Website relaunch"}}]},
  "bots": {"count": 1, "attention": true, "next_run": null,
           "url": "/482139075/bots", "new_url": "/482139075/bots/new", "items": [BOT]},
  "pins": [CHAT],
  "sections": [SECTION],
  "chats": [CHAT],
  "next": "/482139075/native/sidebar?list=recent&before=41&asked=2026-10-24T09:00:00.000000Z"
}
```

where `CHAT` is `{"number": 42, "title": "…", "url": "/482139075/chats/42",
"state": "idle", "waiting": false, "project": "Website relaunch" or null,
"asked_at": "2026-10-25T08:12:00Z", "group": "Today", "actions": [ACTION]}`. A list's `kind` is
`recent`, `all` or `project`; a waiting item's `approval`, `question` or
`bot`; a chat's `state` `idle`, `processing` or `error`. Links that don't
apply are `null` (a guest's `new_chat`, `bots`, `projects` and
`new_project`), and so is `bots` for a guest. Every URL is a path on this
server.

**Decisions at the sidebar's top (2026-10-28).** As the web's sidebar does
(`decisions/_sidebar_button`), the app draws Decisions as a button of its
own at the top of the sidebar, just before the Chats | Bots switch, or at
the top where there's no switch (guests, older servers)
(`sidebar.decisions`). It's outlined like the list switcher, since it's the
one thing there that asks for the person: the list-checks symbol
(`checklist`), "Decisions" spelled out, and at its end `waiting.count` as a
small badge on the attention wash, its outline taking the attention edge,
or a quiet "None" at 0. VoiceOver reads "Decisions" and "N waiting" or
"None waiting". It opens `waiting.url` (or `links.decisions`). The same
data as before, no new keys. A server with neither `waiting.url` nor
`links.decisions` keeps the Decisions row lower in the sidebar instead. Builds from 2026-10-27 to
2026-10-28 drew it as a pill in the root screen's bar beside the sidebar
button (`shell.decisions`); that pill is gone, and returning to the
foreground or a `changed` refetches the JSON only while the sidebar is open
again (launch still fetches it once when deciding whether to reopen a
recent chat).

**Decisions (server, 2026-10-26).** `waiting` now lists decisions, not chats:
everything waiting for the person across their chats, agents, bots' runs
and the bots they handle (the server's `Decision`, `docs/decisions.md`).
`waiting.count` is what waits now, `waiting.snoozed` how many they put off,
and `waiting.url` the web Decisions page (`/:account/decisions`), also in
`links.decisions`. Each of the first 50 `items` keeps `title` (its chat's),
`kind` and `project` as before, and its `url` now opens the Decisions page
on it (`/:account/decisions?decision=<key>`), one decision at a time with its
card, "Why you" and the context below it; `chat_url` is its chat. New keys:
`key`, `decision` (`approval`, `question` (a server's), `ask` (the
assistant's own question with options, `ask_decision`), `draft`, `editor`,
`handoff`), `summary` (one line saying what's to decide) and `since`.
Opening `waiting.url` or an item's `url` in the web view is all a first
version needs: the page decides through the chat's own cards, swiping left
or right on it moves between decisions, and the sidebar's `changed` follows
its count.

**Who asks (server, 2026-10-27).** Each of `waiting.items` also carries
`asker`, `{"kind": "bot", "name": "Front desk", "project": "Website
relaunch"}` (`kind` `bot`, `agent` or `chat`, `project` null outside one),
the server's `Decision#asker`. The list of `waiting.items` (shown only from a
server without `waiting.url`, in the sidebar's Decisions row) leads each row with `asker.name`, then
`summary` and the project under it, as the web's decision row does. Without
`asker` the row is as before.

**Chats | Bots (server, 2026-10-27).** `bots` also carries `url` (the Bots
page), `new_url` (New bot) and `items`, the person's bots and the shared ones
they read, as the web sidebar's Bots view lists them (`bots/_sidebar_list`),
those that need them first. `BOT` is `{"id": 5, "name": "Front desk", "url":
"/482139075/bots/5", "group": "needs_you", "project": "Website relaunch",
"state": "waiting", "state_label": "Waiting for you", "tone": "attention",
"waiting": 1, "working": false, "next_run": null}`: `group` is `needs_you` or
`quiet`, already in order; `project` a shared bot's, null for a personal one;
`state` one of `waiting`, `failed`, `working`, `paused`, `next`, `listening`
and `idle` (`Bot::Overview#state`), with the web's words in `state_label`
and its `tone` (`attention`, `negative`, `live`, `positive`, or null);
`waiting` how many decisions wait for the person in it; `working` whether one
of its chats is answering now; `next_run` its next timed run, if any.

With `items`, the sidebar draws a segmented Chats | Bots switch just under
Decisions, above the list switcher, in place of the Bots row
(`sidebar.switch.chats`, `sidebar.switch.bots`): two equal halves, each its
icon and label centred together, the Bots half's dot hanging past its label. Its Bots half shows an attention dot, never a number,
while `bots.attention`: Decisions carries the one count. Chats shows the
sidebar as before. Bots keeps the same skeleton: a card in the list
switcher's place ("Bots in <organization>", how many bots, and how many are
working or waiting for the person), opening `url`; New bot where New chat
sits, opening `new_url`; then the bots, under "Needs you" and "Quiet" only
when both have some. Each row is the bot mark (with a live dot while
`working`), the name, a shared bot's project, and at its end `waiting` with
an attention dot when it's more than 0, else `state_label` with a dot in its
`tone`. A tap opens `url` like any sidebar link. With no bots it says "Your
bots, and the ones shared with you, show up here." and offers "Start from a
recipe" (`new_url`). The search field shows only with the chats. The app
remembers the chosen half per install. Guests get no `bots`, so no switch;
a server that sends no `items` keeps the Bots row. The sidebar keeps checking
every five seconds while open and a bot is `working`, as it does for a chat.

**Long press (2026-10-26).** Each `CHAT` carries `actions`, what the web
row's menu offers for it, in its order: `rename`, `pin` or `unpin`,
`section`, `project` and `delete`, the creator's own only where the web's
are (someone else's project chat offers Pin and Move to section). `ACTION`
is `{"key": "delete", "title": "Delete", "method": "delete", "url":
"/482139075/chats/42", "iosImage": "trash", "androidImage": "delete",
"confirm": "Delete this chat?", "destructive": true}`; `confirm` and
`destructive` only where they apply. A long press on a chat's row opens
them as a native menu (titles and symbols as sent, `destructive` in red).
Picking one with `method` `get` opens its `url` like any link (Rename and
the Move pages are sheets); any other goes to the page on screen as a reply
to its `sidebar` component's latest `connect`, `{action: "perform", url,
method, confirm, destructive}`, and the page sends it as the web's link
would: a Turbo request with that method, behind the native alert where
there's a `confirm`. Its answer lands on that page: deleting the chat on
screen replaces it with a new chat (section 7, "Deleting"), anything else
leaves the screen as it is, and the sidebar follows through `changed`.
Without `actions` (an older server) a long press does nothing.

**Sections (2026-10-26).** `sections` are the person's own sidebar
sections (the server's `ChatSection`, its `docs/ui/chat.md`, "Sections"),
in their order, the same in every list: `SECTION` is `{"id": 7, "name":
"Customers", "collapsed": false, "chats": [CHAT], "edit_url":
"/482139075/sidebar/sections/7/edit", "collapse_url":
"/482139075/sidebar/sections/7/collapse", "position_url":
"/482139075/sidebar/sections/7/position"}`, its `chats` this list's chats
in it, newest question first, all of them (not paged). The list's `chats`
(and `all=1`'s) are then only those in no section. The app draws each
section after Pinned as a heading (a caret, its name and how many chats it
holds) with its chats below it unless `collapsed`, then the list's chats
under "Other chats". A tap on a heading opens or closes it at once and
sends `collapse_url` to the page on screen like a chat's action (`post`
closes it, `delete` opens it), so every device shows it the same; a long
press offers Rename (`edit_url`, a sheet). The search covers the sections'
chats too. Without `sections` (an older server) the list is as before.

### Keeping it current

The app fetches the JSON when the sidebar opens (if anything changed since),
every five seconds while the sidebar is open and one of its chats is
working, and when the list goes stale while it's open. Two things mark it
stale: returning to the foreground, and a page saying so: every signed-in
page in these builds carries one hidden
`<div data-controller="bridge--sidebar">`, subscribed to the person's own
sidebar streams, which sends `changed` (debounced) when a stream message for
the web's sidebar arrives. Either refetches at once if the sidebar is open;
a closed sidebar refetches when it next opens.

## 12. The composer

Builds that register `composer` draw the chat's composer themselves. The web
composer (`#new_message`) carries `bridge--composer`
(`web/controllers/bridge/composer_controller.js`) and stays in the page,
hidden by native.css, so every rule it carries still holds: locks, who may
steer, the queue, files waiting for their scan, the model and web search.
The conversation then ends just above the page's bottom, and the app lays
its web view out above its own composer, which rides on the keyboard.

### Messages

Web to app: `connect`, then `state` whenever something changes (an
upload's progress, a lock, an answer starting or ending), both with:

```json
{ "placeholder": "Reply to Chat with Work", "text": "", "locked": false, "lockReason": null,
  "working": false, "stopping": false,
  "models": [{"name": "Gemini 3.8 Flash", "rate": "About 2 credits per answer", "selected": true, "searchesWeb": true}],
  "webSearch": {"on": false, "disabled": false, "note": "..."},
  "dictation": {"url": "/482139075/dictations"}, "csrfToken": "...",
  "attachments": [{"id": "7", "name": "plan.pdf", "size": "1.2 MB", "contentType": "application/pdf", "uploading": true, "progress": 40}],
  "acceptsFiles": true }
```

`webSearch` and `dictation` are `null` where the composer doesn't offer
them.

**The yes before the first question (2026-10-27).** Before anything a
person sends goes to a model, the page asks them once, in a dialog of its
own over the chat (the server's `docs/model-consent.md`), naming the
companies that run the models and where. The app needs nothing for it: a
`send` puts the words in the web composer as always, and the web composer
waits for the dialog before it submits. Agree sends them; Not now sends
nothing and the page connects again, so the reply to `connect` carries the
words as `text` and the app's empty field takes them back. Until the
person agrees, `dictation` is `null` (dictation goes to a model too), and a
`state` brings it back once they do. A dictation posted anyway is refused
with `403` and `{error, model_consent: true}`, whose `error` the app shows
like any other. `text` is what the web composer already holds (a shared link, a
restored draft), files left out: the app starts an empty field with it.
Each new web composer (a chat draws it again as an answer starts and ends)
connects again, and the app always answers the latest `connect`.

App to web, as replies to `connect`, `{action, ...}`:

| Action | Data | Does |
|---|---|---|
| `send` | `{text}` | puts the words (and the files already attached) in the web composer and sends; while `working` that steers the answer, or waits where the person may not steer it. The app doesn't send while a file uploads. |
| `stop` | | the running answer's Stop |
| `model` | `{index}` | picks `models[index]` |
| `webSearch` | `{on}` | switches web search |
| `attach` | `{files: [{name, type, data}]}` | uploads files the app picked, photographed or scanned (`data` base64) like any file the composer takes |
| `remove` | `{id}` | takes a file out |
| `text` | `{text}` | dictated words, for the web composer too |

### What the app draws

- The field, with `placeholder`, growing to about five lines. Locked: the
  field disabled and `lockReason` above it.
- The files on their way as chips with their progress and a remove button.
- The controls, as on the web: "+", the model (a menu of `models`, hidden
  while locked or working), and Send. While `working` and the field is
  empty, Stop ("Stop response", sends `stop`) stands in Send's place; once
  there are words or files, Stop and Send show side by side, Send steering
  the answer, and an emptied field leaves Stop alone again. Stop is
  disabled while `stopping`. A light haptic on Send, a firmer one on Stop.
- "+" opens a sheet: the latest photos in a row (the app asks for the photo
  library the first time the sheet opens; Photos and the camera work
  without it), Camera, Photos (`PHPickerViewController`), Files, Scan
  (VisionKit's document camera, the pages sent as one PDF), Dictate, and Web
  search as a switch when `webSearch` isn't `null`. Photos go as JPEGs at
  most 2560 pixels on their longest side; files over 25 MB are refused with
  a note to attach them from a computer.

### Dictation

The app records itself, AAC in an `.m4a` (`audio/mp4`), at most five
minutes. While it listens and while it transcribes, dictation takes the
field's place, as the web composer's `[data-dictating]` line does, since
nobody types meanwhile: a live dot and "Listening", the microphone's level
as bars across the composer, newest on the right (still bars lit to the
level under Reduce Motion), and the time listened (`0:12`); then
"Transcribing…" alone (`composer.dictation`, read by VoiceOver as one
element with the time in words). A stop button sits in Send's place and a
cancel button on the left; the rest of the bar steps aside. The field
comes back, with the words, once they're transcribed. It posts the
recording as the multipart field `audio` to `{base}{dictation.url}` with the web view's cookies, `X-CSRF-Token:
csrfToken` and `Accept: application/json`. `200 {text}` puts the words in
the field and sends `text`; `{error}` (403 without credits, 413, 415, 429,
502) shows the server's words above the composer. Never the system's speech
recognizers.

## 13. Live Activities, widgets and sharing

### Live Activities

While a chat's composer says `working`, the app keeps a Live Activity for
it (ActivityKit, push type `token`), which iOS shows once the person leaves
the app: "Chat with Work · <organization>", "Answering" and a timer since it
started. (ActivityKit starts activities only while the app is in front, so
the app starts it as the answer starts, not as the person leaves.) Never the chat's title or anything from it. It registers the
activity's push token with the server:

```
POST /:account/chats/:number/live_activity
Content-Type: application/json, X-CSRF-Token: <the composer's csrfToken>, the web view's cookies
{ "live_activity": { "token": "<hex>", "app_id": "com.chatwithwork.app", "environment": "sandbox" | "production" } }
```

While the answer runs, the server pushes what it's doing (2026-10-26): event
`update` at `apns-priority` 5 (which Apple doesn't count against the app's
budget), at most every 3 seconds, with a `stale-date` an hour ahead, and the
content state `{phase: "answering", message, step, steps}`: `message` the
step it's on in the words of the chat's activity line ("Searching Todoist",
"Reading 3 files in Drive", "Running code", "Writing the answer", or
"Answering" between steps), `step` its kind for the app's symbol (`search`,
`list`, `read`, `use`, `plan`, `run`, `ask`, `write`, `answer`), and `steps`
how many it took so far. Never a query, file name, title or text, and an MCP
server or computer only as "an MCP server" or "a computer". Builds that read
only `phase` and `message` show the step's words too.

The server ends it when the answer ends, with an APNs `liveactivity` push,
event `end`, content state `{phase, message}`: `phase` is `answered`,
`approval_waiting`, `input_requested`, `failed` or `stopped` (the person's
Stop, or out of credits), `message` generic words for it, shown on the Lock
Screen for 15 minutes. The app shows the message, or its own words for the
phase. A tap opens the chat (`chatwithwork://open?path=/482139075/chats/42`).
The app also ends it itself when that chat's composer says it's done while
the person is in the app; in the background it leaves the end to the
server's push. The activity's attributes are `ChatActivityAttributes` in
`Shared/`, which the widget extension draws: the mark, "Chat with Work ·
<organization>", the step's symbol and words, and the timer with how many
steps.

### Widgets and the app's links

The widget extension (`Widgets/`, `ChatWithWorkWidgets`) adds "Ask Chat
with Work" in small, medium and the Lock Screen's circle: static, with
nothing from the person's chats. It opens the app's own links, which the
app registers as its URL scheme (`CWW_CALLBACK_SCHEME`, `chatwithwork`):

| Link | Opens |
|---|---|
| `chatwithwork://new-chat` | a new chat in the last list chosen |
| `chatwithwork://new-chat?dictate=1` | a new chat that starts listening as its composer connects |
| `chatwithwork://new-chat?title=&text=&url=` | a new chat with those words in its composer, never sent: `/chats/new?title=&text=&url=` (the server fills its composer), and the native field too |
| `chatwithwork://new-chat?shared=<uuid>` | a new chat that attaches the files the share extension left under that name |
| `chatwithwork://open?path=/482139075/chats/42` | that page of this server, a chat as the root |

A new chat already on screen takes the words, files and dictation as it
is, without loading again. `sign-in` and `handoff` are the browser sheet's
callbacks (section 10) and open nothing.

### The share extension

"Chat with Work" in the share sheet (`ShareExtension/`,
`ChatWithWorkShare`) takes text, a web link, and up to ten images or
files. Text and links go into the `new-chat` link as `text`, `url` and
`title`; files (at most 25 MB each) go into the app group's container
(`CWW_APP_GROUP`, `group.com.chatwithwork.app` and the staging and debug
builds' own), one folder per share, whose name the link carries as
`shared`. The app reads and deletes it, and hands the files to the
composer with `attach` once it connects.

## Testing the contract

- **The playground** (`Playground/server.py` in the iOS repo) implements this
  contract with fixture pages, so it shows what each section should produce,
  and the app's UI tests run against it.
- **The app against your Rails app**: `bin/dev` binds to `0.0.0.0`; build the
  Debug app with `CWW_BASE_URL = http:/$()/<your-computer>.local:3000` in
  `Config/Local.xcconfig`, or launch it with
  `-CWWBaseURL http://<your-computer>.local:3000`.
- **Rails tests**: request tests with the app's user agent
  (`"Mozilla/5.0 (iPhone) Chat with Work; platform=ios; version=1.0.0; build=1; Hotwire Native iOS; Turbo Native iOS; bridge-components: [button menu toast]"`)
  for the 401, the recede after sign-in, the sign-in redirect after sign-out,
  the titles, and the hidden chrome; and that a browser user agent sees none
  of it.
