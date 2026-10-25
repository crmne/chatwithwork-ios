import UIKit
import UniformTypeIdentifiers

/// "Chat with Work" in the share sheet: text and links go to a new chat's
/// composer (`/chats/new?title=&text=&url=`, which the server fills and
/// never sends by itself), and files are put in the app group's container,
/// where the app picks them up and hands them to the composer (`attach`).
/// Then it opens the app on that new chat.
final class ShareViewController: UIViewController {
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !handled else { return }
        handled = true
        Task { await share() }
    }

    private func share() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let title = items.first?.attributedContentText?.string

        var text: String?
        var link: String?
        var files: [SharedFile] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), let url = await loadURL(provider), !url.isFileURL {
                link = url.absoluteString
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                text = await loadText(provider) ?? text
            } else if let file = await loadFile(provider) {
                files.append(file)
            }
        }

        let folder = SharedInbox.store(files)
        open(AppLink.newChat(title: title?.isEmpty == false && title != text ? title : nil, text: text, url: link, shared: folder))
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: Loading

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
    }

    private func loadFile(_ provider: NSItemProvider) async -> SharedFile? {
        let type = [UTType.pdf, .image, .data].first { provider.hasItemConformingToTypeIdentifier($0.identifier) } ?? .data
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url, let data = try? Data(contentsOf: url), data.count <= SharedInbox.largest else {
                    continuation.resume(returning: nil)
                    return
                }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? type.preferredMIMEType ?? "application/octet-stream"
                continuation.resume(returning: SharedFile(name: url.lastPathComponent, type: mime, data: data))
            }
        }
    }

    // MARK: Opening the app

    /// Share extensions can't open URLs through their context, so the
    /// request goes up the responder chain to the application, whose open
    /// method extensions may not name directly.
    private func open(_ url: URL) {
        typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, let method = class_getInstanceMethod(type(of: current), selector) {
                unsafeBitCast(method_getImplementation(method), to: Open.self)(current, selector, url as NSURL, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
    }
}
