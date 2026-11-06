import SwiftUI
import UIKit

/// The Chat with Work mark writing itself, while a page or the sidebar loads
/// (the web's `application/logo_draw`): logo.svg's own white bubble and black
/// scribble, with a stroke along the scribble's centre line (the Rails app's
/// `script/logo_pen`, from the outside in, the W last) masked to the scribble,
/// so what shows is always the logo's own shape. It writes from the lip, holds,
/// rewinds from the W, and takes a breath. With Reduce Motion on, it's the
/// still logo.
final class LogoDrawView: UIView {
    private let bubble = CAShapeLayer()
    private let ink = CAShapeLayer()
    private let scribble = CAShapeLayer()
    private let drawing = CALayer()
    private let animationKey = "write"
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Loading")
        accessibilityTraits = .updatesFrequently

        bubble.fillColor = UIColor.white.cgColor
        bubble.fillRule = .evenOdd
        ink.fillColor = nil
        ink.strokeColor = UIColor.black.cgColor
        ink.lineCap = .round
        ink.lineJoin = .round
        scribble.fillColor = UIColor.black.cgColor
        drawing.mask = scribble
        drawing.addSublayer(ink)
        layer.addSublayer(bubble)
        layer.addSublayer(drawing)

        observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMotion() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        let scale = side / LogoPaths.size.width
        var transform = CGAffineTransform(
            translationX: (bounds.width - LogoPaths.size.width * scale) / 2,
            y: (bounds.height - LogoPaths.size.height * scale) / 2
        ).scaledBy(x: scale, y: scale)
        var offset = transform.translatedBy(x: LogoPaths.offset.x, y: LogoPaths.offset.y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawing.frame = bounds
        bubble.path = LogoPaths.bubble.copy(using: &offset)
        scribble.path = LogoPaths.scribble.copy(using: &offset)
        ink.path = LogoPaths.pen.copy(using: &transform)
        ink.lineWidth = LogoPaths.penWidth * scale
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateMotion()
    }

    private func updateMotion() {
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else {
            ink.removeAnimation(forKey: animationKey)
            ink.strokeEnd = 1
            return
        }
        guard ink.animation(forKey: animationKey) == nil else { return }
        ink.strokeEnd = 1
        let write = CAKeyframeAnimation(keyPath: "strokeEnd")
        write.values = [0, 1, 1, 0, 0]
        write.keyTimes = [0, 0.45, 0.62, 0.92, 1]
        let ease = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.55, 1)
        write.timingFunctions = [ease, CAMediaTimingFunction(name: .linear), ease, CAMediaTimingFunction(name: .linear)]
        write.duration = 4
        write.repeatCount = .infinity
        write.isRemovedOnCompletion = false
        ink.add(write, forKey: animationKey)
    }
}

/// The same, for SwiftUI's sidebar.
struct LogoDraw: UIViewRepresentable {
    func makeUIView(context: Context) -> LogoDrawView { LogoDrawView() }
    func updateUIView(_ uiView: LogoDrawView, context: Context) {}
}

extension LogoDrawView {
    /// Stands in for a web screen's spinner: Hotwire Native shows and hides the
    /// spinner as visits go, so the logo lives inside it and follows, and the
    /// spinner's own spokes are clear.
    static func replaceSpinner(in spinner: UIActivityIndicatorView, side: CGFloat) {
        spinner.color = .clear
        let logo = LogoDrawView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        spinner.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: spinner.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: spinner.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: side),
            logo.heightAnchor.constraint(equalToConstant: side)
        ])
    }
}

/// The mark's shapes, in logo.svg's own units.
enum LogoPaths {
    static let size = CGSize(width: 166.94864, height: 167.91972)
    /// logo.svg's group moves its two shapes by this; the pen is already placed.
    static let offset = CGPoint(x: 2.4985955, y: 2.5004155)
    /// Wide enough that the whole pen covers every inked pixel (the Rails app's `LogoMark::PEN_WIDTH`).
    static let penWidth: CGFloat = 22

