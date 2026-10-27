import UIKit

/// The composer the app draws over a chat: the words, the files on their
/// way, and the web's controls, "+" (the attach sheet), the model, and
/// Send. While an answer works, Stop, with Send beside it once there are
/// words to steer with. Docked above the keyboard; the web view ends above it.
/// It only shows what the web composer's state says and reports what the
/// person did (ComposerComponent); every rule stays the server's.
final class ComposerView: UIView, UITextViewDelegate {
    enum Mode: Equatable {
        case typing
        case recording
        case transcribing
    }

    var onAction: ((ComposerAction) -> Void)?
    var onPlus: (() -> Void)?
    var onDictate: (() -> Void)?
    var onStopDictating: (() -> Void)?
    var onCancelDictating: (() -> Void)?

    private(set) var state: ComposerState?
    private(set) var mode: Mode = .typing

    private let box = RainbowBox()
    private let lockLabel = UILabel()
    private let chipsScroll = UIScrollView()
    private let chips = UIStackView()
    let textView = UITextView()
    private let placeholder = UILabel()
    private let plusButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let meter = LevelMeter()
    private let status = UILabel()
    private let cancelButton = UIButton(type: .system)
    private var textHeight: NSLayoutConstraint!
    private var meterTimer: Timer?
    var levelSource: (() -> Float)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Building

    private func build() {
        backgroundColor = .clear
        accessibilityIdentifier = "composer"

        lockLabel.font = .preferredFont(forTextStyle: .footnote)
        lockLabel.adjustsFontForContentSizeCategory = true
        lockLabel.textColor = Palette.inkMuted
        lockLabel.numberOfLines = 0
        lockLabel.isHidden = true
        lockLabel.accessibilityIdentifier = "composer.lock"

        box.backgroundColor = Palette.surface
        chips.axis = .horizontal
        chips.spacing = 6
        chipsScroll.showsHorizontalScrollIndicator = false
        chipsScroll.addSubview(chips)
        chipsScroll.isHidden = true
        chips.translatesAutoresizingMaskIntoConstraints = false

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = Palette.ink
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 2, bottom: 6, right: 2)
        textView.delegate = self
        textView.accessibilityIdentifier = "composer.text"
        textView.accessibilityLabel = String(localized: "Message")

        placeholder.font = textView.font
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = Palette.inkFaint
        placeholder.isUserInteractionEnabled = false

        configure(plusButton, symbol: "plus", label: String(localized: "Add"), identifier: "composer.plus")
        plusButton.addAction(UIAction { [weak self] _ in self?.onPlus?() }, for: .primaryActionTriggered)

