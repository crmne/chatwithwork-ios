@preconcurrency import HotwireNative
import ObjectiveC
import UIKit
import WebKit

/// The shape of a page, drawn natively the moment its screen appears (a
/// place the sidebar opens, a drill-down, a sheet, a notification's chat),
/// until the page paints: its bones with one shimmer sweeping across them,
/// a title bone in the bar, and, for a chat or a new chat, the composer at
/// rest. Without it the screen was empty under the bar for as long as the
/// page took.
///
/// The server says which shape a page has, in its path configuration's
/// `skeleton` property (`Kind`). Attached from outside the screen
/// (`WebScreen.make`), never by a subclass, so only a screen that's new
/// gets one: coming back to a screen shows it as it was. It goes,
/// crossfading, once the page has painted (`PagePaint`) and settled, when
/// the visit fails, or after `timeout` at the latest. A chat's page carries
/// on the same look for answers still rendering, so the crossfade lands on
/// the same shapes.
enum PageSkeleton {
    /// A page's shape, as the path configuration's `skeleton` names it.
    nonisolated enum Kind: String, CaseIterable, Sendable {
        case chat
        case newChat = "new_chat"
        case list
        case settings
        case form
        case page
    }

    nonisolated static let property = "skeleton"

    private nonisolated(unsafe) static var key: UInt8 = 0

    /// Never up longer than this, whatever the page does.
    static var timeout: Duration = .seconds(10)
    static let fadeSeconds: TimeInterval = 0.2
    /// How long a painted page gets to settle in.
    static let settleLimit: Duration = .seconds(1)

    /// The shape a screen for `url` shows, from its path properties: none
    /// where they say `none`, and a plain page for a name this build
    /// doesn't know. A server from before the property draws only a chat
    /// that exists.
    nonisolated static func kind(for url: URL, properties: PathProperties) -> Kind? {
        guard let value = properties[property] as? String else {
            if case .chat = AppRoute(url: url).kind { return .chat }
            return nil
        }
        if value == "none" { return nil }
        return Kind(rawValue: value) ?? .page
    }

