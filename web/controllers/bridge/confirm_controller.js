import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Turbo's data-turbo-confirm as a native alert, through the `alert`
// component. In the app the layout puts this on <body>:
//
//   <body data-controller="bridge--confirm">
//
// The confirm message becomes the alert's title. A request that deletes
// (DELETE, or data-bridge-destructive="true" on the form or button) gets a
// destructive button labelled "Delete"; set the label with
// data-bridge-confirm="Disconnect" and add detail with
// data-bridge-description. On the web, Turbo keeps its own confirm.
export default class extends BridgeComponent {
  static component = "alert"

  #previous = null

  connect() {
    super.connect()

    const forms = window.Turbo?.config?.forms
    if (!forms) return

    this.#previous = forms.confirm
    forms.confirm = (message, element, submitter) => this.#confirm(message, element, submitter)
  }

  disconnect() {
    super.disconnect()

    const forms = window.Turbo?.config?.forms
    if (forms && this.#previous !== null) forms.confirm = this.#previous
  }

  #confirm(message, form, submitter) {
    const attribute = name => submitter?.getAttribute?.(`data-bridge-${name}`) ?? form?.getAttribute?.(`data-bridge-${name}`)
    const method = (form?.querySelector?.("input[name=_method]")?.value || form?.getAttribute?.("method") || "").toLowerCase()
    const deletes = method === "delete"
    const destructive = attribute("destructive") ? attribute("destructive") === "true" : deletes

    const data = {
      title: message,
      description: attribute("description"),
      destructive,
      confirm: attribute("confirm") || (deletes ? "Delete" : "OK"),
      dismiss: attribute("dismiss") || "Cancel"
    }

    // Only a confirmation answers; a dismissed alert leaves the submission
    // unstarted, which is what cancelling means to Turbo.
    return new Promise(resolve => this.send("show", data, () => resolve(true)))
  }
}
