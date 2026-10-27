import Foundation
import WebKit

/// Downloads a file of the server's with the web views' session, as the
/// signed-in person, into a folder of its own under the temporary directory,
/// keeping the name the server gives it (or `name`), so Quick Look and the
/// share sheet show the file by its name.
enum SessionDownload {
    static func file(from url: URL, named name: String? = nil) async throws -> URL {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        HTTPCookieStorage.shared.setCookies(cookies, for: url, mainDocumentURL: url)

        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Files", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: safeName(name ?? response.suggestedFilename ?? url.lastPathComponent))
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// Removes a downloaded file and the folder it came in.
    static func discard(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    /// A file name with no folders in it, never empty.
    static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "file" : cleaned
    }
}
