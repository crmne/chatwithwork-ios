import UIKit

/// The composer the app draws over a chat: the words, the files on their
/// way, and the web's controls, each one tap away as in the web's bar: "+"
/// (the attach sheet), the microphone, the web search globe, the model, and
/// Send. While an answer works, Stop, with Send beside it once there are
/// words to steer with. While dictation listens or transcribes, its line
/// takes the field's place (DictationLine), since nobody types meanwhile.
/// Docked above the keyboard; the web view ends above it.
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
    private let dictateButton = UIButton(type: .system)
    private let webSearchButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let dictationLine = DictationLine()
    private let cancelButton = UIButton(type: .system)
    private var textHeight: NSLayoutConstraint!
    private var meterTimer: Timer?
    private var recordingStarted: Date?
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

        configure(dictateButton, symbol: "mic", label: String(localized: "Dictate"), identifier: "composer.dictate")
        dictateButton.addAction(UIAction { [weak self] _ in self?.onDictate?() }, for: .primaryActionTriggered)
        dictateButton.isHidden = true

        configure(webSearchButton, symbol: "globe", label: String(localized: "Search the web"), identifier: "composer.webSearch")
        webSearchButton.addAction(UIAction { [weak self] _ in self?.webSearchTapped() }, for: .primaryActionTriggered)
        webSearchButton.isHidden = true

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

        dictationLine.isHidden = true

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controls = UIStackView(arrangedSubviews: [plusButton, dictateButton, webSearchButton, cancelButton, spacer, modelButton, stopButton, sendButton])
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = 6

        let inner = UIStackView(arrangedSubviews: [chipsScroll, textView, dictationLine, controls])
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
            dictateButton.widthAnchor.constraint(equalToConstant: 34),
            dictateButton.heightAnchor.constraint(equalToConstant: 34),
            webSearchButton.widthAnchor.constraint(equalToConstant: 34),
            webSearchButton.heightAnchor.constraint(equalToConstant: 34),
            cancelButton.widthAnchor.constraint(equalToConstant: 34),
            cancelButton.heightAnchor.constraint(equalToConstant: 34),
            // As tall as the field at rest, so the box doesn't jump.
            dictationLine.heightAnchor.constraint(equalToConstant: 40)
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
        [plusButton, dictateButton, cancelButton].forEach { $0.layer.borderColor = Palette.line.cgColor }
        styleWebSearch()
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
        if modelButton.configuration?.title != selected?.name {
            modelButton.configuration?.title = selected?.name
            // While an answer works the server's picker has no models, so the
            // title goes and comes back while the button is hidden, and UIKit
            // keeps the hidden button's old size: a chevron without a name.
            modelButton.invalidateIntrinsicContentSize()
        }
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
            recordingStarted = nil
            dictationLine.reset()
        case .recording:
            let started = Date()
            recordingStarted = started
            dictationLine.show(.listening(seconds: 0))
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.dictationLine.push(self.levelSource?() ?? 0)
                    self.dictationLine.show(.listening(seconds: Int(Date().timeIntervalSince(started))))
                }
            }
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Listening. Tap stop when you're done."))
        case .transcribing:
            dictationLine.show(.transcribing)
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Transcribing"))
        }
        refreshControls()
        if mode == .typing, !textView.text.isEmpty {
            // The words are back in the field: VoiceOver goes there.
            UIAccessibility.post(notification: .layoutChanged, argument: textView)
        }
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
        dictationLine.isHidden = !busy
        placeholder.isHidden = !textView.text.isEmpty
        cancelButton.isHidden = !busy
        plusButton.isHidden = busy
        plusButton.isEnabled = state?.locked != true && state?.acceptsFiles != false
        dictateButton.isHidden = busy || state?.dictation == nil
        dictateButton.isEnabled = state?.locked != true
        dictateButton.alpha = dictateButton.isEnabled ? 1 : 0.35
        webSearchButton.isHidden = busy || state?.webSearch == nil
        styleWebSearch()
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

    /// The globe switches web search like the sheet's switch. Where the
    /// model can't search it stays, faint, and says why. A locked composer
    /// changes nothing, as its other buttons.
    private func webSearchTapped() {
        guard mode == .typing, state?.locked != true, let webSearch = state?.webSearch else { return }
        if webSearch.disabled {
            if let note = webSearch.note, !note.isEmpty { flash(note) }
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        onAction?(.webSearch(on: !webSearch.on))
        // Turning it on says where searches go, as the web's switch does beside it.
        if !webSearch.on, let note = webSearch.note, !note.isEmpty { flash(note) }
    }

    /// On: the live wash and edge, as the web's pressed globe. Off: an
    /// outline like "+". Faint where the model can't search.
    private func styleWebSearch() {
        let webSearch = state?.webSearch
        let on = webSearch?.on == true
        let inert = webSearch?.disabled == true || state?.locked == true
        webSearchButton.tintColor = on ? Palette.liveInk : Palette.ink
        webSearchButton.backgroundColor = on ? Palette.live.withAlphaComponent(0.12) : .clear
        webSearchButton.layer.borderColor = (on ? Palette.live.withAlphaComponent(0.4) : Palette.line).cgColor
        webSearchButton.alpha = inert ? 0.35 : 1
        webSearchButton.accessibilityValue = on ? String(localized: "On") : String(localized: "Off")
        webSearchButton.accessibilityHint = webSearch?.disabled == true ? webSearch?.note : nil
        webSearchButton.accessibilityTraits = inert ? (on ? [.button, .selected, .notEnabled] : [.button, .notEnabled]) : on ? [.button, .selected] : .button
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

/// Dictation's line, in the field's place while it listens or transcribes,
/// as the web composer's `[data-dictating]` line: a live dot and
/// "Listening", the microphone's level across the composer, and how long
/// it has listened; or "Transcribing" alone. VoiceOver reads it as one
/// element: what it's doing, and the time.
final class DictationLine: UIView {
    enum Phase: Equatable {
        case listening(seconds: Int)
        case transcribing
    }

    private let dot = UIView()
    private let label = UILabel()
    private let waveform = Waveform()
    private let time = UILabel()
    private(set) var phase: Phase?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "composer.dictation"
        isAccessibilityElement = true
        accessibilityTraits = .updatesFrequently

        dot.backgroundColor = Palette.live
        dot.layer.cornerRadius = 3.5
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Palette.inkMuted
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
        time.textColor = Palette.inkMuted
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        waveform.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [dot, label, waveform, time])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(6, after: dot)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            waveform.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ phase: Phase) {
        guard phase != self.phase else { return }
        self.phase = phase
        switch phase {
        case .listening(let seconds):
            label.text = String(localized: "Listening")
            time.text = Self.clock(seconds)
            dot.isHidden = false
            waveform.isHidden = false
            time.isHidden = false
            accessibilityLabel = String(localized: "Listening")
            accessibilityValue = Self.spokenDuration(seconds)
        case .transcribing:
            label.text = String(localized: "Transcribing…")
            dot.isHidden = true
            waveform.isHidden = true
            time.isHidden = true
            accessibilityLabel = String(localized: "Transcribing")
            accessibilityValue = nil
        }
    }

    func push(_ level: Float) {
        waveform.push(level)
    }

    func reset() {
        phase = nil
        waveform.clear()
    }

    /// "0:07", "1:23", as the web's dictation clock.
    static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// "7 seconds", "1 minute, 23 seconds", for VoiceOver.
    static func spokenDuration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
        return formatter.string(from: TimeInterval(seconds)) ?? ""
    }
}

