import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// The phone apps' native composer (their docs/server-contract.md, "The composer"). The app draws the composer itself,
// docked above the keyboard, and this controller, on the web composer (#new_message), drives the web one, which stays
// in the page hidden (native.css), so every rule it carries holds: locks, who may steer, the queue, files waiting for
// their scan, the model, and web search. The chat draws its composer again as an answer starts and ends, and each new
// one connects again with what it is now.
//
// Web to app: connect {state}, then state {state} whenever it changes (an upload's progress, a lock):
//   state = { overlay, visible, placeholder, text, locked, lockReason, working, stopping, models: [{name, rate, selected, searchesWeb}],
//             webSearch: {on, disabled, note} | null, dictation: {url} | null, csrfToken,
//             attachments: [{id, name, size, contentType, uploading, progress}], acceptsFiles }
// +text+ is the words the web composer holds (a shared link, a restored draft), files left out, for the app's empty field.
// Until the person says yes to their words going to models (model_consent_controller.js), +dictation+ is null, and a
// send waits for the page's dialog: agreeing sends it, while Not now connects again, so the app's field gets its words
// back.
// App to web, as replies to connect: {action, ...}
//   send {text}        the words, then Send as the web's button would (steering a running answer, or waiting where
//                      the person may not steer it)
//   stop               the running answer's Stop
//   model {index}      picks a model from state.models
//   webSearch {on}     switches web search
//   attach {files: [{name, type, data}]}  files the app picked, scanned, or photographed, base64, uploaded here like
//                      any file the composer takes
//   remove {id}        takes a file out again
//   text {text}        dictated words (the app records, and posts the audio to dictation.url itself)
//   layout {height, width}  the composer's overlay height and web viewport width in native units
export default class extends BridgeComponent {
  static component = "composer"

  connect() {
    super.connect()
    this.observer = new MutationObserver(() => this.#changed())
    this.observer.observe(this.element, { childList: true, subtree: true, attributes: true, characterData: true })
    // Native views sit above the web view, including its modal top layer.
    // Hide the native composer while a page dialog owns the screen, keeping
    // its draft. Watch removal too: Turbo can replace an open dialog.
    this.dialogs = new MutationObserver(records => {
      if (records.some(record => record.target instanceof HTMLDialogElement ||
        [ ...record.addedNodes, ...record.removedNodes ].some(node => node.nodeType === Node.ELEMENT_NODE &&
          (node.matches("dialog") || node.querySelector("dialog"))))) this.#changed()
    })
    this.dialogs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: [ "open" ] })
    this.element.addEventListener("lexxy:upload-progress", this.progressed = () => this.#changed())
    window.addEventListener("model-consent:given", this.consented = () => this.#changed())
    window.addEventListener("model-consent:declined", this.declined = () => this.#connectToApp())
    window.addEventListener("resize", this.resized = () => this.#layout(this.layout))
    this.#connectToApp()
  }

  disconnect() {
    this.observer?.disconnect()
    this.dialogs?.disconnect()
    this.element.removeEventListener("lexxy:upload-progress", this.progressed)
    window.removeEventListener("model-consent:given", this.consented)
    window.removeEventListener("model-consent:declined", this.declined)
    window.removeEventListener("resize", this.resized)
    document.documentElement.style.removeProperty("--native-composer-height")
    clearTimeout(this.timer)
    super.disconnect()
  }

  #connectToApp() {
    this.lastState = JSON.stringify(this.#state())
    this.send("connect", JSON.parse(this.lastState), message => this.#perform(message.data))
  }

  #changed() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      const state = JSON.stringify(this.#state())
      if (state === this.lastState) return
      this.lastState = state
      this.send("state", JSON.parse(state))
    }, 150)
  }

  #perform({ action, ...data } = {}) {
    switch (action) {
      case "send": return this.#sendText(data.text || "")
      case "stop": return this.element.querySelector("a.chat-prompt__stop")?.click()
      case "model": return this.element.querySelectorAll(".model-picker__option")[data.index]?.click()
      case "webSearch": return this.#switchWebSearch(Boolean(data.on))
      case "attach": return (data.files || []).forEach(file => this.#attach(file))
      case "remove": return this.#remove(data.id)
      case "text": return this.element.dispatchEvent(new CustomEvent("dictation:text", { detail: { text: data.text || "", final: true } }))
      case "layout": return this.#layout(data)
    }
  }

  #layout(data) {
    if (!data || !Number.isFinite(data.height) || !Number.isFinite(data.width) || data.height < 0 || data.width <= 0) return

    this.layout = data
    const height = Math.min(window.innerHeight, data.height * window.innerWidth / data.width)
    document.documentElement.style.setProperty("--native-composer-height", `${height}px`)
  }