        modelButton.showsMenuAsPrimaryAction = true
        modelButton.accessibilityIdentifier = "composer.model"
        var modelConfiguration = UIButton.Configuration.plain()
        modelConfiguration.baseForegroundColor = Palette.inkMuted
        modelConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 8)
        modelConfiguration.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        modelConfiguration.imagePlacement = .trailing
        modelConfiguration.imagePadding = 4
        modelConfiguration.titleLineBreakMode = .byTruncatingTail
        modelButton.configuration = modelConfiguration

        stopButton.accessibilityIdentifier = "composer.stop"
        stopButton.accessibilityLabel = String(localized: "Stop response")
        stopButton.addAction(UIAction { [weak self] _ in self?.stopTapped() }, for: .primaryActionTriggered)
        stopButton.layer.cornerRadius = 17
        stopButton.setImage(UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)), for: .normal)
        stopButton.isHidden = true

        sendButton.accessibilityIdentifier = "composer.send"
        sendButton.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .primaryActionTriggered)
        sendButton.layer.cornerRadius = 17
        sendButton.tintColor = Palette.inkInverted
        sendButton.backgroundColor = Palette.ink

        configure(cancelButton, symbol: "xmark", label: String(localized: "Cancel dictation"), identifier: "composer.cancelDictation")
        cancelButton.addAction(UIAction { [weak self] _ in self?.onCancelDictating?() }, for: .primaryActionTriggered)
        cancelButton.isHidden = true

        status.font = .preferredFont(forTextStyle: .subheadline)
        status.textColor = Palette.inkMuted
        status.isHidden = true
        meter.isHidden = true

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controls = UIStackView(arrangedSubviews: [plusButton, cancelButton, meter, status, spacer, modelButton, stopButton, sendButton])
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = 6

        let inner = UIStackView(arrangedSubviews: [chipsScroll, textView, controls])
        inner.axis = .vertical
        inner.spacing = 2
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        box.translatesAutoresizingMaskIntoConstraints = false

        let outer = UIStackView(arrangedSubviews: [lockLabel, box])
        outer.axis = .vertical
        outer.spacing = 6
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholder)

        textHeight = textView.heightAnchor.constraint(equalToConstant: 40)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 6),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            chips.topAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.topAnchor, constant: 4),
            chips.bottomAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.bottomAnchor),
            chips.leadingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.leadingAnchor),
            chips.trailingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.trailingAnchor),
            chipsScroll.heightAnchor.constraint(equalTo: chips.heightAnchor, constant: 4),
            textHeight,
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 7),
            placeholder.widthAnchor.constraint(lessThanOrEqualTo: textView.widthAnchor, constant: -14),
            stopButton.widthAnchor.constraint(equalToConstant: 34),
            stopButton.heightAnchor.constraint(equalToConstant: 34),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),
            plusButton.widthAnchor.constraint(equalToConstant: 34),
            plusButton.heightAnchor.constraint(equalToConstant: 34),
            cancelButton.widthAnchor.constraint(equalToConstant: 34),
            meter.widthAnchor.constraint(equalToConstant: 120),
            meter.heightAnchor.constraint(equalToConstant: 24)
        ])
        modelButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        refreshControls()
    }

    private func configure(_ button: UIButton, symbol: String, label: String, identifier: String) {
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        button.tintColor = Palette.ink
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        button.layer.cornerRadius = 17
        button.layer.borderWidth = 1
        button.layer.borderColor = Palette.line.cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        [plusButton, cancelButton].forEach { $0.layer.borderColor = Palette.line.cgColor }
        sendButton.backgroundColor = Palette.ink
        styleStop()
    }

    // MARK: State

    func update(_ state: ComposerState) {
        self.state = state
        placeholder.text = state.placeholder.isEmpty ? String(localized: "Ask anything") : state.placeholder
        lockLabel.text = state.lockReason
        lockLabel.isHidden = !(state.locked && state.lockReason?.isEmpty == false)
        textView.isEditable = !state.locked
        if state.locked { textView.resignFirstResponder() }

        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for attachment in state.attachments {
            let chip = AttachmentChip(attachment: attachment)
            chip.onRemove = { [weak self] in self?.onAction?(.remove(id: attachment.id)) }
            chips.addArrangedSubview(chip)
        }
        chipsScroll.isHidden = state.attachments.isEmpty

        let selected = state.selectedModel
        modelButton.configuration?.title = selected?.name
        modelButton.accessibilityLabel = selected.map { String(localized: "Model: \($0.name)") }
        modelButton.menu = UIMenu(title: String(localized: "Model"), children: state.models.enumerated().map { index, model in
            UIAction(title: model.name, subtitle: model.rate, state: model.selected ? .on : .off) { [weak self] _ in
                self?.onAction?(.model(index: index))
            }
        })
        refreshControls()
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        meterTimer?.invalidate()
        meterTimer = nil
        switch mode {
        case .typing:
            status.text = nil
        case .recording:
            status.text = nil
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.meter.push(self.levelSource?() ?? 0)
                }
            }
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Recording. Tap stop when you're done."))
        case .transcribing:
            status.text = String(localized: "Transcribing…")
        }
        refreshControls()
    }

    /// Shows a line in place of the words for a moment, like a refusal.
    func flash(_ message: String) {
        lockLabel.text = message
        lockLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.lockLabel.text == message else { return }
            self.lockLabel.isHidden = !(self.state?.locked == true && self.state?.lockReason?.isEmpty == false)
            self.lockLabel.text = self.state?.lockReason
        }
    }

    private func refreshControls() {
        let state = state
        let recording = mode == .recording
        let transcribing = mode == .transcribing
        let busy = recording || transcribing

        textView.isHidden = busy
        placeholder.isHidden = !textView.text.isEmpty
        meter.isHidden = !recording
        status.isHidden = !transcribing
        cancelButton.isHidden = !busy
        plusButton.isHidden = busy
        plusButton.isEnabled = state?.locked != true
        modelButton.isHidden = busy || state == nil || state?.locked == true || state?.working == true || (state?.models.isEmpty ?? true)

        let text = textView.text ?? ""
        let image: String
        if recording {
            image = "stop.fill"
            sendButton.accessibilityLabel = String(localized: "Stop recording")
            sendButton.isEnabled = true
            sendButton.isHidden = false
            stopButton.isHidden = true
        } else if transcribing {
            image = "ellipsis"
            sendButton.accessibilityLabel = String(localized: "Transcribing")
            sendButton.isEnabled = false
            sendButton.isHidden = false
            stopButton.isHidden = true
        } else {
            let buttons = state?.buttons(text: text)
            image = "arrow.up"
            sendButton.accessibilityLabel = String(localized: "Send")
            sendButton.isEnabled = buttons?.sendEnabled == true
            sendButton.isHidden = buttons?.send == false
            stopButton.isHidden = buttons?.stop != true
            stopButton.isEnabled = buttons?.stopEnabled == true
        }
        sendButton.setImage(UIImage(systemName: image, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)), for: .normal)
        stopButton.alpha = stopButton.isEnabled ? 1 : 0.35
        styleStop()
        sendButton.alpha = sendButton.isEnabled ? 1 : 0.35
        box.showsEdge = state?.locked != true
        box.alpha = state?.locked == true ? 0.7 : 1
        resizeText()
    }

    private func sendTapped() {
        switch mode {
        case .recording:
            onStopDictating?()
            return
        case .transcribing:
            return
        case .typing:
            break
        }
        guard let state else { return }
        let text = textView.text ?? ""
        guard state.buttons(text: text).sendEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAction?(.send(text: text))
        textView.text = ""
        refreshControls()
    }

    private func stopTapped() {
        guard mode == .typing, state?.buttons(text: textView.text ?? "").stopEnabled == true else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onAction?(.stop)
    }

    /// Stop alone is the filled button in Send's place; beside Send it steps
    /// back to an outline, so Send stays the one filled button.
    private func styleStop() {
        if sendButton.isHidden {
            stopButton.tintColor = Palette.inkInverted
            stopButton.backgroundColor = Palette.ink
            stopButton.layer.borderWidth = 0
        } else {
            stopButton.tintColor = Palette.ink
            stopButton.backgroundColor = .clear
            stopButton.layer.borderWidth = 1
            stopButton.layer.borderColor = Palette.line.cgColor
        }
    }

    /// Words from dictation, after what's typed.
    func append(_ words: String) {
        let current = textView.text ?? ""
        let joiner = current.isEmpty || current.hasSuffix(" ") || current.hasSuffix("\n") ? "" : " "
        textView.text = current + joiner + words
        refreshControls()
    }

    // MARK: UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        refreshControls()
    }

    private func resizeText() {
        let width = textView.bounds.width > 0 ? textView.bounds.width : 300
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let height = min(max(fitting, 40), 140)
        if abs(textHeight.constant - height) > 0.5 { textHeight.constant = height }
        textView.isScrollEnabled = fitting > 140
    }
}