/// The microphone's level as neutral bars across the composer, newest on
/// the right, each as tall as the level (as the web's
/// `.chat-prompt__waveform`). Under Reduce Motion the bars stand still,
/// half height, lit up to the level.
private final class Waveform: UIView {
    private static let barWidth: CGFloat = 3
    private static let gap: CGFloat = 2
    private var levels: [Float] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func push(_ level: Float) {
        levels.append(max(0, min(1, level)))
        if levels.count > 200 { levels.removeFirst(levels.count - 200) }
        setNeedsDisplay()
    }

    func clear() {
        levels = []
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let step = Self.barWidth + Self.gap
        let count = max(1, Int((rect.width + Self.gap) / step))
        let still = UIAccessibility.isReduceMotionEnabled
        let latest = CGFloat(levels.last ?? 0)
        let shown = Array(levels.suffix(count))
        // Bars not yet heard sit flat on the left, so the newest is always on the right.
        let padded = [Float](repeating: 0, count: count - shown.count) + shown
        for (index, level) in padded.enumerated() {
            let x = rect.maxX - CGFloat(count - index) * step + Self.gap
            let scale: CGFloat
            let alpha: CGFloat
            if still {
                scale = 0.5
                alpha = 0.25 + 0.75 * latest
            } else {
                scale = 0.08 + 0.92 * CGFloat(level)
                alpha = 1
            }
            let height = max(2, rect.height * scale)
            Palette.inkMuted.withAlphaComponent(alpha).setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: (rect.height - height) / 2, width: Self.barWidth, height: height), cornerRadius: 1).fill()
        }
    }
}

extension UIColor {
    convenience init(hexValue: UInt32) {
        self.init(red: CGFloat((hexValue >> 16) & 0xFF) / 255, green: CGFloat((hexValue >> 8) & 0xFF) / 255, blue: CGFloat(hexValue & 0xFF) / 255, alpha: 1)
    }
}
