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

/// Downloads a file with the web views' session, then shows it in Quick Look.
/// Anything that fails to download opens in the in-app browser instead.
final class DocumentPreviewer: NSObject {
    static let shared = DocumentPreviewer()

    private var file: URL?

    func preview(_ url: URL, from presenter: UIViewController) {
        Task {
            do {
                file = try await download(url)
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

    private func download(_ url: URL) async throws -> URL {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        HTTPCookieStorage.shared.setCookies(cookies, for: url, mainDocumentURL: url)

        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: "Previews", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: response.suggestedFilename ?? url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
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
