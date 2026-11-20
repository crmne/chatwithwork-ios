import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// The phone apps that show the web composer rather than drawing their own (they list `web-composer` and leave
// `composer` out; docs/ui/native-apps.md, "The composer"; their docs/server-contract.md, "The web composer"). The page
// draws and sends everything; the app only needs to know when an answer runs, to start its Live Activity or Live Update,
// and has a way to hand the composer what came from outside the page: files shared into the app, and a widget's or a
// shortcut's Dictate. On the web composer (#new_message), beside bridge--composer, which only builds that draw their own
// composer connect.
//
// Web to app: connect {state}, then state {state} whenever it changes:
//   state = { working, waiting, run, revision, startedAt, mark, csrfToken, acceptsFiles, dictates, menu }
// +working+, +waiting+, +run+, +revision+, +startedAt+ and +mark+ are bridge--composer's own (the server's
// LiveActivity::Run and Chat#live_mark, opaque and nothing from the chat). +acceptsFiles+ is false while the composer is
// locked. +dictates+ is whether the composer's microphone is offered now (an install with a model to transcribe with,
// and the person's yes to their words going to models). +menu+ is whether one of the composer's menus is open (the +
// menu, the model picker, the mode picker, the slash menu): Android's Back closes it then, as Back closes a menu there,
// rather than leaving the page under it.
// The chat draws its composer again as an answer starts and ends, and each new one connects again.
//
// App to web, as replies to connect: {action, ...}
//   attach {files: [{name, type, data}]}  files shared into the app, base64, uploaded here like any file the composer
//                                         takes (bridge--composer's attach)
//   dictate                               starts the composer's dictation, as its microphone button does
//   closeMenus                            closes the composer's open menus (Android's Back while +menu+)
export default class extends BridgeComponent {
  static component = "web-composer"

  connect() {
    super.connect()
    // The composer's own attributes say what changes here (its classes, its data-live-*); its button for dictation
    // comes and goes with the editor and the yes to models.
    this.observer = new MutationObserver(() => this.#changed())
    this.observer.observe(this.element, { attributes: true, attributeFilter: [ "class", "data-live-run", "data-live-revision", "data-live-waiting", "data-live-mark", "data-live-started-at" ] })
    // Its menus open and close inside it: a button's aria-expanded, the slash menu's list's hidden, and the model
    // picker, a dropdown open while the focus is in it.
    this.menus = new MutationObserver(() => this.#changed())
    this.menus.observe(this.element, { subtree: true, attributes: true, attributeFilter: [ "aria-expanded", "hidden" ] })
    // The + menu and the model picker are popovers (helpers/composer_overlay.js), whose toggle doesn't bubble.
    this.element.addEventListener("toggle", this.toggled = () => this.#changed(), true)
    this.element.addEventListener("focusin", this.focusMoved = () => this.#changed())
    this.element.addEventListener("focusout", this.focusMoved)
    window.addEventListener("model-consent:given", this.consented = () => this.#changed())
    // The apps take the connect only if the address it carries is still the page's as it arrives (helpers/address.js).
    document.addEventListener("address:replaced", this.readdressed = () => this.#connectToApp())
    queueMicrotask(() => { if (this.element.isConnected) this.#connectToApp() })
  }

  disconnect() {
    this.observer?.disconnect()
    this.menus?.disconnect()
    this.element.removeEventListener("toggle", this.toggled, true)
    this.element.removeEventListener("focusin", this.focusMoved)
    this.element.removeEventListener("focusout", this.focusMoved)
    window.removeEventListener("model-consent:given", this.consented)
    document.removeEventListener("address:replaced", this.readdressed)
    clearTimeout(this.timer)
    super.disconnect()
  }

  #connectToApp() {
    this.lastState = JSON.stringify(this.#state())
    this.send("connect", JSON.parse(this.lastState), message => this.#perform(message.data))
  }

  #changed() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#changedNow(), 150)
  }

  #changedNow() {
    const state = JSON.stringify(this.#state())
    if (state === this.lastState) return
    this.lastState = state
    this.send("state", JSON.parse(state))
  }

  #perform({ action, ...data } = {}) {
    switch (action) {
      case "attach": return (data.files || []).forEach(file => this.#attach(file))
      case "dictate": return this.#dictate()
      case "closeMenus": return this.#closeMenus()
    }
  }

  #attach({ name, type, data }) {
    const attachments = this.#controller("attachments")
    if (!attachments || !data || this.element.classList.contains("composer--locked")) return

    const bytes = Uint8Array.from(atob(data), character => character.charCodeAt(0))
    attachments.upload(new File([ bytes ], name || "file", { type: type || "application/octet-stream" }))
  }

  // The microphone's own click, so everything it checks (the yes to models, credits, a recording already going) holds.
  #dictate() {
    const button = this.element.querySelector("[data-dictation-target=button]")
    if (button && !button.disabled && !this.element.classList.contains("composer--locked")) button.click()
  }

  #closeMenus() {
    for (const element of this.element.querySelectorAll("[data-controller~='composer-menu'], [data-controller~='dropdown']")) {
      for (const identifier of [ "composer-menu", "dropdown" ]) {
        this.application.getControllerForElementAndIdentifier(element, identifier)?.close()
      }
    }
    for (const popover of this.element.querySelectorAll(":popover-open")) popover.hidePopover()
    this.#controller("slash-menu")?.close()
    if (document.activeElement?.closest(".dropdown") && this.element.contains(document.activeElement)) document.activeElement.blur()
  }

  #controller(identifier) {
    return this.application.getControllerForElementAndIdentifier(this.element, identifier)
  }

  #state() {
    const element = this.element
    const consentNeeded = document.getElementById("model_consent") !== null
    const locked = element.classList.contains("composer--locked")

    return {
      working: element.classList.contains("composer--working"),
      waiting: element.dataset.liveWaiting === "true",
      run: element.dataset.liveRun || null,
      revision: element.dataset.liveRevision ? Number(element.dataset.liveRevision) : null,
      startedAt: element.dataset.liveStartedAt ? Number(element.dataset.liveStartedAt) : null,
      mark: element.dataset.liveMark || null,
      csrfToken: document.querySelector("meta[name=csrf-token]")?.content || null,
      acceptsFiles: !locked,
      dictates: Boolean(element.dataset.dictationUrlValue && element.querySelector("[data-dictation-target=button]")) && !consentNeeded && !locked,
      menu: Boolean(element.querySelector("[aria-expanded=true], [data-slash-menu-target=list]:not([hidden]), :popover-open, .dropdown:focus-within"))
    }
  }
}
