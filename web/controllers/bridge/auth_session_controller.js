import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

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
// The app's sheet ends at chatwithwork://sign-in?token=… (or ?error=…) and
// chatwithwork://handoff?status=…&return_to=….
export default class extends BridgeComponent {
  static component = "auth-session"
  static values = {
    url: String,
    redeemUrl: { type: String, default: "/native/sign_ins" },
    handoffUrl: { type: String, default: "/native/handoffs" },
    returnTo: String,
    ephemeral: Boolean
  }

  async signIn(event) {
    event.preventDefault()
    event.stopImmediatePropagation()

    const { verifier, challenge } = await pkcePair()
    const url = withParams(this.urlValue, { challenge })

    this.send("start", { url, ephemeral: this.ephemeralValue }, message => {
      const result = callbackParams(message.data)
      if (result.token) {
        submit(this.redeemUrlValue, { token: result.token, verifier })
      } else if (result.error !== "canceled") {
        this.#fail(result.message || "Signing in didn't finish. Try again.")
      }
    })
  }

  async handoff(event) {
    event.preventDefault()
    event.stopImmediatePropagation()

    const form = event.target.closest("form") || this.element.closest("form")
    const params = Object.fromEntries([...new FormData(form)].filter(([name]) => !["authenticity_token", "_method"].includes(name)))
    const returnTo = this.returnToValue || window.location.pathname + window.location.search

    const response = await fetch(this.handoffUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ handoff: { path: new URL(form.action).pathname, params, return_to: returnTo } })
    })
    if (!response.ok) return this.#fail("That service can't be connected from the app right now.")

    const { url } = await response.json()
    this.send("start", { url, ephemeral: this.ephemeralValue }, message => {
      const result = callbackParams(message.data)
      if (result.error === "canceled") return
      window.Turbo.visit(result.return_to || returnTo, { action: "replace" })
    })
  }

  #fail(message) {
    this.dispatch("failed", { detail: { message } })
  }
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
