import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// A navigation bar button that clicks this element. One per page.
//
//   <%= link_to new_chat_path, data: { controller: "bridge--button",
//         bridge_title: "New chat", bridge_ios_image: "square.and.pencil",
//         bridge_android_image: "edit_square" } do %>…<% end %>
//
// data-bridge-side: "right" (default) or "left". data-bridge-native-action:
// a stable id for anything the app does itself beyond clicking (the apps
// never key behavior off the title, which gets translated).
export default class extends BridgeComponent {
  static component = "button"

  connect() {
    super.connect()

    const element = this.bridgeElement
    const side = element.bridgeAttribute("side") || "right"
    const data = {
      title: element.title,
      iosImage: element.bridgeAttribute("ios-image"),
      androidImage: element.bridgeAttribute("android-image"),
      color: element.bridgeAttribute("color"),
      nativeAction: element.bridgeAttribute("native-action")
    }

    this.send(side, data, () => this.element.click())
  }

  disconnect() {
    super.disconnect()
    this.send("disconnect")
  }
}
