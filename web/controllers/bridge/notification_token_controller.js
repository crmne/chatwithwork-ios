import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Push notifications for this device: the row in Settings > Notifications,
// and a hidden element in the app's layout that keeps the server's copy of
// the token current.
//
//   <div data-controller="bridge--notification-token"
//        data-bridge--notification-token-url-value="<%= native_push_registrations_path %>">
//     <button data-action="bridge--notification-token#enable">Turn on</button>
//     <button data-action="bridge--notification-token#openSettings">Open Settings</button>
//   </div>
//
// The element gets data-push-status (authorized, provisional, ephemeral,
// denied or not_determined) so CSS can show the right button. A token is
// posted when the person turns notifications on, and on any page at most
// once a day while they're on.
export default class extends BridgeComponent {
  static component = "notification-token"
  static values = { url: String }

  connect() {
    super.connect()
    this.send("connect", {}, message => this.#update(message.data, false))
  }

  enable(event) {
    event?.preventDefault()
    this.send("get", {}, message => this.#update(message.data, true))
  }

  openSettings(event) {
    event?.preventDefault()
    this.send("openSettings")
  }

  #update(state, force) {
    this.element.dataset.pushStatus = state.status
    this.dispatch("changed", { detail: state })

    if (state.token && (force || this.#due(state.token))) this.#register(state)
  }

  #due(token) {
    try {
      const last = Number(localStorage.getItem(`push-registration:${token}`) || 0)
      return Date.now() - last > 24 * 60 * 60 * 1000
    } catch {
      return true
    }
  }

  async #register(state) {
    const response = await fetch(this.urlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body: JSON.stringify({ push_registration: { token: state.token, platform: state.platform, environment: state.environment, app_id: state.appId } })
    })

    if (response.ok) {
      try { localStorage.setItem(`push-registration:${state.token}`, String(Date.now())) } catch {}
    }
  }
}
