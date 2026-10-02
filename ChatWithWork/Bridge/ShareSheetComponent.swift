import HotwireNative
import LinkPresentation
import UIKit

/// `share`: the system share sheet for a link.
///
/// Web → native: `connect` with `{url?, title?, text?, color?}` adds a share
/// button to the navigation bar; `share` with the same data opens the sheet
/// at once. Native → web: a reply to `share` with `{completed, activityType}`
/// once the sheet closes. Joe Masilotti's contract (url defaults to the page),
/// plus the title and text, which give the sheet a proper preview.
final class ShareSheetComponent: BridgeComponent {
    override nonisolated class var name: String { "share" }

    override func onReceive(message: Message) {
        switch message.event {
        case "connect": showButton(message)
        case "share": share(message)
        case "disconnect": hideButton()
        default: break
        }
    }

    private func showButton(_ message: Message) {
        guard let data: ShareData = message.data(), let viewController = destinationViewController else { return }

        let item = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), primaryAction: nil)
        item.primaryAction = UIAction(title: String(localized: "Share")) { [weak self, weak item] _ in
            self?.present(data, from: item, message: nil)
        }
        item.accessibilityLabel = String(localized: "Share")
        item.tintColor = UIColor(hex: data.color)
        item.accessibilityIdentifier = "bridge.share"
        NavigationBarItems.set(item, slot: .share, side: .trailing, on: viewController)
    }

    private func hideButton() {
        guard let viewController = destinationViewController else { return }
        NavigationBarItems.set(nil, slot: .share, side: .trailing, on: viewController)
    }

    private func share(_ message: Message) {
        guard let data: ShareData = message.data() else { return }
        present(data, from: nil, message: message)
    }

    private func present(_ data: ShareData, from barButtonItem: UIBarButtonItem?, message: Message?) {
        guard let viewController = destinationViewController else { return }

        let page = (viewController as? VisitableViewController)?.currentVisitableURL
        let url = data.url.flatMap { URL(string: $0, relativeTo: page)?.absoluteURL } ?? page
        guard let url else { return }

        var items: [Any] = [LinkItem(url: url, title: data.title)]
        if let text = data.text, !text.isEmpty { items.append(text) }

        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if message != nil {
            sheet.completionWithItemsHandler = { @Sendable [weak self] activityType, completed, _, _ in
                let result = ShareResult(completed: completed, activityType: activityType?.rawValue)
                Task { @MainActor in
                    _ = try? await self?.reply(to: "share", with: result)
                }
            }
        }
        if let popover = sheet.popoverPresentationController {
            if let barButtonItem {
                popover.sourceItem = barButtonItem
            } else {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        viewController.present(sheet, animated: true)
    }
}

nonisolated struct ShareData: Decodable, Equatable {
    let url: String?
    let title: String?
    let text: String?
    let color: String?
}

nonisolated struct ShareResult: Encodable, Equatable {
    let completed: Bool
    let activityType: String?
}

/// A link with its title, so the share sheet's header reads "Q3 planning"
/// instead of a bare URL. The share sheet asks for items on background
/// threads, so nothing here belongs to the main actor.
private nonisolated final class LinkItem: NSObject, UIActivityItemSource, Sendable {
    let url: URL
    let title: String?

    init(url: URL, title: String?) {
        self.url = url
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        return metadata
    }
}
