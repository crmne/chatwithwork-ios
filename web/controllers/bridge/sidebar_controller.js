import { BridgeComponent } from "@hotwired/hotwire-native-bridge"
import { Turbo } from "@hotwired/turbo-rails"

// The phone apps draw the sidebar natively from /native/sidebar's JSON
// (Native::SidebarsController). This hidden element, on every signed-in page
// in builds that list the "sidebar" component, tells the app when that list
// changed, so it fetches it again: the page subscribes to the person's own
// sidebar streams ([user, "chats"] and [user, :sidebar]), whose messages
// target the web sidebar's rows, pins, lists and Bots row, none of which the
// app's pages render.
//
//   <div hidden data-controller="bridge--sidebar"></div>
//
// Web to app: connect {}, changed {} (at most twice a second).
// App to web, as replies to connect: {action: "perform", url, method, confirm?, destructive?}, a chat's action
// from a long press in the native sidebar (the JSON's chat "actions"). This page sends it as the web's own link
// would: a "get" is a visit, anything else a Turbo request with that method, asking first where there's a confirm
// (a native alert, through bridge--confirm), so its answer lands here (a new chat after deleting this one).
const SIDEBAR_TARGET = /sidebar|chat_list|pinned|chat_list_switcher/
const DEBOUNCE = 500

export default class extends BridgeComponent {
  static component = "sidebar"

  connect() {
    super.connect()
    this.heard = this.heard.bind(this)
    document.addEventListener("turbo:before-stream-render", this.heard)
    this.send("connect", {}, message => this.perform(message.data))
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
    clearTimeout(this.timer)
    super.disconnect()
  }

  heard(event) {
    const stream = event.target
    const target = `${stream.getAttribute("target") || ""} ${stream.getAttribute("targets") || ""}`
    if (!SIDEBAR_TARGET.test(target)) return

    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.send("changed", {}), DEBOUNCE)
  }
}
