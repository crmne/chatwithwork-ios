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

application.register("composer", class extends Controller {
  static targets = ["input", "send"]

  update() {
    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${Math.min(this.inputTarget.scrollHeight, 160)}px`
    if (this.hasSendTarget) this.sendTarget.disabled = this.inputTarget.value.trim() === ""
  }

  submit(event) {
    if (this.inputTarget.value.trim() === "") {
      event.preventDefault()
    } else if (event.type === "keydown") {
      event.preventDefault()
      this.element.querySelector("form").requestSubmit()
    }
  }

  suggest(event) {
    this.inputTarget.value = event.currentTarget.dataset.text
    this.update()
    this.inputTarget.focus()
  }
})

// Conversations open at their latest message, as the app's scroll
// controller does.
document.addEventListener("turbo:load", () => {
  if (document.body.classList.contains("chat-view")) {
    window.scrollTo(0, document.documentElement.scrollHeight)
  }
})
