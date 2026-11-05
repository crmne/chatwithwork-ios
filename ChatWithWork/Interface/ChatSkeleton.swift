import HotwireNative
import ObjectiveC
import UIKit
import WebKit

/// The shape of a chat, drawn natively the moment a chat screen appears
/// (a notification's chat, a link, a sidebar row), until the page paints:
/// question bubbles and answer lines as bones with one shimmer sweeping
/// across them, a title bone in the bar, and the composer at rest. Without
/// it the screen was empty under the bar for as long as the page took.
///
/// Attached from outside the screen (`WebScreen.make`), never by a
/// subclass. It goes, crossfading, once the page has painted (`PagePaint`)
/// and settled, when the visit fails, or after `timeout` at the latest.
/// The page carries on the same look for answers still rendering, so the
/// crossfade lands on the same shapes.
enum ChatSkeleton {
    private nonisolated(unsafe) static var key: UInt8 = 0

    /// Never up longer than this, whatever the page does.
    static var timeout: Duration = .seconds(10)
    static let fadeSeconds: TimeInterval = 0.2
    /// How long a painted page gets to settle in.
    static let settleLimit: Duration = .seconds(1)

    /// Whether a screen for `url` gets the skeleton: a conversation that
    /// exists. A new chat has nothing to sketch.
    nonisolated static func covers(_ url: URL) -> Bool {
        if case .chat = AppRoute(url: url).kind { return true }
        return false
    }

