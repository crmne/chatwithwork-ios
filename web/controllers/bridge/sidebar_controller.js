import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

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
const SIDEBAR_TARGET = /sidebar|chat_list|pinned|chat_list_switcher/
const DEBOUNCE = 500

export default class extends BridgeComponent {
  static component = "sidebar"

  connect() {
    super.connect()
    this.heard = this.heard.bind(this)
    document.addEventListener("turbo:before-stream-render", this.heard)
    this.send("connect", {})
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
