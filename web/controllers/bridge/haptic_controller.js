import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Taptic feedback when something happens on the page.
//
//   <%= form_with url: chat_tool_call_approval_path(chat, record),
//         data: { controller: "bridge--haptic", bridge_feedback: "success",
//                 action: "turbo:submit-start->bridge--haptic#vibrate" } do %>
//
// data-bridge-feedback: success (default), warning, error, selection, light,
// medium, heavy, soft or rigid.
export default class extends BridgeComponent {
  static component = "haptic"

  vibrate() {
    const feedback = this.bridgeElement.bridgeAttribute("feedback") || "success"
    this.send("vibrate", { feedback })
  }
}
