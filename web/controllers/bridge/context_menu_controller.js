import { BridgeComponent, BridgeElement } from "@hotwired/hotwire-native-bridge"
import { clipboardHTML } from "helpers/clipboard_helpers"

// A message's actions as one native menu, opened from a "more" button. It
// goes on the message itself, so the hidden copy source beside the actions
// is one of its targets:
//
//   <div class="message message--assistant" data-controller="markdown clipboard bridge--context-menu">
//     <pre data-clipboard-target="source" data-bridge--context-menu-target="copySource" hidden>…the message as text…</pre>
//     …
//     <div class="message__actions">
//       <button data-bridge--context-menu-target="item" data-bridge-title="Copy"
//               data-bridge-ios-image="doc.on.doc" data-bridge-copy="true">…</button>
//       <button data-bridge--context-menu-target="item" data-bridge-title="Retry" …>…</button>
//       <button class="message__action message__more" data-bridge--context-menu-target="trigger"
//               data-action="bridge--context-menu#show" aria-label="More actions">…</button>
//     </div>
//   </div>
//
// Items take data-bridge-title (else the aria-label or text),
// data-bridge-ios-image, data-bridge-android-image and
// data-bridge-destructive. An item with data-bridge-copy="true" copies the
// copySource target's text natively (a page can't write the clipboard
// without a tap of its own), so it never clicks back. An answer (whose
// clipboard controller copies Markdown) also sends copyHtml, the rich text
// the web copies beside it, unless its reader chose to copy answers as
// Markdown in Settings; apps that know copyHtml put both on the clipboard.
export default class extends BridgeComponent {
  static component = "context-menu"
  static targets = ["item", "trigger", "copySource"]

  async show(event) {
    event?.preventDefault()

    const anchor = this.hasTriggerTarget ? this.triggerTarget : this.element
    const rect = anchor.getBoundingClientRect()
    const targets = [...this.itemTargets]
    const copyText = this.hasCopySourceTarget ? this.copySourceTarget.textContent.trim() : null
    const copyHtml = copyText && this.#copiesRichText ? await clipboardHTML(copyText) : null

    const items = targets.map(target => {
      const item = new BridgeElement(target)
      return {
        title: item.title,
        iosImage: item.bridgeAttribute("ios-image"),
        androidImage: item.bridgeAttribute("android-image"),
        destructive: item.bridgeAttribute("destructive") === "true",
        copy: item.bridgeAttribute("copy") === "true" ? copyText : null,
        copyHtml: item.bridgeAttribute("copy") === "true" ? copyHtml : null,
        nativeAction: item.bridgeAttribute("native-action")
      }
    })

    const data = {
      items,
      rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
      scroll: { x: window.scrollX, y: window.scrollY },
      title: this.bridgeElement.bridgeAttribute("title")
    }

    this.send("show", data, message => {
      const target = targets[message.data.index]
      if (target?.isConnected) new BridgeElement(target).click()
    })
  }

  get #copiesRichText() {
    return this.element.dataset.clipboardMarkdownValue === "true" &&
      document.querySelector("meta[name='copy-answers-as']")?.content !== "markdown"
  }
}
