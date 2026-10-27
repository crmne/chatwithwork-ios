import HotwireNative
import UIKit

/// `file`: Share in the bar of a file's viewer (the server's
/// `chats/files/show`), for the file itself rather than a link to it.
///
/// Web → native: `connect` with `{files: [{url, name, contentType?, title?}]}`,
/// the file first, then the PDF of its pages once the server has made one;
/// `disconnect`. One file shares at once; with more, the button's Share menu
/// asks which, by each `title`, which says what the file is ("PowerPoint",
/// "PDF"). Sharing downloads the file with the web views'
/// session (SessionDownload), only from this build's own server, and opens
/// the share sheet with it, which can save it to Files, print it, send it,
/// or open it in another app. Nothing goes back to the page.
final class FileShareComponent: BridgeComponent {
    override nonisolated class var name: String { "file" }

    private var files: [ViewerFile] = []
    private var downloading = false

    override func onReceive(message: Message) {
        switch message.event {
        case "connect":
            files = (message.data() as FileShareData?)?.files ?? []
            showButton()
        case "disconnect":
            files = []
            showButton()
            // Its pages go; whatever the web view shows next starts whole.
            PinchZoom.reset(delegate?.webView)
        default:
            break
        }
    }

    private func showButton() {
        guard let viewController = destinationViewController else { return }
        guard !files.isEmpty else {
            NavigationBarItems.set(nil, slot: .file, side: .trailing, on: viewController)
            return
        }

        let item = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), menu: nil)
        if files.count == 1 {
            item.primaryAction = UIAction(title: String(localized: "Share")) { [weak self, weak item] _ in
                guard let self, let item, let file = files.first else { return }
                share(file, from: item)
            }
        } else {
            item.menu = UIMenu(title: String(localized: "Share"), children: files.map { file in
                UIAction(title: file.title ?? file.name, image: UIImage(systemName: file.isPDF ? "doc.richtext" : "doc")) { [weak self, weak item] _ in
                    guard let self, let item else { return }
                    share(file, from: item)
                }
            })
        }
        item.accessibilityLabel = String(localized: "Share")
        item.accessibilityIdentifier = "bridge.file"
        item.isEnabled = !downloading
        NavigationBarItems.set(item, slot: .file, side: .trailing, on: viewController)
    }

    private func share(_ file: ViewerFile, from item: UIBarButtonItem) {
        guard !downloading, let viewController = destinationViewController,
              let url = file.resolvedURL(relativeTo: (viewController as? VisitableViewController)?.currentVisitableURL),
              AppEnvironment.current.owns(url) else { return }

        downloading = true
        item.isEnabled = false
        Task { [weak self, weak viewController, weak item] in
            defer {
                self?.downloading = false
                item?.isEnabled = true
            }
            do {
                let local = try await SessionDownload.file(from: url, named: file.name)
                guard let viewController, viewController.viewIfLoaded?.window != nil else {
                    SessionDownload.discard(local)
                    return
                }
                Self.presentShareSheet(for: local, from: item, on: viewController)
            } catch {
                ToastCenter.shared.show(String(localized: "Couldn't download the file. Try again."), style: .error)
            }
        }
    }

    private static func presentShareSheet(for file: URL, from item: UIBarButtonItem?, on viewController: UIViewController) {
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.completionWithItemsHandler = { @Sendable _, _, _, _ in
            Task { @MainActor in SessionDownload.discard(file) }
        }
        if let popover = sheet.popoverPresentationController {
            if let item {
                popover.sourceItem = item
            } else {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        viewController.present(sheet, animated: true)
    }
}

nonisolated struct FileShareData: Decodable, Equatable {
    let files: [ViewerFile]
}

nonisolated struct ViewerFile: Decodable, Equatable {
    let url: String
    let name: String
    let contentType: String?
    let title: String?

    var isPDF: Bool { contentType == "application/pdf" }

    /// The file's address on the page's server; nil for anything that isn't
    /// http(s), which the app never downloads.
    func resolvedURL(relativeTo page: URL?) -> URL? {
        guard let resolved = URL(string: url, relativeTo: page)?.absoluteURL,
              let scheme = resolved.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return resolved
    }
}
