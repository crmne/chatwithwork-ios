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
//
// The layout's hidden element also offers notifications at the moment they
// make sense (data-bridge--notification-token-offers-value="true"): the
// first time a chat waits for the person (.thinking--approval), or an answer
// is still working after OFFER_AFTER. The app shows its own explanation
// once per install, only while the person hasn't decided, and answers like
// "get" (docs/server-contract.md in the apps' repositories).
const OFFER_AFTER = 15000
const OFFER_CHECK_EVERY = 2000

export default class extends BridgeComponent {
  static component = "notification-token"
  static values = { url: String, offers: Boolean }

  connect() {
    super.connect()
    this.send("connect", {}, message => this.#update(message.data, false))
    if (this.offersValue) this.#watchForOffer()
  }

  disconnect() {
    clearInterval(this.offerTimer)
    super.disconnect()
  }

  enable(event) {
    event?.preventDefault()
    this.send("get", {}, message => this.#update(message.data, true))
  }

  openSettings(event) {
    event?.preventDefault()
    this.send("openSettings")
  }

  // Offers once per page: the app keeps its own once-per-install memory.
  #watchForOffer() {
    let workingSince = null
    this.offerTimer = setInterval(() => {
      if (this.element.dataset.pushStatus && this.element.dataset.pushStatus !== "not_determined") return this.#stopWatching()

      if (document.querySelector(".thinking--approval")) return this.#offer("approval")

      const working = document.querySelector("#typing_indicator .thinking:not(.thinking--approval)")
      workingSince = working ? (workingSince || Date.now()) : null
      if (workingSince && Date.now() - workingSince >= OFFER_AFTER) this.#offer("answer")
    }, OFFER_CHECK_EVERY)
  }

  #offer(reason) {
    this.#stopWatching()
    this.send("offer", { reason }, message => this.#update(message.data, true))
  }

  #stopWatching() {
    clearInterval(this.offerTimer)
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