    static let bubble = SVGPath.cgPath("M 75.667969,-2.4335938 C 67.094311,-2.0873269 57.765622,-0.35526525 47.943359,3.46875 34.703204,8.6234826 20.951071,17.144265 10.996094,30.802734 1.0144122,44.497842 -4.4269065,63.19012 -1.8710937,85.470703 0.2068526,103.58469 14.111871,130.56652 49.568359,140.33594 c 4.179589,1.15172 8.152774,1.72455 12.167969,2.13281 -0.08727,0.24109 -0.106866,0.16573 -0.201172,0.45117 v 0.002 c -0.09582,0.2897 -0.04459,0.62276 -0.11914,0.91993 -0.0011,-0.0119 -0.0035,-0.0369 -0.0039,-0.041 -4.2e-5,3.1e-4 -0.002,0.0117 -0.002,0.0117 10e-7,2e-5 0.0028,0.0299 0.0039,0.041 -0.747133,2.98985 -0.577218,6.29177 0.388672,9.46289 1.063151,3.49043 2.951875,6.81787 5.869141,8.9375 2.223725,1.61403 5.081523,2.65903 7.544922,2.98437 2.106037,0.27813 3.593045,0.17131 4.802734,0.0996 3.471129,-0.20532 7.702231,-1.4893 11.119141,-3.17383 23.794234,-11.73043 51.706704,-37.53191 64.943354,-62.14453 v -0.004 c 4.27481,-7.949284 6.9281,-15.474937 7.97461,-22.156255 0.25989,-1.659246 0.44438,-3.38536 0.38086,-5.390625 -0.0513,-1.617833 -0.0329,-4.800051 -2.55664,-8.757813 -1.405,-2.20333 -3.86325,-4.676072 -7.38867,-5.970703 C 153.19797,57.264962 151.95081,57.071794 150.75977,57 151.2525,40.038896 142.10426,23.07414 126.33398,12.136719 120.19819,7.8810096 101.38915,-3.4724028 75.667969,-2.4335938 Z M 61.535156,142.92187 h -0.002 c -10e-7,10e-6 -0.0019,0.0151 -0.002,0.0156 z")
    static let scribble = SVGPath.cgPath("M 76.320312,9.2363281 C 68.92023,9.5472819 60.826332,11.064245 52.207031,14.419922 40.499208,18.978078 28.760138,26.376148 20.490234,37.722656 12.220331,49.069165 7.5337613,64.352786 9.8027344,84.132812 11.391454,97.982088 21.6793,120.4635 52.689453,129.00781 c 7.456678,2.05475 12.49028,2.50787 22,2.52539 3.112758,0.006 4.135851,0.0393 5.353516,0.0723 -0.973803,2.30969 -2.389741,5.52121 -4.164063,8.70312 -0.730963,1.30725 -1.439539,2.63197 -2.001953,3.73438 -0.562642,1.10285 -0.926458,1.77915 -1.1875,2.57031 -0.71676,2.16831 0.0351,4.79356 1.886719,6.13477 0.586098,0.42546 1.407677,0.73984 2.179687,0.84179 0.773448,0.10215 1.544064,0.0802 2.56836,0.0195 2.24503,-0.13184 3.80869,-0.59979 6.617187,-1.98437 20.396764,-10.0555 48.480974,-36.1397 59.791014,-57.169922 3.69561,-6.871438 5.9737,-13.682308 6.71485,-18.414062 0.18528,-1.182939 0.27851,-2.237528 0.24804,-3.199219 -0.0305,-0.961691 -0.10104,-1.842691 -0.7207,-2.814453 -0.30983,-0.485881 -0.8406,-1.001517 -1.5332,-1.25586 -0.69261,-0.254342 -1.43151,-0.20642 -1.99414,-0.03516 -1.12527,0.342528 -1.81583,0.992236 -2.5879,1.822266 -1.22329,1.314925 -1.93214,2.965624 -3.48242,5.716797 -1.55028,2.751172 -3.67238,6.407772 -6.66015,10.826171 -5.97555,8.8368 -15.40259,20.707912 -30.50391,34.171882 -2.63405,2.34853 -6.69607,5.74789 -10.208984,8.62109 0.798689,-2.10176 1.489172,-4.25037 1.705078,-6.25586 0.108427,-1.00714 0.121062,-1.99443 -0.210937,-3.02929 -0.332,-1.03487 -1.236701,-2.16105 -2.44336,-2.58204 -0.956797,-0.33388 -1.799975,-0.37311 -2.923828,-0.42773 -1.123853,-0.0546 -2.458691,-0.0636 -3.984375,-0.0586 -3.051368,0.01 -6.858926,0.0777 -10.984375,-0.0156 -8.250898,-0.1867 -17.776793,-1.07328 -24.558593,-4.06445 C 32.277914,104.93765 24.089072,92.396496 23.529297,76.470703 23.190836,66.845145 25.415784,56.162864 32.183594,46.738281 38.951403,37.313698 50.293712,29.03897 68.636719,24.367187 c 17.436609,-4.440896 33.737551,-0.866573 44.296871,6.884766 10.55933,7.751339 15.45193,19.294002 10.68946,32.044922 -1.93002,5.167065 -8.01007,14.230361 -14.42578,20.867187 -3.20786,3.318414 -6.52659,6.063308 -9.281254,7.523438 -1.377332,0.730065 -2.600276,1.12641 -3.517579,1.210937 -0.917302,0.08453 -1.475976,-0.06936 -2.011718,-0.464843 0.0016,0.0012 -0.423263,-0.492459 -0.75586,-1.486328 -0.332596,-0.99387 -0.622365,-2.408547 -0.833984,-4.056641 -0.423238,-3.296189 -0.556737,-7.533127 -0.554688,-11.728516 0.002,-4.195389 0.132443,-8.356057 0.203125,-11.613281 0.03534,-1.628612 0.05739,-3.028251 0.03711,-4.130859 -0.01014,-0.551304 -0.02866,-1.023572 -0.07031,-1.455078 -0.04165,-0.431507 0.02893,-0.70888 -0.378906,-1.498047 -1.829631,-3.539461 -6.568523,-4.222592 -9.832031,-1.898438 l -0.002,0.002 c -1.208089,0.862926 -6.456953,4.88218 -13.88086,16.587891 -5.571513,8.787584 -9.785983,14.144524 -12.609375,17.167969 -1.283852,1.37482 -2.189415,2.142908 -2.839843,2.632812 -0.556665,-0.693511 -0.994397,-1.676431 -1.111329,-3.990234 -0.165604,-3.276922 0.443094,-8.607494 2.154297,-16.742188 1.928747,-9.168579 2.651191,-14.9533 2.486328,-19.064453 -0.164862,-4.111153 -1.465129,-6.756143 -3.1875,-8.478515 -1.229876,-1.229878 -2.8317,-1.975809 -4.511718,-1.798829 -1.678614,0.176833 -3.199704,1.447298 -3.81836,3.078125 -0.264222,0.691769 -0.330511,1.205613 -0.447265,1.941407 -0.117115,0.738064 -0.218705,1.576976 -0.283203,2.396484 -0.250609,3.098746 -1.171765,8.403699 -2.773438,15.6875 -1.235266,5.616137 -3.237953,15.903297 -2.980469,25.029297 0.128742,4.563 0.779329,8.864002 2.669922,12.281258 1.890593,3.41724 5.428896,5.8177 9.953125,5.65039 2.982764,-0.11028 5.599705,-1.93453 8.511719,-4.33985 2.912014,-2.40532 5.984493,-5.564625 8.929687,-8.925782 C 72.99889,88.50277 76.69486,83.398484 79.316362,79.3145 c -0.07319,3.803537 0.01674,8.325233 0.78125,13.240234 0.621384,3.994837 1.630341,7.905706 3.462891,11.068366 1.83255,3.16265 4.801053,5.67458 8.6875,5.82617 11.266587,0.43935 21.558097,-8.07608 29.611337,-17.658207 8.05323,-9.582124 13.88724,-20.346185 15.84374,-26.259766 C 142.53374,50.931086 135.61304,32.871932 119.63867,21.792969 114.47555,18.21189 98.520561,8.3034669 76.320312,9.2363281 Z")
    static let pen = SVGPath.cgPath("M151.67 74.67 L151.50 76.25 L147.75 84.92 L145.58 89.17 L142.08 95.08 L139.00 99.67 L135.42 104.50 L130.33 110.67 L126.33 115.17 L117.92 123.67 L114.92 126.50 L110.25 130.67 L102.58 137.00 L96.00 138.83 L90.50 140.17 L89.92 141.50 L86.08 145.92 L82.00 149.92 L81.50 150.33 L81.08 150.42 L81.50 150.33 L82.00 149.92 L86.08 145.92 L89.92 141.50 L90.42 140.33 L90.00 139.50 L90.00 128.50 L92.00 126.50 L92.92 126.25 L92.00 126.50 L90.08 128.42 L89.83 128.33 L89.25 127.17 L88.67 127.08 L73.08 126.83 L64.92 126.00 L57.00 124.42 L51.83 122.83 L48.58 121.50 L43.50 118.92 L39.92 116.75 L35.58 113.58 L33.00 111.33 L29.67 107.92 L27.08 104.67 L24.67 100.92 L23.17 98.00 L21.75 94.58 L20.17 89.08 L19.50 85.17 L19.25 82.58 L19.00 78.75 L19.00 75.42 L19.50 68.75 L20.50 63.00 L21.25 60.08 L22.50 56.33 L24.83 51.08 L26.42 48.25 L28.58 44.92 L31.25 41.50 L33.25 39.25 L36.42 36.17 L39.75 33.42 L43.58 30.67 L46.83 28.67 L52.58 25.67 L56.00 24.17 L59.92 22.67 L65.33 20.92 L68.92 20.00 L73.17 19.17 L80.25 18.42 L83.17 18.42 L90.75 19.00 L94.83 19.50 L98.42 20.17 L102.08 21.08 L106.17 22.42 L109.50 23.75 L114.33 26.17 L118.33 28.67 L121.00 30.67 L122.75 32.17 L126.17 35.67 L128.67 38.92 L130.17 41.33 L131.50 44.00 L132.83 47.75 L133.67 51.92 L134.42 57.92 L133.83 63.08 L132.92 66.75 L131.75 69.92 L130.17 73.25 L127.83 77.33 L123.92 83.17 L120.42 87.67 L116.33 92.33 L112.25 96.25 L108.25 99.33 L105.58 100.83 L103.42 101.50 L97.17 102.75 L94.67 102.08 L91.92 100.92 L91.25 100.25 L90.67 99.17 L89.58 95.67 L88.92 91.83 L88.50 88.00 L88.25 82.92 L88.25 75.42 L86.00 73.17 L87.08 69.33 L88.33 65.75 L88.75 62.67 L88.33 65.75 L87.08 69.33 L86.00 73.08 L76.75 76.92 L71.67 84.50 L68.67 88.50 L65.83 92.00 L63.00 95.17 L60.08 98.00 L53.08 100.08 L52.58 100.08 L50.67 99.42 L49.83 99.08 L49.42 98.67 L48.75 97.33 L48.33 95.83 L47.83 92.00 L47.67 88.50 L48.42 78.58 L49.50 72.25 L51.17 64.42 L52.33 57.50 L52.50 55.50 L51.92 50.58 L51.83 48.67")
}

