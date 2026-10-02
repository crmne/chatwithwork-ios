import { BridgeComponent, BridgeElement } from "@hotwired/hotwire-native-bridge"

// The form's submit button, in the navigation bar.
//
//   <%= form_with model: @project, data: { controller: "bridge--form",
//         action: "turbo:submit-start->bridge--form#submitStart turbo:submit-end->bridge--form#submitEnd" } do |form| %>
//     …
//     <%= form.submit "Create project", data: { bridge__form_target: "submit", bridge_title: "Create" } %>
//   <% end %>
export default class extends BridgeComponent {
  static component = "form"
  static targets = ["submit"]

  connect() {
    super.connect()

    const submit = new BridgeElement(this.submitTarget)
    const data = { title: submit.title, color: this.bridgeElement.bridgeAttribute("color") }
    this.send("connect", data, () => this.submitTarget.click())
  }

  disconnect() {
    super.disconnect()
    this.send("disconnect")
  }

  submitStart() {
    this.send("disableSubmit")
  }

  submitEnd() {
    this.send("enableSubmit")
  }
}
