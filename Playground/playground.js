// The playground's JavaScript: Turbo, Stimulus, the reference bridge
// controllers from web/controllers/bridge, and small stand-ins for the Rails
// app's own controllers (search, the composer).
import "@hotwired/turbo"
import { Application, Controller } from "@hotwired/stimulus"
import AuthSessionController from "/web/controllers/bridge/auth_session_controller.js"
import ButtonController from "/web/controllers/bridge/button_controller.js"
import ConfirmController from "/web/controllers/bridge/confirm_controller.js"
import ContextMenuController from "/web/controllers/bridge/context_menu_controller.js"
import FormController from "/web/controllers/bridge/form_controller.js"
import HapticController from "/web/controllers/bridge/haptic_controller.js"
import MenuController from "/web/controllers/bridge/menu_controller.js"
import NotificationTokenController from "/web/controllers/bridge/notification_token_controller.js"
import SearchController from "/web/controllers/bridge/search_controller.js"
import ShareController from "/web/controllers/bridge/share_controller.js"
import ToastController from "/web/controllers/bridge/toast_controller.js"

const application = Application.start()

application.register("bridge--auth-session", AuthSessionController)
application.register("bridge--button", ButtonController)
application.register("bridge--confirm", ConfirmController)
application.register("bridge--context-menu", ContextMenuController)
application.register("bridge--form", FormController)
application.register("bridge--haptic", HapticController)
application.register("bridge--menu", MenuController)
application.register("bridge--notification-token", NotificationTokenController)
application.register("bridge--search", SearchController)
application.register("bridge--share", ShareController)
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
