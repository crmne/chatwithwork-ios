import { BridgeComponent, BridgeElement } from "@hotwired/hotwire-native-bridge"

// A navigation bar menu whose items click this page's elements. One per page.
//
//   <div data-controller="bridge--menu" hidden>
//     <%= button_to "Pin", chat_pin_path(@chat), data: { bridge__menu_target: "item",
//           bridge_ios_image: "pin", bridge_android_image: "keep" } %>
//     <%= link_to "Delete", chat_path(@chat), data: { bridge__menu_target: "item",
//           bridge_ios_image: "trash", bridge_destructive: "true",
//           turbo_method: :delete, turbo_confirm: "Delete this chat?" } %>
//   </div>
//
// On the controller element, optionally: data-bridge-side ("left" or
// "right"), data-bridge-label, data-bridge-ios-image (the button's symbol),
// and data-bridge-header (a title above the items). A menu on the left or
// with a header is a chooser (the organization switcher): its button shows
// the label as text. Otherwise the label is the button's accessibility label. On items:
// data-bridge-title (else the text), data-bridge-ios-image,
// data-bridge-android-image, data-bridge-destructive, data-bridge-checked,
// and data-bridge-native-action (a stable id, never the title).
//
// Items that change, like Pin turning into Unpin after a Turbo Stream,
// re-send the whole menu.
export default class extends BridgeComponent {
  static component = "menu"
  static targets = ["item"]

  #scheduled = false

  connect() {
    super.connect()
    this.#scheduleSend()
  }

  disconnect() {
    super.disconnect()
    this.send("disconnect")
  }

  itemTargetConnected() {
    this.#scheduleSend()
  }

  itemTargetDisconnected() {
    this.#scheduleSend()
  }

  #scheduleSend() {
    if (this.#scheduled) return
    this.#scheduled = true
    queueMicrotask(() => {
      this.#scheduled = false
      if (this.element.isConnected) this.#send()
    })
  }

  #send() {
    const element = this.bridgeElement
    const items = this.itemTargets.map(target => {
      const item = new BridgeElement(target)
      return {
        title: item.title,
        iosImage: item.bridgeAttribute("ios-image"),
        androidImage: item.bridgeAttribute("android-image"),
        destructive: item.bridgeAttribute("destructive") === "true",
        checked: item.bridgeAttribute("checked") === "true",
        nativeAction: item.bridgeAttribute("native-action")
      }
    })

    const data = {
      items,
      color: element.bridgeAttribute("color"),
      side: element.bridgeAttribute("side"),
      label: element.bridgeAttribute("label"),
      iosImage: element.bridgeAttribute("ios-image"),
      header: element.bridgeAttribute("header")
    }

    const targets = this.itemTargets
    this.send("connect", data, message => {
      const target = targets[message.data.index]
      if (target?.isConnected) new BridgeElement(target).click()
    })
  }
}
