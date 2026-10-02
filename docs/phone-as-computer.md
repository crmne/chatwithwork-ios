# The phone as a computer

Status: design note, not built. 2026-10-02.

Chat with Work already lets the assistant search a person's computer through
the Local Agent (`cww`, crmne/chatwithwork-local-agent): the computer pairs
with the device flow, dials out to `/local_agent`, and answers read-only MCP
tools that appear to the model as `local_<device id>_<tool>`. The phone can be
one more such computer, answering for what lives only on the phone, each kind
of data turned on by its owner: calendars, contacts, reminders, photos, and
files the person picks.

The server side is the Rails app's `docs/local-agent.md` and
`docs/security/local-agent.md`; this note covers what changes for a phone.

## What the assistant could ask

Read-only tools, named like the computer's (`roots`, `search`, `list`,
`read`) so `LocalAgent::Device` treats them alike, with the kind of data in
the arguments, or with names of their own if the server's allowlist grows:

| Data | Framework | Tools | Permission |
|---|---|---|---|
| Calendars | EventKit | search events by text and date range; list a day | Calendars, full or read access |
| Reminders | EventKit | list open reminders by list and due date | Reminders |
| Contacts | Contacts | search by name, company, email | Contacts (iOS 18 lets the person share only some) |
| Photos | PhotoKit, Vision | search by date, place and the text in a photo (recognized on the phone) | Photos, limited library respected |
| Files | Files (document picker, security-scoped bookmarks) | the same four tools as `cww`, inside folders the person picked | none beyond the pick |

Nothing writes, as with `cww`. Text that leaves the phone is what a tool
returns for one call, cached by the server like any computer's
(`RemoteResource`, `provider: "local"`, 30 days unread).

## Pairing

The device flow (RFC 8628) with DPoP proofs, as `cww` pairs, but the person is
already signed in inside the app, so it can be one tap:

1. Settings › Connectors › Computers shows "Use this iPhone" in the app (a
   bridge component, say `computer`, so the page knows the app can be one).
2. The app makes its key, posts `POST /local_agent/device_authorizations`
   (`name`: the device name the person sees in Settings, `platform`: `ios`,
   `client_version`), and opens `verification_uri_complete` in a sheet of the
   web view, where `/device` asks the person to confirm who they are, as it
   does for a computer.
3. The app polls `/local_agent/token`, keeps the refresh token in the
   Keychain (this device only, after first unlock), and connects.

The one server change pairing needs: proofs are `alg: EdDSA` with Ed25519
keys today. The Secure Enclave only holds P-256 keys, so either accept `ES256`
proofs from phones (a key that can never leave the phone, the better
choice), or keep the Ed25519 key in the Keychain (CryptoKit's
`Curve25519.Signing`), which works with the server as it is.

## Staying reachable

A computer keeps its socket open; a phone can't. iOS suspends an app shortly
after it leaves the screen, and its socket with it. So:

- While the app is open, it holds the `/local_agent` socket like `cww`
  (`URLSessionWebSocketTask`, the `mcp` subprotocol, which needs no Action
  Cable framing) and answers at once.
- When a tool call targets a phone that isn't connected, the server sends a
  wake push (`"content-available": 1`, `kind: "local_agent_wake"`), and the
  app gets about 30 seconds in the background to connect, answer what's
  waiting, and disconnect. iOS throttles these pushes and drops them when the
  phone is in Low Power Mode or the app was force-quit, so this is best
  effort.
- Otherwise the call answers as an offline computer's does ("Carmine's iPhone
  is offline"), and the model says so. Calls don't queue: by the time the
  phone comes back, the person has moved on.

## Privacy and control

- Each kind of data is off until the person turns it on in the app (a native
  screen, since it asks iOS for the permission), and can be turned off there
  or in iOS Settings. The phone answers only for kinds that are on: like
  `cww`, the device enforces what may be read; the server's checks are
  defense in depth.
- Limits on the phone: results per call, characters per read, calls per
  minute, and a local log of every call, viewable in the app.
- Settings › Computers lists the phone with the activity log
  (`local_agent.*` AuditEvents, never contents), Pause, and Disconnect, as for
  a computer. The taint rule applies: once a chat has read phone data, every
  change in it asks again.

## Where it fits in this app

Nothing in the app depends on it yet; these are the seams it would use:

- **A module of its own** (`ChatWithWork/LocalAgent/`): the key and token
  store, the pairing flow, the socket, and one tool provider per kind of
  data, behind a small protocol so each is tested alone.
- **`PushNotifications`** routes `kind: "local_agent_wake"` to it instead of
  opening a page (and asks for the `remote-notification` background mode).
- **`AppShell`** connects the socket when the app becomes active and the phone
  is paired, and disconnects on sign-out or when the organization changes:
  one key pairs into one organization, as with `cww`.
- **`BridgeRegistry`** gains the `computer` component for the Settings row.
- **Info.plist** gains a usage description per kind of data, each saying the
  assistant reads it only when the person asks a question that needs it.
