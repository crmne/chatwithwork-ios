import { BridgeComponent } from "@hotwired/hotwire-native-bridge"
import { Turbo } from "@hotwired/turbo-rails"

// Sign-ins and connector OAuth in the system's secure browser sheet
// (ASWebAuthenticationSession on iOS, an Auth Tab on Android), because
// Google refuses OAuth in web views and passkeys only work in the browser.
// docs/server-contract.md describes the server's half.
//
// Signed out, on each "Sign in with …" form:
//   data-controller="bridge--auth-session"
//   data-action="submit->bridge--auth-session#signIn"
//   data-bridge--auth-session-url-value="/native/sign_ins/new?provider=google_oauth2"
//
// Signed in, on each connector's Connect form:
//   data-controller="bridge--auth-session"
//   data-action="submit->bridge--auth-session#handoff"
//
// Or once, on <body>, in the sidebar builds (NativeApp#sidebar?), which
// hands over every form the way Chat with Work Desktop's controller does:
// a sign-in form marked data-desktop-sign-in="<provider>", and any form
// whose action leaves for a vendor's sign-in (handoff-pattern, the server's
// NativeHandoff.client_pattern):
//   data-controller="bridge--auth-session"
//   data-bridge--auth-session-handoff-pattern-value="^(?:/\d{7,})?/..."
//   data-bridge--auth-session-new-sign-in-url-value="/native/sign_ins/new"
//
// The app's sheet ends at chatwithwork://sign-in?token=… (or ?error=…) and
// chatwithwork://handoff?status=…&return_to=….
export default class extends BridgeComponent {
  static component = "auth-session"
  static values = {
    url: String,
    redeemUrl: { type: String, default: "/native/sign_ins" },
    handoffUrl: { type: String, default: "/native/handoffs" },
    newSignInUrl: { type: String, default: "/native/sign_ins/new" },
    handoffPattern: String,
    returnTo: String,
    ephemeral: Boolean
  }

  connect() {
    super.connect()
    if (this.hasHandoffPatternValue) {
      this.intercept = this.intercept.bind(this)
      this.passThrough = new WeakSet()
      document.addEventListener("submit", this.intercept, true)
    }
  }

  disconnect() {
    if (this.intercept) document.removeEventListener("submit", this.intercept, true)
    super.disconnect()
  }

  // Capturing, so Turbo and the form's own controllers never see a submit
  // that goes to the browser instead.
  intercept(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || this.passThrough.has(form)) return

    if (form.dataset.desktopSignIn) {
      this.signIn(event, withParams(this.newSignInUrlValue, { provider: form.dataset.desktopSignIn }))
    } else if (this.#handsOff(form)) {
      this.handoff(event, form)
    }
  }

  async signIn(event, startUrl = this.urlValue) {
    event.preventDefault()
    event.stopImmediatePropagation()

    const { verifier, challenge } = await pkcePair()
    const url = withParams(startUrl, { challenge, callback: SIGN_IN_CALLBACK })

    this.send("start", { url, ephemeral: this.ephemeralValue }, message => {
      const result = callbackParams(message.data)
      if (result.token) {
        submit(this.redeemUrlValue, { token: result.token, verifier })
      } else if (result.error !== "canceled") {
        this.#fail(result.message || "Signing in didn't finish. Try again.")
      }
    })
  }

  async handoff(event, form = event.target.closest("form") || this.element.closest("form")) {
    event.preventDefault()
    event.stopImmediatePropagation()

    const submitter = event.submitter
    const params = Object.fromEntries([...new FormData(form, submitter)].filter(([name]) => !["authenticity_token", "_method"].includes(name)))
    const returnTo = this.returnToValue || window.location.pathname + window.location.search
    const action = new URL(form.action, window.location.href)

    const response = await fetch(this.handoffUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ handoff: { path: action.pathname + action.search, params, return_to: returnTo, callback: HANDOFF_CALLBACK } })
    })
    if (response.status === 422 && this.passThrough) {
      // Not an action the server hands over: submit it here after all.
      this.passThrough.add(form)
      return form.requestSubmit(submitter)
    }
    if (!response.ok) return this.#fail("That service can't be connected from the app right now.")

    const { url } = await response.json()
    this.send("start", { url, ephemeral: this.ephemeralValue }, message => {
      const result = callbackParams(message.data)
      if (result.error === "canceled") return
      if (result.error) return this.#fail("That connection didn't finish. Try again.")

      const failed = result.status !== "connected"
      const note = result.message || (failed ? "That connection didn't finish. Try again." : "Connected.")
      document.addEventListener("turbo:load", () => toast(note, failed ? "alert" : "notice"), { once: true })
      Turbo.visit(sitePath(result.return_to) || returnTo, { action: "replace" })
    })
  }

  #fail(message) {
    this.dispatch("failed", { detail: { message } })
    toast(message, "alert")
  }

  // A POST to a vendor's sign-in on this site, not a DELETE or PATCH riding
  // on a POST (button_to's _method).
  #handsOff(form) {
    if (form.method !== "post" || form.querySelector("input[name='_method']")) return false
    const action = new URL(form.action, window.location.href)
    return action.origin === window.location.origin && new RegExp(this.handoffPatternValue).test(action.pathname)
  }
}

// Where the server hands the browser's flow back to (NativeApp::CALLBACKS).
const SIGN_IN_CALLBACK = "chatwithwork://sign-in"
const HANDOFF_CALLBACK = "chatwithwork://handoff"

// A native toast, through the toast component's own element.
function toast(message, type) {
  const element = document.createElement("div")
  element.hidden = true
  element.dataset.controller = "bridge--toast"
  element.dataset.bridgeType = type
  element.dataset.turboTemporary = ""
  element.textContent = message
  document.body.append(element)
}

// Only a path on this site, never another origin's.
function sitePath(path) {
  return typeof path === "string" && path.startsWith("/") && !path.startsWith("//") ? path : null
}

function callbackParams(data) {
  if (data.error) return { error: data.error }
  try {
    return Object.fromEntries(new URL(data.url).searchParams)
  } catch {
    return { error: "failed" }
  }
}

async function pkcePair() {
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  const verifier = base64url(bytes)
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))
  return { verifier, challenge: base64url(new Uint8Array(digest)) }
}

function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

function withParams(path, params) {
  const url = new URL(path, window.location.origin)
  Object.entries(params).forEach(([name, value]) => url.searchParams.set(name, value))
  return url.pathname + url.search
}

function csrfToken() {
  return document.querySelector("meta[name=csrf-token]")?.content
}

function submit(action, fields) {
  const form = document.createElement("form")
  form.method = "post"
  form.action = action
  form.dataset.turbo = "false"
  Object.entries({ ...fields, authenticity_token: csrfToken() }).forEach(([name, value]) => {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.append(input)
  })
  document.body.append(form)
  form.submit()
}
