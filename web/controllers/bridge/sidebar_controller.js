import { BridgeComponent } from "@hotwired/hotwire-native-bridge"
import { Turbo } from "@hotwired/turbo-rails"

// The phone apps' sidebar. This hidden element is on every signed-in page in
// builds that list the "sidebar" component. Its connect names the sidebar
// page (SidebarsController, the web's own sidebar on its own), which builds
// that know it keep in their drawer, and the path the page on screen belongs
// under (data-sidebar-belongs-to: a bot's chat raises its bot's row), which
// they hand that page to mark. Older builds draw the sidebar natively from
// /native/sidebar's JSON (Native::SidebarsController), and this element
// tells them when it changed, so they fetch it again: the page subscribes to
// the person's own sidebar streams ([user, "chats"] and [user, :sidebar]),
// whose messages target the web sidebar's rows, pins, lists and Bots row,
// none of which the app's pages render.
//
//   <div hidden data-controller="bridge--sidebar" data-bridge--sidebar-page-value="/482139075/sidebar"></div>
//
// Web to app: connect {page, belongsTo} (older servers send {}), again when the page changes its address in place,
// changed {} (at most twice a second).
// App to web, as replies to connect: {action: "perform", url, method, confirm?, destructive?}, a chat's action
// from a long press in the native sidebar (the JSON's chat "actions"). This page sends it as the web's own link
// would: a "get" is a visit, anything else a Turbo request with that method, asking first where there's a confirm
// (a native alert, through bridge--confirm), so its answer lands here (a new chat after deleting this one).
const SIDEBAR_TARGET = /sidebar|chat_list|pinned|chat_list_switcher/
const DEBOUNCE = 500

export default class extends BridgeComponent {
  static component = "sidebar"
  static values = { page: String }

  connect() {
    super.connect()
    this.heard = this.heard.bind(this)
    document.addEventListener("turbo:before-stream-render", this.heard)
    document.addEventListener("address:replaced", this.#readdressed)
    // The apps take the connect only if the address it carries is still the page's as it arrives, and a page can
    // change its address as it connects (Decisions' ?view=&decision=, helpers/address.js). So it goes once the
    // controllers connecting with this one have, and again whenever the address changes after.
    queueMicrotask(() => this.#connectHere())
  }

  #connectHere() {
    if (!this.element.isConnected || this.connectedFor === window.location.href) return

    this.connectedFor = window.location.href
    this.send("connect", this.#page(), message => this.perform(message.data))
  }

  #readdressed = () => {
    if (this.connectedFor) this.#connectHere()
  }

  perform({ action, url, method, confirm, destructive } = {}) {
    if (action !== "perform" || typeof url !== "string" || !url.startsWith("/")) return

    if (!method || method === "get") {
      Turbo.visit(url)
      return
    }

    const link = document.createElement("a")
    link.href = url
    link.hidden = true
    link.dataset.turboMethod = method
    link.dataset.turboFrame = "_top"
    if (confirm) link.dataset.turboConfirm = confirm
    if (destructive) link.dataset.bridgeDestructive = "true"
    document.body.append(link)
    link.click()
    link.remove()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.heard)
    document.removeEventListener("address:replaced", this.#readdressed)
    this.connectedFor = null
    clearTimeout(this.timer)
    super.disconnect()
  }

  #page() {
    if (!this.pageValue) return {}

    const belongsTo = document.querySelector("[data-sidebar-belongs-to]")?.dataset.sidebarBelongsTo || null
    return { page: this.pageValue, belongsTo }
  }

  heard(event) {
    const stream = event.target
    const target = `${stream.getAttribute("target") || ""} ${stream.getAttribute("targets") || ""}`
    if (!SIDEBAR_TARGET.test(target)) return

    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.send("changed", {}), DEBOUNCE)
  }
}
