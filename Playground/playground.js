// The playground's JavaScript: Turbo, Stimulus, the reference bridge
// controllers from web/controllers/bridge, and small stand-ins for the Rails
// app's own controllers (search, the composer).
import "@hotwired/turbo"
import { Application, Controller } from "@hotwired/stimulus"
import AuthSessionController from "/web/controllers/bridge/auth_session_controller.js"
import ButtonController from "/web/controllers/bridge/button_controller.js"
import ConfirmController from "/web/controllers/bridge/confirm_controller.js"
import ContextMenuController from "/web/controllers/bridge/context_menu_controller.js"
import FileController from "/web/controllers/bridge/file_controller.js"
import FormController from "/web/controllers/bridge/form_controller.js"
import HapticController from "/web/controllers/bridge/haptic_controller.js"
import MenuController from "/web/controllers/bridge/menu_controller.js"
import NotificationTokenController from "/web/controllers/bridge/notification_token_controller.js"
import SearchController from "/web/controllers/bridge/search_controller.js"
import ShareController from "/web/controllers/bridge/share_controller.js"
import SidebarController from "/web/controllers/bridge/sidebar_controller.js"
import BridgeComposerController from "/web/controllers/bridge/composer_controller.js"
import BridgeWebComposerController from "/web/controllers/bridge/web_composer_controller.js"
import ToastController from "/web/controllers/bridge/toast_controller.js"

const application = Application.start()

// The page's own refresh, which pulling down calls (docs/server-contract.md,
// "Pull to refresh"): the server morphs a fresh copy in; here a Turbo visit
// to the same page stands in, settling once it has drawn. Opened first with
// `?cold_refresh`, the playground leaves it out, as an older server does, so the app's
// fallback to Hotwire Native's own refresh can be tried too.
if (!new URLSearchParams(location.search).has("cold_refresh")) {
  window.chatWithWork = Object.assign(window.chatWithWork || {}, {
    refresh() {
      return new Promise((resolve) => {
        document.addEventListener("turbo:load", () => resolve(), { once: true })
        window.Turbo.visit(location.href, { action: "replace" })
      })
    }
  })
}

application.register("bridge--auth-session", AuthSessionController)
application.register("bridge--button", ButtonController)
application.register("bridge--confirm", ConfirmController)
application.register("bridge--context-menu", ContextMenuController)
application.register("bridge--file", FileController)
application.register("bridge--form", FormController)
application.register("bridge--haptic", HapticController)
application.register("bridge--menu", MenuController)
application.register("bridge--notification-token", NotificationTokenController)
application.register("bridge--search", SearchController)
application.register("bridge--share", ShareController)
application.register("bridge--sidebar", SidebarController)
application.register("bridge--composer", BridgeComposerController)
application.register("bridge--web-composer", BridgeWebComposerController)
application.register("bridge--toast", ToastController)

application.register("search", class extends Controller {
  static targets = ["input", "item"]

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    this.itemTargets.forEach(item => {
      item.classList.toggle("hidden", query !== "" && !item.textContent.toLowerCase().includes(query))
    })
  }
})

