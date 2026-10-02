import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// The system share sheet for a link.
//
// A button that opens it:
//   <button data-controller="bridge--share" data-action="bridge--share#share"
//           data-bridge-url="<%= shared_chat_url(@share_link.token) %>"
//           data-bridge-title="<%= @chat.display_title %>">Share</button>
//
// Or a share button in the navigation bar, with
// data-bridge--share-button-value="true". The url defaults to the page and
// the title to the document's.
export default class extends BridgeComponent {
  static component = "share"
  static values = { button: Boolean }

  connect() {
    super.connect()
    if (this.buttonValue) this.send("connect", this.#data)
  }

  disconnect() {
    super.disconnect()
    if (this.buttonValue) this.send("disconnect")
  }

  share(event) {
    event?.preventDefault()
    this.send("share", this.#data, message => {
      this.dispatch("shared", { detail: message.data })
    })
  }

  get #data() {
    const element = this.bridgeElement
    return {
      url: element.bridgeAttribute("url") || window.location.href,
      title: element.bridgeAttribute("title") || document.title,
      text: element.bridgeAttribute("text"),
      color: element.bridgeAttribute("color")
    }
  }
}
