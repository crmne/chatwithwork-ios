import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// A flash message, shown as a native toast. In the app the flash partial
// renders each message as a hidden element with this controller instead of
// the web toast:
//
//   <div data-controller="bridge--toast" data-bridge-type="notice"
//        data-turbo-temporary hidden><%= message %></div>
//
// data-bridge-type: notice, info, alert or error. data-bridge-message, or
// else the element's text. data-turbo-temporary keeps a toast from showing
// again when Turbo restores the page from its cache.
export default class extends BridgeComponent {
  static component = "toast"

  connect() {
    super.connect()

    const element = this.bridgeElement
    const message = (element.bridgeAttribute("message") || this.element.textContent || "").trim()
    if (message) this.send("show", { message, type: element.bridgeAttribute("type") || "notice" })
  }

  // Also usable as an action: data-action="bridge--toast#show".
  show(event) {
    event?.preventDefault()
    const element = this.bridgeElement
    const message = (element.bridgeAttribute("message") || "").trim()
    if (message) this.send("show", { message, type: element.bridgeAttribute("type") || "notice" })
  }
}