    static func attach(to controller: VisitableViewController, url: URL) {
        guard covers(url), let container = controller.viewIfLoaded, current(on: controller) == nil else { return }
        let skeleton = ChatSkeletonView(path: url.path(percentEncoded: false))
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(skeleton)
        NSLayoutConstraint.activate([
            skeleton.topAnchor.constraint(equalTo: container.topAnchor),
            skeleton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            skeleton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        if controller.navigationItem.title?.isEmpty != false, controller.navigationItem.titleView == nil {
            let bone = TitleBone()
            controller.navigationItem.titleView = bone
            skeleton.titleBone = bone
        }
        objc_setAssociatedObject(controller, &key, skeleton, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        Task { [weak controller] in
            try? await Task.sleep(for: timeout)
            guard let controller else { return }
            dismiss(on: controller)
        }
    }

    static func current(on controller: UIViewController) -> ChatSkeletonView? {
        objc_getAssociatedObject(controller, &key) as? ChatSkeletonView
    }

    /// The page in `controller`'s web view painted `path`. It's the chat's
    /// page, or the page the web view now shows (a redirect), and not a
    /// page from before that finished late.
    static func pagePainted(path: String, webView: WKWebView?, on controller: UIViewController) {
        guard let skeleton = current(on: controller), !skeleton.isSettling else { return }
        let shown = webView?.url?.path(percentEncoded: false)
        guard samePage(path, skeleton.path) || samePage(path, shown) else { return }
        skeleton.isSettling = true
        settle(webView, on: controller)
    }

    /// A painted page isn't yet what the person should see: Hotwire keeps the
    /// web view hidden until its visit says it rendered, and the page moves
    /// to its place in the chat once its scripts run. Fading out earlier
    /// showed an empty screen with a spinner, then the chat's first lines,
    /// then a jump. So wait for both, never longer than `settleLimit`.
    private static func settle(_ webView: WKWebView?, on controller: UIViewController) {
        Task { [weak controller, weak webView] in
            let clock = ContinuousClock()
            let limit = clock.now + settleLimit
            while let webView, clock.now < limit, !isSettled(webView) {
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let controller else { return }
            dismiss(on: controller)
        }
    }

    private static func isSettled(_ webView: WKWebView) -> Bool {
        let scrollView = webView.scrollView
        return isSettled(webViewHidden: webView.isHidden, contentHeight: scrollView.contentSize.height,
                         visibleHeight: scrollView.bounds.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom,
                         offset: scrollView.contentOffset.y, restingOffset: -scrollView.adjustedContentInset.top)
    }

    /// Shown, and either the chat fits the screen or it has left the top.
    nonisolated static func isSettled(webViewHidden: Bool, contentHeight: CGFloat, visibleHeight: CGFloat, offset: CGFloat, restingOffset: CGFloat) -> Bool {
        !webViewHidden && (contentHeight <= visibleHeight + 1 || offset > restingOffset + 1)
    }

    nonisolated static func samePage(_ path: String?, _ other: String?) -> Bool {
        guard let path, let other else { return false }
        let one = AppRoute(path: path), two = AppRoute(path: other)
        return one.path == two.path && (one.account == nil || two.account == nil || one.account == two.account)
    }

    /// Crossfades the skeleton out, and the real title in.
    static func dismiss(on controller: UIViewController, animated: Bool = true) {
        guard let skeleton = current(on: controller) else { return }
        objc_setAssociatedObject(controller, &key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if let bone = skeleton.titleBone, controller.navigationItem.titleView === bone {
            controller.navigationItem.titleView = nil
        }
        skeleton.accessibilityElementsHidden = true
        guard animated, skeleton.window != nil else {
            skeleton.removeFromSuperview()
            return
        }
        UIView.animate(withDuration: fadeSeconds, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            skeleton.alpha = 0
        } completion: { _ in
            skeleton.removeFromSuperview()
        }
    }
}

/// Where the bones go, top-down under the bar, in a column `width` wide.
/// Shared with the Android app's skeleton, so both draw the same chat.
nonisolated struct ChatSkeletonLayout: Equatable {
    struct Bone: Equatable {
        enum Kind: Equatable { case question, line }
        let kind: Kind
        let frame: CGRect
    }

    static let margin: CGFloat = 16
    static let topGap: CGFloat = 16
    static let gap: CGFloat = 24
    static let lineHeight: CGFloat = 12
    /// The answers' text rhythm: 1rem at a line height of 1.6.
    static let lineRhythm: CGFloat = 25.6
    /// `--radius-card` and `--radius-tag`: a question's corners, but the bottom right.
    static let bubbleRadius: CGFloat = 14
    static let bubbleTailRadius: CGFloat = 6
    /// The column's widest, as the native composer's.
    static let maxColumn: CGFloat = 780

    let bones: [Bone]
    let composer: CGRect

    /// `bounds` is the screen's, `insets` its safe area (under the bar, above
    /// the home indicator).
    init(bounds: CGRect, insets: UIEdgeInsets) {
        let usable = bounds.width - insets.left - insets.right
        let column = min(usable, Self.maxColumn)
        let left = insets.left + (usable - column) / 2 + Self.margin
        let width = max(column - 2 * Self.margin, 0)
        var y = insets.top + Self.topGap
        var bones: [Bone] = []

        func question(_ fraction: CGFloat, height: CGFloat) {
            let w = (width * fraction).rounded()
            bones.append(Bone(kind: .question, frame: CGRect(x: left + width - w, y: y, width: w, height: height)))
            y += height + Self.gap
        }
        func answer(lines: Int) {
            for index in 0..<lines {
                let w = index == lines - 1 ? (width * 0.6).rounded() : width
                let top = y + CGFloat(index) * Self.lineRhythm + (Self.lineRhythm - Self.lineHeight) / 2
                bones.append(Bone(kind: .line, frame: CGRect(x: left, y: top.rounded(), width: w, height: Self.lineHeight)))
            }
            y += CGFloat(lines) * Self.lineRhythm + Self.gap
        }

        question(0.62, height: 44)
        answer(lines: 4)
        question(0.45, height: 36)
        answer(lines: 3)
        self.bones = bones

        let height = ComposerView.restingBoxHeight
        composer = CGRect(x: left, y: bounds.height - insets.bottom - ComposerView.restingBottomGap - height, width: width, height: height)
    }

    var path: CGPath {
        let path = CGMutablePath()
        for bone in bones {
            switch bone.kind {
            case .line:
                path.addPath(CGPath(roundedRect: bone.frame, cornerWidth: bone.frame.height / 2, cornerHeight: bone.frame.height / 2, transform: nil))
            case .question:
                path.addPath(Self.bubble(bone.frame))
            }
        }
        return path
    }

    /// A rounded rectangle whose bottom-right corner is tighter, as the web's `.message__bubble`.
    static func bubble(_ rect: CGRect) -> CGPath {
        let r = min(bubbleRadius, rect.height / 2), tail = bubbleTailRadius
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tail))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - tail, y: rect.maxY), radius: tail)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

/// The skeleton itself: bones in `surfaceSelected` on the canvas, one
/// gradient masked by all of them sweeping left to right, and the composer
/// at rest. Still under Reduce Motion, following the setting as it changes.
final class ChatSkeletonView: UIView {
    static let sweepSeconds: CFTimeInterval = 1.4
    private static let sweepKey = "sweep"

    let path: String
    weak var titleBone: TitleBone?
    var isSettling = false
    /// Whether Reduce Motion is on; replaced in tests.
    var reducesMotion: () -> Bool = { UIAccessibility.isReduceMotionEnabled } {
        didSet { updateSweep() }
    }

    private let bones = CAShapeLayer()
    private let shine = CALayer()
    private let shineMask = CAShapeLayer()
    private let band = CAGradientLayer()
    private let composer = UIView()
    private var laidOut: CGRect = .null

    var isSweeping: Bool { band.animation(forKey: Self.sweepKey) != nil }
    private(set) var layout: ChatSkeletonLayout?

    init(path: String) {
        self.path = path
        super.init(frame: .zero)
        backgroundColor = Palette.canvas
        isUserInteractionEnabled = false
        accessibilityIdentifier = "chat.skeleton"
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Loading chat", comment: "VoiceOver: a chat's shape shows while its page loads")
        // The page loading underneath stays out of VoiceOver's way until this goes.
        accessibilityViewIsModal = true

        layer.addSublayer(bones)
        shine.mask = shineMask
        shine.addSublayer(band)
        layer.addSublayer(shine)
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.locations = [0.4, 0.5, 0.6]

        composer.layer.cornerRadius = RainbowBox.cornerRadius
        composer.layer.cornerCurve = .continuous
        composer.layer.borderWidth = 1
        addSubview(composer)

        styleColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ChatSkeletonView, _: UITraitCollection) in
            view.styleColors()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(motionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let key = CGRect(origin: CGPoint(x: safeAreaInsets.top, y: safeAreaInsets.bottom), size: bounds.size)
        guard key != laidOut else { return }
        laidOut = key
        let layout = ChatSkeletonLayout(bounds: bounds, insets: safeAreaInsets)
        self.layout = layout
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bones.frame = bounds
        bones.path = layout.path
        shine.frame = bounds
        shineMask.frame = bounds
        shineMask.path = layout.path
        // A diagonal band, about 20 degrees off upright whatever the screen's
        // shape. A gradient's points are in the layer's unit square, so its
        // bands lean by the screen's proportions too.
        band.frame = bounds
        let lean = bounds.width > 0 ? 0.36 * bounds.height / bounds.width : 0
        band.startPoint = CGPoint(x: 0, y: 0.5 - lean / 2)
        band.endPoint = CGPoint(x: 1, y: 0.5 + lean / 2)
        CATransaction.commit()
        composer.frame = layout.composer
        updateSweep(restart: true)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSweep(restart: true)
    }

    private func styleColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bones.fillColor = Palette.surfaceSelected.resolvedColor(with: traitCollection).cgColor
        let highlight = Palette.skeletonShine.resolvedColor(with: traitCollection)
        band.colors = [highlight.withAlphaComponent(0).cgColor, highlight.cgColor, highlight.withAlphaComponent(0).cgColor]
        composer.backgroundColor = Palette.surface
        composer.layer.borderColor = Palette.line.resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
    }

    @objc private func motionChanged() {
        updateSweep()
    }

    private func updateSweep(restart: Bool = false) {
        let wanted = !reducesMotion() && window != nil && bounds.width > 0
        shine.isHidden = !wanted
        if !wanted {
            band.removeAnimation(forKey: Self.sweepKey)
            return
        }
        guard restart || !isSweeping else { return }
        let sweep = CABasicAnimation(keyPath: "transform.translation.x")
        // Far enough for a leaning band to clear the screen at both ends.
        sweep.fromValue = -1.25 * bounds.width
        sweep.toValue = 1.25 * bounds.width
        sweep.duration = Self.sweepSeconds
        sweep.timingFunction = CAMediaTimingFunction(name: .linear)
        sweep.repeatCount = .infinity
        sweep.isRemovedOnCompletion = false
        band.add(sweep, forKey: Self.sweepKey)
    }
}

/// Where the chat's title will go, until it does.
final class TitleBone: UIView {
    static let size = CGSize(width: 120, height: 12)

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        backgroundColor = Palette.surfaceSelected
        layer.cornerRadius = Self.size.height / 2
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { Self.size }
}
