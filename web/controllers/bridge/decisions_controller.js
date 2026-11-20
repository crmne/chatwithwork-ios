import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// The phone apps' Decisions button at the end of the bar (docs/ui/native-apps.md, "Decisions in the bar"; their
// docs/server-contract.md, "Decisions in the bar"). On every page but Decisions the bar's last button is Decisions, in
// the attention tint with a count while some wait; on Decisions it's New chat. The page says how many wait for the
// person here, live: the count inside it follows their [user, :sidebar] stream, as the sidebar's Decisions row does, and
// it loads again as the page comes back from the background, when the streams may have missed a change.
//
// Web to app: connect {waiting, here, url}, then count {waiting} whenever it changes
//   waiting  how many decisions wait for the person in this organization (snoozed ones left out), as the sidebar says
//   here     whether this page is Decisions (the bar's button is New chat there)
//   url      Decisions, absolute, which the button opens
// App to web: nothing.
export default class extends BridgeComponent {
  static component = "decisions"
  static values = { url: String, countUrl: String, here: Boolean }

  connect() {
    super.connect()
    this.waiting = this.#count()
    this.observer = new MutationObserver(() => this.#changed())
    this.observer.observe(this.element, { childList: true, subtree: true, characterData: true })
    document.addEventListener("visibilitychange", this.returned = () => { if (document.visibilityState === "visible") this.#reload() })
    // The apps take a message only while the address it carries is the page's (helpers/address.js).
    document.addEventListener("address:replaced", this.readdressed = () => this.#connectToApp())
    queueMicrotask(() => { if (this.element.isConnected) this.#connectToApp() })
  }

  disconnect() {
    this.observer?.disconnect()
    document.removeEventListener("visibilitychange", this.returned)
    document.removeEventListener("address:replaced", this.readdressed)
    super.disconnect()
  }

  #connectToApp() {
    this.send("connect", { waiting: this.waiting, here: this.hereValue, url: this.urlValue })
  }

  #changed() {
    const waiting = this.#count()
    if (waiting === this.waiting) return
    this.waiting = waiting
    this.send("count", { waiting })
  }

  #reload() {
    const frame = this.element.querySelector("turbo-frame#native_decisions")
    if (!frame || !this.countUrlValue || !navigator.onLine) return
    if (frame.getAttribute("src") === this.countUrlValue) frame.reload()
    else frame.src = this.countUrlValue
  }

  #count() {
    return Number(this.element.querySelector(".sidebar__meta-count")?.textContent.trim()) || 0
  }
}