// Stands in for the chat form's controllers (chat, attachments) and its
// Lexxy editor: a textarea whose text goes into the form's hidden content
// field, as the editor's does.
application.register("composer", class extends Controller {
  static targets = ["input", "content", "send"]

  update() {
    this.element.dataset.permissionMode = this.element.querySelector("input[name=permission_mode]:checked")?.value || ""
    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${Math.min(this.inputTarget.scrollHeight, 192)}px`
    if (this.hasSendTarget) this.sendTarget.disabled = this.inputTarget.value.trim() === ""
  }

  submit(event) {
    if (this.inputTarget.value.trim() === "") {
      event.preventDefault()
    } else if (event.type === "keydown") {
      event.preventDefault()
      this.element.querySelector("form").requestSubmit()
    } else {
      this.contentTarget.value = this.inputTarget.value
    }
  }

  reset(event) {
    if (!event.detail.success) return
    this.inputTarget.value = ""
    this.update()
  }
})

// Stands in for the parts of the web app's chat controller that the
// composer bridge uses: the field, whether files are uploading, and sending.
application.register("chat", class extends Controller {
  static targets = ["input"]

  get attachmentsUploading() { return false }

  get promptText() { return this.inputTarget.value }

  htmlFromPlainText(text) { return text }

  updateButtonState() {
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  canSubmit() { return this.inputTarget.value.trim() !== "" }

  submitFormActions() {
    this.element.querySelector("form").requestSubmit()
  }
})

// Stands in for new_chat_sending_controller.js: New chat turns into its chat
// the moment the question goes (docs/server-contract.md, "New chat and New
// bot"). The page goes out of sight, the question and Thinking stand where the
// chat's page puts them, the composer moves into the chat's dock saying it
// works (so the app's shows Stop), and the title says "New chat"; a question
// that doesn't go puts the page back as it was, the words in the composer.
application.register("new-chat-sending", class extends Controller {
  static targets = ["page", "shell"]

  send(event) {
    const form = event.target
    const composer = form.closest(".composer")
    if (this.sending || !composer || !this.hasShellTarget) return
    const text = composer.querySelector("[data-composer-target=input]")?.value || ""
    const shell = this.shellTarget.content.firstElementChild.cloneNode(true)
    shell.querySelector(".message__bubble").textContent = text
    this.sending = { composer, shell, parent: composer.parentNode, place: composer.nextSibling, text, title: document.title }
    this.pageTarget.hidden = true
    this.pageTarget.after(shell)
    shell.querySelector("[data-new-chat-sending-target=dock]").append(composer)
    composer.classList.add("composer--working")
    document.title = "New chat"
    form.addEventListener("turbo:submit-end", (end) => { if (!end.detail?.success) this.putBack() }, { once: true })
  }

  putBack() {
    const sending = this.sending
    if (!sending) return
    this.sending = null
    sending.parent.insertBefore(sending.composer, sending.place?.parentNode === sending.parent ? sending.place : null)
    sending.composer.classList.remove("composer--working")
    const input = sending.composer.querySelector("[data-composer-target=input]")
    if (input) {
      input.value = sending.text
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
    sending.shell.remove()
    document.title = sending.title
    this.pageTarget.hidden = false
  }
})

// Stands in for prompt_suggestions_controller.js: a suggestion's words go
// into the composer, and to the app's own composer as well
// ("composer:filled", which the composer bridge connects again with).
application.register("prompt-suggestions", class extends Controller {
  static outlets = ["chat"]

  fill({ params: { prompt } }) {
    if (!this.hasChatOutlet) return
    this.chatOutlet.inputTarget.value = prompt
    this.chatOutlet.updateButtonState()
    this.chatOutlet.inputTarget.focus()
    this.chatOutlet.element.dispatchEvent(new CustomEvent("composer:filled", { detail: { text: prompt } }))
  }
})

// The composer's + menu, like the web app's composer-menu: its button opens
// and closes it, Escape closes it and returns to the button, and a click
// elsewhere closes it and leaves focus where it went.
application.register("composer-menu", class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    this.outside = event => { if (!this.element.contains(event.target)) this.#show(false) }
    document.addEventListener("click", this.outside)
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
  }

  toggle() {
    this.#show(this.menuTarget.hidden)
  }

  close() {
    if (!this.menuTarget.hidden) {
      this.#show(false)
      this.buttonTarget.focus()
    }
  }

  #show(open) {
    this.menuTarget.hidden = !open
    this.buttonTarget.setAttribute("aria-expanded", open)
  }
})

// Deny on an approval card, like the web app's approval-deny: its first
// press opens "Reason (optional)", the next denies with it; Escape or Cancel
// closes it again.
application.register("approval-deny", class extends Controller {
  static targets = ["reason", "field", "cancel", "deny"]

  deny(event) {
    if (this.open) return
    event.preventDefault()
    event.stopImmediatePropagation()
    this.#toggle(true)
    this.fieldTarget.focus()
  }

  close(event) {
    if (!this.open) return
    event?.preventDefault()
    this.fieldTarget.value = ""
    this.#toggle(false)
    this.denyTarget.focus()
  }

  get open() {
    return this.element.classList.contains("approval--denying")
  }

  #toggle(open) {
    this.element.classList.toggle("approval--denying", open)
    this.reasonTarget.hidden = !open
    this.cancelTarget.hidden = !open
    this.denyTarget.classList.toggle("btn-subtle", !open)
    this.denyTarget.classList.toggle("btn-subtle-negative", open)
  }
})

// Opens a <dialog> by id, like the web app's modal-opener.
application.register("modal-opener", class extends Controller {
  static values = { dialogId: String }

  open() {
    document.getElementById(this.dialogIdValue)?.showModal()
  }
})

// The model picker's choice, like the web app's model-select.
application.register("model-select", class extends Controller {
  static targets = ["model", "provider", "icon", "label", "option"]

  select(event) {
    const { modelId, provider, name, rate, icon, invert } = event.params
    this.modelTarget.value = modelId
    this.providerTarget.value = provider
    this.labelTarget.textContent = name
    this.iconTarget.src = icon
    this.iconTarget.classList.toggle("dark:brightness-0", invert)
    this.iconTarget.classList.toggle("dark:invert", invert)
    this.element.dataset.tip = rate
    this.optionTargets.forEach(option => {
      const chosen = option === event.currentTarget
      option.classList.toggle("active", chosen)
      option.setAttribute("aria-selected", chosen)
    })
    document.activeElement?.blur()
  }
})

// Conversations open at their latest message, as the app's scroll
// controller does.
document.addEventListener("turbo:load", () => {
  if (document.body.classList.contains("chat-view")) {
    window.scrollTo(0, document.documentElement.scrollHeight)
  }
})
