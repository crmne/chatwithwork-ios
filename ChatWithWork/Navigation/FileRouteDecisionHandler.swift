import HotwireNative
import QuickLook
import SafariServices
import UIKit
import WebKit

/// Uploaded files and previews (Active Storage) open in Quick Look, which
/// shows PDFs, images, Office documents and audio natively, with Share, Save
/// to Files and Print. A web view visit would fail: they aren't Turbo pages.
nonisolated struct FileRouteDecisionHandler: RouteDecisionHandler {
    let name = "files"

    func matches(proposal: VisitProposal, configuration: Navigator.Configuration) -> Bool {
        AppRoute(url: proposal.url).kind == .file
    }

    func handle(proposal: VisitProposal, configuration: Navigator.Configuration, navigator: Navigating) -> Router.Decision {
        let url = proposal.url
        // Routing always happens on the main thread.
        nonisolated(unsafe) let navigator = navigator
        MainActor.assumeIsolated {
            DocumentPreviewer.shared.preview(url, from: navigator.activeNavigationController)
        }
        return .cancel
    }
}

/// Downloads a file with the web views' session (SessionDownload), then shows
/// it in Quick Look. Anything that fails to download opens in the in-app
/// browser instead. A chat's files open in their viewer, a page of the
/// server's (the path configuration's `/chats/<n>/files/` rule); this is for
/// the links that still lead to a file itself, like older pages' downloads.
final class DocumentPreviewer: NSObject {
    static let shared = DocumentPreviewer()

    private var file: URL?

    func preview(_ url: URL, from presenter: UIViewController) {
        Task {
            do {
                if let file { SessionDownload.discard(file) }
                file = try await SessionDownload.file(from: url)
                let preview = QLPreviewController()
                preview.dataSource = self
                presenter.present(preview, animated: true)
            } catch {
                let safari = SFSafariViewController(url: url)
                safari.preferredControlTintColor = Palette.ink
                presenter.present(safari, animated: true)
            }
        }
    }
}

extension DocumentPreviewer: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        file == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        (file ?? URL(fileURLWithPath: "/")) as NSURL
    }
}
