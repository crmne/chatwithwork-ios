import UIKit
import WebKit

/// The keyboard up the moment the person opens New chat, where the page's
/// own composer shows. WebKit brings the keyboard up only for a focus that
/// follows a touch in the page, and New chat opened by the bar's button, the
/// sidebar, a link or a shortcut loads its page afterwards. So a field of
/// the app's own, out of sight, takes the keyboard at once (`raise`), and
/// hands it to the page's web view as soon as New chat's composer is drawn
/// and focused (`handOver`): WebKit keeps the keyboard up for the page's
/// focused field when its web view becomes first responder. A page that
/// never comes lets the keyboard go after `limit`.
@MainActor
enum KeyboardHandOff {
    static let limit: Duration = .seconds(10)
    /// How long it holds on to words already typed into it, for a slow page.
    static let limitWithWords: Duration = .seconds(60)

    private static var holder: Holder?
    /// Words typed into the field that no page took in time: the next New
    /// chat's composer gets them, before anything typed then.
    private(set) static var leftover = ""

    /// Takes the keyboard for New chat's composer, still on its way in
    /// `webView`, and hands it over as soon as that page has drawn its
    /// composer: the app focuses its editable (`focusScript`) and makes the
    /// web view first responder. Watches every few frames, from the tap,
    /// rather than waiting for the composer's bridge `connect`, which comes
    /// seconds after the page shows.
    ///
    /// `leaving` is the mark `markLeaving` put on the page shown when this
    /// New chat was asked for: that page is never handed the keyboard, even
    /// when it's a New chat too, so only the document of this visit gets it.
    static func raise(in window: UIWindow?, for webView: WKWebView?, leaving: String? = nil) {
        guard let window, let webView else { return }
        let field = holder ?? Holder(frame: CGRect(x: -10, y: -10, width: 1, height: 1))
        if field.superview !== window { window.addSubview(field) }
        holder = field
        guard field.becomeFirstResponder() else { return release() }
        let raised = field.raised
        Task { [weak webView] in
            let clock = ContinuousClock()
            let deadline = clock.now + limit
            let deadlineWithWords = clock.now + limitWithWords
            while clock.now < deadline || (field.hasText && clock.now < deadlineWithWords),
                  holder === field, field.raised == raised, field.isFirstResponder {
                if let webView, webView.window != nil, !webView.isHidden,
                   (try? await webView.evaluateJavaScript(focusScript(leaving: leaving))) as? Bool == true,
                   // A newer New chat may have taken the field while the page answered.
                   holder === field, field.raised == raised, field.isFirstResponder {
                    handOver(to: webView)
                    return
                }
                try? await Task.sleep(for: .milliseconds(32))
            }
            if holder === field, field.raised == raised { release() }
        }
    }

    /// Hands the keyboard the app's field holds to `webView`, whose page has
    /// focused its composer, with anything typed meanwhile. False when
    /// nothing was held, or the person moved on (the field lost it).
    @discardableResult
    static func handOver(to webView: WKWebView) -> Bool {
        guard let field = holder, field.isFirstResponder else {
            release()
            return false
        }
        let typed = leftover + (field.text ?? "")
        let taken = webView.becomeFirstResponder()
        let input = webView.scrollView.subviews.first(where: \.isFirstResponder) as? UIKeyInput
        holder = nil
        field.text = nil
        field.removeFromSuperview()
        // Words that can't go in now wait for the next New chat's composer (`leftover`).
        guard taken, let input else {
            leftover = typed
            if field.isFirstResponder { field.resignFirstResponder() }
            return false
        }
        leftover = ""
        if !typed.isEmpty { input.insertText(typed) }
        return true
    }

    /// Marks the page `webView` shows now, which a New chat being asked for
    /// is about to replace, so `raise` never hands the keyboard to it. The
    /// mark is sent before the visit's own script, so it lands on that page;
    /// the page the visit draws comes with a body of its own, unmarked.
    static func markLeaving(_ webView: WKWebView) -> String {
        let token = UUID().uuidString
        webView.evaluateJavaScript("void (document.body && (document.body.dataset.\(leavingKey) = \"\(token)\"))", completionHandler: nil)
        return token
    }

    private static let leavingKey = "nativeHandOffLeaving"

    /// Focuses New chat's composer, unless something outside it has the
    /// focus; true once its field has it (not one of its buttons). Never on the page marked
    /// `leaving`, nor on Turbo's preview of a page from its cache.
    static func focusScript(leaving: String? = nil) -> String {
        let mark = leaving.map { "\"\($0)\"" } ?? "null"
        return """
        (() => {
          if (!/\\/chats\\/new$/.test(location.pathname)) return false
          if (document.documentElement.hasAttribute("data-turbo-preview")) return false
          const leaving = \(mark)
          if (leaving && document.body?.dataset.\(leavingKey) === leaving) return false
          const composer = document.getElementById("new_message")
          const editable = composer?.querySelector(".lexxy-editor__content, [contenteditable=true], textarea")
          if (!editable) return false
          const active = document.activeElement
          if (active && active !== document.body && !composer.contains(active)) return false
          if (!editable.contains(active)) editable.focus({ preventScroll: true })
          return editable.contains(document.activeElement)
        })()
        """
    }

    /// Forgets everything held for New chat, the keyboard and the words no
    /// page took (`leftover`): on signing out and on moving to another
    /// organization, so nobody's words reach someone else's composer.
    static func discard() {
        leftover = ""
        guard let field = holder else { return }
        holder = nil
        field.text = nil
        if field.isFirstResponder { field.resignFirstResponder() }
        field.removeFromSuperview()
    }

    static func release() {
        guard let field = holder else { return }
        holder = nil
        leftover += field.text ?? ""
        field.text = nil
        if field.isFirstResponder { field.resignFirstResponder() }
        field.removeFromSuperview()
    }

    /// Plain, as the web composer is, so the keyboard doesn't change when
    /// the page takes it; never seen or read out.
    private final class Holder: UITextField {
        private(set) var raised = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            alpha = 0.01
            autocorrectionType = .default
            isAccessibilityElement = false
            accessibilityElementsHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func becomeFirstResponder() -> Bool {
            raised += 1
            return super.becomeFirstResponder()
        }
    }
}