/// The composer's box: the surface, a soft shadow, and the rainbow edge,
/// the brand's one place for it (Live Wire).
private final class RainbowBox: UIView {
    private let edge = CAGradientLayer()
    private let edgeMask = CAShapeLayer()

    var showsEdge = true {
        didSet { edge.isHidden = !showsEdge }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
        edge.colors = [0x44FF9A, 0x44B0FF, 0x8B44FF, 0xFF6644, 0xEBFF70].map { UIColor(hexValue: $0).cgColor }
        edge.locations = [0, 0.23, 0.48, 0.73, 1]
        edge.startPoint = CGPoint(x: 0, y: 0.5)
        edge.endPoint = CGPoint(x: 1, y: 0.5)
        edgeMask.fillColor = UIColor.clear.cgColor
        edgeMask.strokeColor = UIColor.black.cgColor
        edgeMask.lineWidth = 1.5
        edge.mask = edgeMask
        layer.addSublayer(edge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        edge.frame = bounds
        edgeMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 21.25).cgPath
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 22).cgPath
    }
}

/// A file on its way into the question: its name, size or progress, and a
/// remove button.
private final class AttachmentChip: UIView {
    var onRemove: (() -> Void)?

    init(attachment: ComposerState.Attachment) {
        super.init(frame: .zero)
        backgroundColor = Palette.canvasSunken
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = Palette.line.cgColor

        let icon = UIImageView(image: UIImage(systemName: Self.symbol(for: attachment.contentType)))
        icon.tintColor = Palette.inkMuted
        let name = UILabel()
        name.text = attachment.name
        name.font = .preferredFont(forTextStyle: .footnote)
        name.textColor = Palette.ink
        name.lineBreakMode = .byTruncatingMiddle
        let meta = UILabel()
        meta.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        meta.textColor = Palette.inkMuted
        meta.text = attachment.uploading ? "\(Int(attachment.progress ?? 0))%" : attachment.size
        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)), for: .normal)
        remove.tintColor = Palette.inkMuted
        remove.accessibilityLabel = String(localized: "Remove \(attachment.name)")
        remove.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [icon, name, meta, remove])
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            name.widthAnchor.constraint(lessThanOrEqualToConstant: 150),
            remove.widthAnchor.constraint(equalToConstant: 24)
        ])

        if attachment.uploading {
            let bar = UIProgressView(progressViewStyle: .bar)
            bar.progress = Float((attachment.progress ?? 0) / 100)
            bar.progressTintColor = Palette.live
            bar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
            ])
        }
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func symbol(for contentType: String?) -> String {
        guard let contentType else { return "doc" }
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType == "application/pdf" { return "doc.richtext" }
        if contentType.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }
}

/// The microphone's level, as a row of bars that scroll in from the right.
private final class LevelMeter: UIView {
    private var levels = [Float](repeating: 0, count: 24)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Recording")
        accessibilityTraits = .updatesFrequently
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(UIAccessibility.isReduceMotionEnabled ? 0.5 : level)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let step = rect.width / CGFloat(levels.count)
        Palette.inkMuted.setFill()
        for (index, level) in levels.enumerated() {
            let height = max(2, rect.height * CGFloat(level))
            UIBezierPath(roundedRect: CGRect(x: CGFloat(index) * step, y: (rect.height - height) / 2, width: step * 0.55, height: height), cornerRadius: 1).fill()
        }
    }
}

extension UIColor {
    convenience init(hexValue: UInt32) {
        self.init(red: CGFloat((hexValue >> 16) & 0xFF) / 255, green: CGFloat((hexValue >> 8) & 0xFF) / 255, blue: CGFloat(hexValue & 0xFF) / 255, alpha: 1)
    }
}
