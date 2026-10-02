import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// The native search bar, driving the page's own filter. Put it beside the
// existing search controller; each query lands in the input target as if
// typed, so `input->search#filter` runs unchanged.
//
//   <div data-controller="search bridge--search">
//     <input type="search" data-search-target="input" data-bridge--search-target="input"
//            data-action="input->search#filter" placeholder="Search your chats">
//
// Also dispatches bridge--search:queried with { query }.
export default class extends BridgeComponent {
  static component = "search"
  static targets = ["input"]

  connect() {
    super.connect()

    const placeholder = this.bridgeElement.bridgeAttribute("placeholder") ||
      (this.hasInputTarget ? this.inputTarget.placeholder : null)

    this.send("connect", { placeholder }, message => {
      const query = message.data.query ?? ""
      if (this.hasInputTarget) {
        this.inputTarget.value = query
        this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
      }
      this.dispatch("queried", { detail: { query } })
    })
  }
}