/// Just enough of SVG's path grammar for logo.svg: moves, lines and cubic curves, absolute and relative.
enum SVGPath {
    static func cgPath(_ data: String) -> CGPath {
        let path = CGMutablePath()
        let characters = Array(data)
        var index = 0
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Character = "M"

        func skipSeparators() {
            while index < characters.count, characters[index] == " " || characters[index] == "," || characters[index].isNewline {
                index += 1
            }
        }

        func number() -> CGFloat {
            skipSeparators()
            let begin = index
            while index < characters.count {
                let character = characters[index]
                let startsExponent = (character == "e" || character == "E") && index > begin
                let signsExponent = (character == "-" || character == "+") && index > begin && "eE".contains(characters[index - 1])
                let plain = character.isNumber || character == "." || ((character == "-" || character == "+") && index == begin)
                guard plain || startsExponent || signsExponent else { break }
                index += 1
            }
            return CGFloat(Double(String(characters[begin..<index])) ?? 0)
        }

        func point(relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            skipSeparators()
            guard index < characters.count else { break }
            if characters[index].isLetter {
                command = characters[index]
                index += 1
                if command == "z" || command == "Z" {
                    path.closeSubpath()
                    current = start
                }
                continue
            }
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                current = point(relative: relative)
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"
            case "L":
                current = point(relative: relative)
                path.addLine(to: current)
            case "H":
                let x = number()
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case "V":
                let y = number()
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case "C":
                let one = point(relative: relative), two = point(relative: relative), end = point(relative: relative)
                path.addCurve(to: end, control1: one, control2: two)
                current = end
            default:
                index += 1
            }
        }
        return path.copy() ?? path
    }
}
