import Foundation
import HotwireNative
import Testing
import UIKit
@testable import ChatWithWork

@Suite("Interface")
struct InterfaceTests {
    @Test("says plainly why a page didn't load")
    func errorCopy() throws {
        let offline = ErrorCopy(.web(WebError(urlError: URLError(.notConnectedToInternet))))
        #expect(offline.title == "You're offline")
        #expect(offline.symbol == "wifi.slash")

        let timeout = ErrorCopy(.web(WebError(urlError: URLError(.timedOut))))
        #expect(timeout.title == "This is taking too long")

        let unreachable = ErrorCopy(.web(WebError(urlError: URLError(.cannotFindHost))))
        #expect(unreachable.title == "Can't reach Chat with Work")

        let missing = ErrorCopy(.http(try #require(HTTPError(statusCode: 404))))
        #expect(missing.title == "This page isn't here")

        let forbidden = ErrorCopy(.http(try #require(HTTPError(statusCode: 403))))
        #expect(forbidden.title == "You don't have access")

        let broken = ErrorCopy(.http(try #require(HTTPError(statusCode: 502))))
        #expect(broken.title == "Something went wrong")
    }

    @Test("matches Live Wire's tokens in both appearances")
    func palette() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        #expect(hex(Palette.canvas.resolvedColor(with: light)) == "F3F5F9")
        #expect(hex(Palette.canvas.resolvedColor(with: dark)) == "06070B")
        #expect(hex(Palette.ink.resolvedColor(with: light)) == "0A0D14")
        #expect(hex(Palette.ink.resolvedColor(with: dark)) == "E9ECF4")
        #expect(hex(Palette.negative.resolvedColor(with: dark)) == "FF6644")
    }

    @Test("resolves its colors on any thread, as SwiftUI does when it lays out text")
    func colorsResolveOffTheMainThread() async {
        let ink = Palette.ink
        let resolved = await Task.detached {
            ink.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        }.value
        #expect(hex(resolved) == "E9ECF4")
    }

    @Test("scales pages with the system text size, up to 120%")
    func textSize() {
        #expect(TextSize.pageZoom(for: .large) == 1)
        #expect(TextSize.pageZoom(for: .extraSmall) == 0.85)
        #expect(TextSize.pageZoom(for: .extraExtraExtraLarge) == 1.15)
        #expect(TextSize.pageZoom(for: .accessibilityExtraExtraExtraLarge) == 1.2)
    }

    @Test("reads colors the bridge sends", arguments: [("#0A0D14", "0A0D14"), ("ff6644", "FF6644")])
    func hexColors(input: String, expected: String) throws {
        #expect(hex(try #require(UIColor(hex: input))) == expected)
    }

    @Test("ignores colors it can't read", arguments: [nil, "", "red", "#12345"] as [String?])
    func badColors(input: String?) {
        #expect(UIColor(hex: input) == nil)
    }

    private func hex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}
