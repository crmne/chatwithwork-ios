import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Share in the bar of a file's viewer (chats/files/show): the app downloads the file with the page's session and hands
// the file itself to the share sheet, which can save it, send it, or open it in another app. With more than one file
// (an Office file, then the PDF of its pages), the app asks which first, by each title, which says what the file is.
// One per page.
//
//   <div hidden data-controller="bridge--file"
//        data-bridge--file-files-value='[{"url": "https://…", "name": "deck.pptx",
//          "contentType": "application/vnd…presentation", "title": "PowerPoint"}]'></div>
export default class extends BridgeComponent {
  static component = "file"
  static values = { files: Array }

  connect() {
    super.connect()
    this.send("connect", { files: this.filesValue })
  }

  disconnect() {
    super.disconnect()
    this.send("disconnect")
  }
}