  #sendText(text) {
    const chat = this.#controller("chat")
    const attachments = this.#controller("attachments")
    // Files still uploading would be lost from the editor's value: the app sends once they're done (state.attachments).
    if (!chat?.hasInputTarget || chat.attachmentsUploading) return

    // The editor's value is the words and the files' attachment nodes after them, as restoreFiles builds it.
    const files = (attachments?.storedAttachments || []).map(file => file.outerHTML).join("")
    chat.inputTarget.value = (text.trim() ? chat.htmlFromPlainText(text) : "") + files
    // Lexxy tells the composer its value changed on its next frame.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      chat.updateButtonState()
      if (chat.canSubmit()) chat.submitFormActions()
    }))
  }

  #switchWebSearch(on) {
    const checkbox = this.element.querySelector(".chat-prompt__web-search input[type=checkbox]")
    if (checkbox && !checkbox.disabled && checkbox.checked !== on) checkbox.click()
  }

  #attach({ name, type, data }) {
    const attachments = this.#controller("attachments")
    if (!attachments || !data) return

    const bytes = Uint8Array.from(atob(data), character => character.charCodeAt(0))
    attachments.upload(new File([ bytes ], name || "file", { type: type || "application/octet-stream" }))
  }

  #remove(id) {
    const figure = this.element.querySelector(`figure.attachment[data-lexical-node-key="${CSS.escape(String(id))}"]`)
    if (figure) this.#controller("attachments")?.removeAttachment(figure)
  }

  // The file's own name, from Lexxy's node; its caption holds the size too.
  #fileName(figure) {
    const node = this.#controller("attachments")?.nodeFor(figure)
    return node?.fileName || figure.querySelector(".attachment__name")?.textContent.trim() || "file"
  }

  #controller(identifier) {
    return this.application.getControllerForElementAndIdentifier(this.element, identifier)
  }

  #state() {
    const element = this.element
    const editor = element.querySelector("lexxy-editor")
    const lock = [ ...element.querySelectorAll(".chat-prompt__lock") ].find(lock => !lock.hidden)
    const webSearch = element.querySelector(".chat-prompt__web-search input[type=checkbox]")
    // The dialog that asks for the yes is on the page only while it's missing (model_consents/_dialog).
    const consentNeeded = document.getElementById("model_consent") !== null
    const dictation = element.dataset.dictationUrlValue && element.querySelector("[data-dictation-target=button]") && !consentNeeded

    return {
      overlay: true,
      visible: !document.querySelector("dialog:modal"),
      placeholder: editor?.getAttribute("placeholder") || "",
      text: this.#controller("chat")?.promptText || "",
      locked: element.classList.contains("composer--locked"),
      lockReason: lock?.textContent.trim().replace(/\s+/g, " ") || null,
      working: element.classList.contains("composer--working"),
      stopping: Boolean(element.querySelector("button.chat-prompt__stop[disabled]")),
      models: [ ...element.querySelectorAll(".model-picker__option") ].map(option => ({
        name: option.dataset.modelSelectNameParam,
        rate: option.dataset.modelSelectRateParam || null,
        selected: option.getAttribute("aria-selected") === "true",
        searchesWeb: option.dataset.modelSelectWebSearchParam === "true"
      })),
      webSearch: webSearch ? {
        on: webSearch.checked,
        disabled: webSearch.disabled,
        note: element.querySelector(".chat-prompt__menu-note")?.textContent.trim() || null
      } : null,
      dictation: dictation ? { url: element.dataset.dictationUrlValue } : null,
      csrfToken: document.querySelector("meta[name=csrf-token]")?.content || null,
      attachments: [ ...element.querySelectorAll("figure.attachment") ].map(figure => {
        const progress = figure.querySelector("progress")
        return {
          id: figure.dataset.lexicalNodeKey,
          name: this.#fileName(figure),
          size: figure.querySelector(".attachment__meta")?.textContent.split(" · ")[0] || null,
          contentType: figure.dataset.contentType || null,
          uploading: Boolean(progress),
          progress: progress ? Number(progress.value || 0) : 100
        }
      }),
      acceptsFiles: !element.classList.contains("composer--locked")
    }
  }
}