    static func attach(to controller: VisitableViewController, url: URL, properties: PathProperties? = nil) {
        let properties = properties ?? Hotwire.config.pathConfiguration.properties(for: url)
        guard let kind = kind(for: url, properties: properties), let container = controller.viewIfLoaded, current(on: controller) == nil else { return }
        let skeleton = PageSkeletonView(kind: kind, path: page(of: url))
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

    static func current(on controller: UIViewController) -> PageSkeletonView? {
        objc_getAssociatedObject(controller, &key) as? PageSkeletonView
    }

    /// The page in `controller`'s web view painted `path` (with its query)
    /// at `at`. It's the screen's page, or the page the web view now shows
    /// (a redirect), and not a page from before that finished late: a
    /// bot's Overview painting as its Setup tab's screen comes up has the
    /// same path, so the query tells them apart, and a paint from before
    /// the skeleton came up never counts.
    static func pagePainted(path: String, at: Date? = nil, webView: WKWebView?, on controller: UIViewController) {
        guard let skeleton = current(on: controller), !skeleton.isSettling else { return }
        if let at, at < skeleton.shownAt.addingTimeInterval(-0.001) { return }
        let shown = webView?.url.map(page(of:))
        guard samePage(path, skeleton.path) || samePage(path, shown) else { return }
        skeleton.isSettling = true
        settle(webView, kind: skeleton.kind, on: controller)
    }

    /// A page as `PagePaint` names it: its path and its query.
    nonisolated static func page(of url: URL) -> String {
        let path = url.path(percentEncoded: false)
        guard let query = url.query(percentEncoded: true), !query.isEmpty else { return path }
        return path + "?" + query
    }

    /// A painted page isn't yet what the person should see: Hotwire keeps the
    /// web view hidden until its visit says it rendered, and a chat moves
    /// to its place once its scripts run. Fading out earlier showed an
    /// empty screen with a spinner, then the chat's first lines, then a
    /// jump. So wait for both, never longer than `settleLimit`.
    private static func settle(_ webView: WKWebView?, kind: Kind, on controller: UIViewController) {
        Task { [weak controller, weak webView] in
            let clock = ContinuousClock()
            let limit = clock.now + settleLimit
            while let webView, clock.now < limit, !isSettled(webView, kind: kind) {
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let controller else { return }
            dismiss(on: controller)
        }
    }

    private static func isSettled(_ webView: WKWebView, kind: Kind) -> Bool {
        guard kind == .chat else { return !webView.isHidden }
        let scrollView = webView.scrollView
        return isSettled(webViewHidden: webView.isHidden, contentHeight: scrollView.contentSize.height,
                         visibleHeight: scrollView.bounds.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom,
                         offset: scrollView.contentOffset.y, restingOffset: -scrollView.adjustedContentInset.top)
    }

    /// A chat: shown, and either it fits the screen or it has left the top.
    nonisolated static func isSettled(webViewHidden: Bool, contentHeight: CGFloat, visibleHeight: CGFloat, offset: CGFloat, restingOffset: CGFloat) -> Bool {
        !webViewHidden && (contentHeight <= visibleHeight + 1 || offset > restingOffset + 1)
    }

    /// The same page: the same path, in the same organization where both
    /// name one, and the same query.
    nonisolated static func samePage(_ path: String?, _ other: String?) -> Bool {
        guard let path, let other else { return false }
        let (onePath, oneQuery) = split(path), (twoPath, twoQuery) = split(other)
        let one = AppRoute(path: onePath), two = AppRoute(path: twoPath)
        return one.path == two.path && oneQuery == twoQuery
            && (one.account == nil || two.account == nil || one.account == two.account)
    }

    private nonisolated static func split(_ page: String) -> (path: String, query: String) {
        guard let mark = page.firstIndex(of: "?") else { return (page, "") }
        return (String(page[..<mark]), String(page[page.index(after: mark)...]))
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

/// Where a chat's bones go, top-down under the bar, in a column `width` wide.
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
        let column = SkeletonColumn(bounds: bounds, insets: insets)
        let left = column.left, width = column.width
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
        composer = column.composer
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

/// The column every skeleton draws in: 16 from the sides, centred, at most
/// the chat's width, and where the composer rests at its foot.
nonisolated struct SkeletonColumn: Equatable {
    let left: CGFloat
    let width: CGFloat
    let composer: CGRect

    init(bounds: CGRect, insets: UIEdgeInsets) {
        let usable = bounds.width - insets.left - insets.right
        let column = min(usable, ChatSkeletonLayout.maxColumn)
        left = insets.left + (usable - column) / 2 + ChatSkeletonLayout.margin
        width = max(column - 2 * ChatSkeletonLayout.margin, 0)
        let height = ComposerView.restingBoxHeight
        composer = CGRect(x: left, y: bounds.height - insets.bottom - ComposerView.restingBottomGap - height, width: width, height: height)
    }
}

/// Where the bones go for every page that isn't a chat, one function per
/// kind, top-down under the bar. Shared with the Android app's skeleton
/// (points there are dp), so both draw the same pages. Bones that would
/// pass the bottom of the safe area, or the composer, are left out.
nonisolated struct PageSkeletonLayout: Equatable {
    struct Bone: Equatable {
        enum Shape: Equatable { case line, circle }
        let shape: Shape
        let frame: CGRect
    }

    /// A group of rows (`.settings__group`): not a bone, but the surface
    /// with a hairline edge, its rows split by hairlines at `dividers`.
    struct Box: Equatable {
        let frame: CGRect
        let dividers: [CGFloat]
    }

    static let boxRadius: CGFloat = 14
    static let rowHeight: CGFloat = 52
    static let listRowHeight: CGFloat = 64
    static let fieldHeight: CGFloat = 44

    let bones: [Bone]
    let boxes: [Box]
    /// Where the composer rests, on the pages that have one.
    let composer: CGRect?

    private init(bones: [Bone], boxes: [Box], composer: CGRect?) {
        self.bones = bones
        self.boxes = boxes
        self.composer = composer
    }

    /// `bounds` is the screen's, `insets` its safe area. Not for a chat,
    /// whose shape is `ChatSkeletonLayout`'s.
    init(kind: PageSkeleton.Kind, bounds: CGRect, insets: UIEdgeInsets) {
        switch kind {
        case .newChat: self = Self.newChat(bounds: bounds, insets: insets)
        case .list: self = Self.list(bounds: bounds, insets: insets)
        case .settings: self = Self.settings(bounds: bounds, insets: insets)
        case .form: self = Self.form(bounds: bounds, insets: insets)
        case .page, .chat: self = Self.page(bounds: bounds, insets: insets)
        }
    }

    /// The greeting, three suggestions under it, and the composer at rest.
    static func newChat(bounds: CGRect, insets: UIEdgeInsets) -> Self {
        let column = SkeletonColumn(bounds: bounds, insets: insets)
        var builder = Builder(column: column, floor: column.composer.minY)
        let centre = insets.top + 0.4 * (column.composer.minY - insets.top)
        var y = (centre - 11).rounded()
        builder.centred(0.6, y: y, height: 22)
        y += 22 + 20
        for fraction in [0.44, 0.58, 0.36] {
            builder.centred(fraction, y: y, height: 32)
            y += 32 + 8
        }
        return Self(bones: builder.bones, boxes: [], composer: column.composer)
    }

    /// Rows of a list as far down as they fit: a mark, a name, and a line under it.
    static func list(bounds: CGRect, insets: UIEdgeInsets) -> Self {
        let column = SkeletonColumn(bounds: bounds, insets: insets)
        var builder = Builder(column: column, floor: bounds.height - insets.bottom)
        let firsts: [CGFloat] = [0.56, 0.42, 0.64, 0.48], seconds: [CGFloat] = [0.34, 0.52, 0.28, 0.44]
        let textLeft = column.left + 32 + 12
        let textWidth = max(column.width - 44, 0)
        var top = insets.top + 16
        var index = 0
        while builder.fits(top + listRowHeight) {
            builder.add(.circle, CGRect(x: column.left, y: top + (listRowHeight - 32) / 2, width: 32, height: 32))
            builder.add(.line, CGRect(x: textLeft, y: top + 16, width: (textWidth * firsts[index % 4]).rounded(), height: 12))
            builder.add(.line, CGRect(x: textLeft, y: top + 38, width: (textWidth * seconds[index % 4]).rounded(), height: 10))
            top += listRowHeight
            index += 1
        }
        return Self(bones: builder.bones, boxes: [], composer: nil)
    }

    /// Two sections of Settings: a heading, a muted line, and a group of rows.
    static func settings(bounds: CGRect, insets: UIEdgeInsets) -> Self {
        let column = SkeletonColumn(bounds: bounds, insets: insets)
        var builder = Builder(column: column, floor: bounds.height - insets.bottom)
        var y = insets.top + 16
        for (index, rows) in [4, 3].enumerated() {
            if index > 0 { y += 28 }
            builder.line(0.36, y: y, height: 14)
            y += 14 + 10
            builder.line(0.72, y: y, height: 10)
            y += 10 + 14
            y = builder.group(rows: rows, y: y)
        }
        return Self(bones: builder.bones, boxes: builder.boxes, composer: nil)
    }

    /// Four fields of a form: a label, and the field under it.
    static func form(bounds: CGRect, insets: UIEdgeInsets) -> Self {
        let column = SkeletonColumn(bounds: bounds, insets: insets)
        var builder = Builder(column: column, floor: bounds.height - insets.bottom)
        var y = insets.top + 16
        for (index, fraction) in [0.3, 0.22, 0.36, 0.26].enumerated() {
            if index > 0 { y += 20 }
            builder.line(fraction, y: y, height: 10)
            y += 10 + 8
            let field = CGRect(x: column.left, y: y, width: column.width, height: fieldHeight)
            if builder.fits(field.maxY) { builder.boxes.append(Box(frame: field, dividers: [])) }
            y += fieldHeight
        }
        return Self(bones: builder.bones, boxes: builder.boxes, composer: nil)
    }

    /// Any other page: a heading, two lines of text, and a group of rows.
    static func page(bounds: CGRect, insets: UIEdgeInsets) -> Self {
        let column = SkeletonColumn(bounds: bounds, insets: insets)
        var builder = Builder(column: column, floor: bounds.height - insets.bottom)
        var y = insets.top + 16
        builder.line(0.52, y: y, height: 20)
        y += 20 + 12
        let rhythm = ChatSkeletonLayout.lineRhythm, height = ChatSkeletonLayout.lineHeight
        for (index, fraction) in [1, 0.68].enumerated() {
            builder.line(fraction, y: (y + CGFloat(index) * rhythm + (rhythm - height) / 2).rounded(), height: height)
        }
        y += 2 * rhythm + 24
        _ = builder.group(rows: 4, y: y)
        return Self(bones: builder.bones, boxes: builder.boxes, composer: nil)
    }

    /// Mirrored for a right-to-left language.
    func mirrored(width: CGFloat) -> Self {
        func flip(_ rect: CGRect) -> CGRect { CGRect(x: width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) }
        return Self(bones: bones.map { Bone(shape: $0.shape, frame: flip($0.frame)) },
                    boxes: boxes.map { Box(frame: flip($0.frame), dividers: $0.dividers) },
                    composer: composer.map(flip))
    }

    var path: CGPath {
        let path = CGMutablePath()
        for bone in bones {
            switch bone.shape {
            case .line:
                path.addPath(CGPath(roundedRect: bone.frame, cornerWidth: bone.frame.height / 2, cornerHeight: bone.frame.height / 2, transform: nil))
            case .circle:
                path.addEllipse(in: bone.frame)
            }
        }
        return path
    }

    private struct Builder {
        let column: SkeletonColumn
        /// Nothing passes this.
        let floor: CGFloat
        var bones: [Bone] = []
        var boxes: [Box] = []

        func fits(_ bottom: CGFloat) -> Bool { bottom <= floor }

        mutating func add(_ shape: Bone.Shape, _ frame: CGRect) {
            if fits(frame.maxY) { bones.append(Bone(shape: shape, frame: frame)) }
        }

        /// A bone at the column's start, `fraction` of its width.
        mutating func line(_ fraction: CGFloat, y: CGFloat, height: CGFloat) {
            add(.line, CGRect(x: column.left, y: y, width: (column.width * fraction).rounded(), height: height))
        }

        mutating func centred(_ fraction: CGFloat, y: CGFloat, height: CGFloat) {
            let width = (column.width * fraction).rounded()
            add(.line, CGRect(x: column.left + ((column.width - width) / 2).rounded(), y: y, width: width, height: height))
        }

        /// A group of `rows` rows at `y`, as many as fit, each a label and
        /// a short value at its end. Returns where the group ends.
        mutating func group(rows: Int, y: CGFloat) -> CGFloat {
            let fitting = (0..<rows).filter { fits(y + CGFloat($0 + 1) * PageSkeletonLayout.rowHeight) }.count
            let frame = CGRect(x: column.left, y: y, width: column.width, height: CGFloat(rows) * PageSkeletonLayout.rowHeight)
            guard fitting > 0 else { return frame.maxY }
            let inner = max(column.width - 32, 0)
            let labels: [CGFloat] = [0.44, 0.56, 0.38, 0.5]
            for row in 0..<fitting {
                let middle = y + (CGFloat(row) + 0.5) * PageSkeletonLayout.rowHeight
                add(.line, CGRect(x: column.left + 16, y: middle - 6, width: (inner * labels[row % 4]).rounded(), height: 12))
                let short = (inner * 0.14).rounded()
                add(.line, CGRect(x: column.left + column.width - 16 - short, y: middle - 6, width: short, height: 12))
            }
            let shown = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: CGFloat(fitting) * PageSkeletonLayout.rowHeight)
            boxes.append(Box(frame: shown, dividers: (1..<max(fitting, 1)).map { y + CGFloat($0) * PageSkeletonLayout.rowHeight }))
            return frame.maxY
        }
    }
}

/// The skeleton itself: bones in `surfaceSelected` on the canvas, one
/// gradient masked by all of them sweeping left to right, and, for the
/// pages that have them, the composer at rest and groups of rows. Still
/// under Reduce Motion, following the setting as it changes.
final class PageSkeletonView: UIView {
    static let sweepSeconds: CFTimeInterval = 1.4
    private static let sweepKey = "sweep"

    let kind: PageSkeleton.Kind
    /// The page it stands for, its query included (`PageSkeleton.page(of:)`).
    let path: String
    /// When it came up: paints from before then are another page's.
    let shownAt = Date()
    weak var titleBone: TitleBone?
    var isSettling = false
    /// Whether Reduce Motion is on; replaced in tests.
    var reducesMotion: () -> Bool = { UIAccessibility.isReduceMotionEnabled } {
        didSet { updateSweep() }
    }

    private let backdrop = UIView()
    private let bones = CAShapeLayer()
    private let shine = CALayer()
    private let shineMask = CAShapeLayer()
    private let band = CAGradientLayer()
    private let composer = UIView()
    private var boxViews: [UIView] = []
    private var laidOut: CGRect = .null
    private var laidOutDirection: UIUserInterfaceLayoutDirection?

    var isSweeping: Bool { band.animation(forKey: Self.sweepKey) != nil }
    /// A chat's layout; nil for the other kinds.
    private(set) var layout: ChatSkeletonLayout?
    /// Every other kind's layout.
    private(set) var pageLayout: PageSkeletonLayout?

    init(kind: PageSkeleton.Kind, path: String) {
        self.kind = kind
        self.path = path
        super.init(frame: .zero)
        backgroundColor = Palette.canvas
        isUserInteractionEnabled = false
        accessibilityIdentifier = kind == .chat ? "chat.skeleton" : "page.skeleton"
        isAccessibilityElement = true
        accessibilityLabel = kind == .chat
            ? String(localized: "Loading chat", comment: "VoiceOver: a chat's shape shows while its page loads")
            : String(localized: "Loading", comment: "VoiceOver: a page's shape shows while it loads")
        // The page loading underneath stays out of VoiceOver's way until this goes.
        accessibilityViewIsModal = true

        // Groups sit under the bones, and the composer over them, as in a
        // chat, where it covers what would pass behind it.
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(backdrop)
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
        composer.isHidden = true
        addSubview(composer)

        styleColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PageSkeletonView, _: UITraitCollection) in
            view.styleColors()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(motionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let key = CGRect(origin: CGPoint(x: safeAreaInsets.top, y: safeAreaInsets.bottom), size: bounds.size)
        let direction = effectiveUserInterfaceLayoutDirection
        guard key != laidOut || direction != laidOutDirection else { return }
        laidOut = key
        laidOutDirection = direction
        let rightToLeft = direction == .rightToLeft

        let bonePath: CGPath
        var composerFrame: CGRect?
        var boxes: [PageSkeletonLayout.Box] = []
        if kind == .chat {
            let layout = ChatSkeletonLayout(bounds: bounds, insets: safeAreaInsets)
            self.layout = layout
            var flip = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: bounds.width, ty: 0)
            bonePath = rightToLeft ? layout.path.copy(using: &flip) ?? layout.path : layout.path
            composerFrame = layout.composer
        } else {
            var layout = PageSkeletonLayout(kind: kind, bounds: bounds, insets: safeAreaInsets)
            if rightToLeft { layout = layout.mirrored(width: bounds.width) }
            pageLayout = layout
            bonePath = layout.path
            composerFrame = layout.composer
            boxes = layout.boxes
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bones.frame = bounds
        bones.path = bonePath
        shine.frame = bounds
        shineMask.frame = bounds
        shineMask.path = bonePath
        // A diagonal band, about 20 degrees off upright whatever the screen's
        // shape. A gradient's points are in the layer's unit square, so its
        // bands lean by the screen's proportions too.
        band.frame = bounds
        let lean = bounds.width > 0 ? 0.36 * bounds.height / bounds.width : 0
        band.startPoint = CGPoint(x: 0, y: 0.5 - lean / 2)
        band.endPoint = CGPoint(x: 1, y: 0.5 + lean / 2)
        CATransaction.commit()
        composer.isHidden = composerFrame == nil
        composer.frame = composerFrame ?? .zero
        layOutBoxes(boxes)
        updateSweep(restart: true)
    }

    private func layOutBoxes(_ boxes: [PageSkeletonLayout.Box]) {
        boxViews.forEach { $0.removeFromSuperview() }
        let hairline = 1 / max(traitCollection.displayScale, 1)
        boxViews = boxes.map { box in
            let view = UIView(frame: box.frame)
            view.layer.cornerRadius = PageSkeletonLayout.boxRadius
            view.layer.cornerCurve = .continuous
            view.layer.borderWidth = 1
            view.clipsToBounds = true
            for divider in box.dividers {
                let line = UIView(frame: CGRect(x: 0, y: divider - box.frame.minY, width: box.frame.width, height: hairline))
                view.addSubview(line)
            }
            backdrop.addSubview(view)
            return view
        }
        styleColors()
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
        let line = Palette.line.resolvedColor(with: traitCollection)
        for view in [composer] + boxViews {
            view.backgroundColor = Palette.surface
            view.layer.borderColor = line.cgColor
            view.subviews.forEach { $0.backgroundColor = Palette.line }
        }
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

/// Where the page's title will go, until it does.
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
