import HotwireNative
import ObjectiveC
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// One chat screen's native composer: the view, the "+" sheet and its
/// pickers, and dictation. It shows what the web composer's state says and
/// hands what the person does to `send`, the reply channel of the
/// `composer` component's latest `connect`.
@MainActor
final class ComposerController: NSObject {
    private nonisolated(unsafe) static var key: UInt8 = 0

    /// A widget's or a shortcut's "Dictate": the next composer that connects
    /// starts listening.
    static var dictatesOnConnect = false
    /// New chat opened by the person (a tap on New chat, a shortcut): the
    /// next new chat's composer takes the keyboard, with its microphone beside
    /// the field. It never starts listening itself.
    static var focusesOnConnect = false
    /// Words shared into the app, for the next composer that connects.
    static var pendingText: String?
    /// Files shared into the app, handed to the next composer that connects.
    static var pendingFiles: [ComposerFile] = []

    let view = ComposerView()
    var send: ((ComposerAction) -> Void)?
    /// Told whenever the state changes (Live Activities follow `working`).
    var onState: ((ComposerState) -> Void)?

    private weak var screen: VisitableViewController?
    private let recorder = DictationRecorder()
    /// The screen stays on while dictation records or transcribes.
    let awake = ScreenAwake()
    private var startingDictation = false
    private var dictationTask: Task<Void, Never>?
    private var dictationGeneration = 0
    /// A recording that couldn't be transcribed, kept on the phone with the
    /// draft until it's sent again or discarded, so nothing said is lost.
    private(set) var keptRecording: (file: URL, path: String)?

    /// A kept recording goes with its composer (signing out, switching
    /// organizations): nothing would offer Try again or Discard for it.
    isolated deinit {
        if let kept = keptRecording { try? FileManager.default.removeItem(at: kept.file) }
    }
    var transcribeRecording: (URL, String, String?, AppEnvironment) async throws -> String = {
        try await DictationRecorder.transcribe($0, at: $1, csrfToken: $2, environment: $3)
    }
    private var lastLayout: CGSize?
    private let environment: AppEnvironment
    /// Sent from a page that turns into its chat in place (New chat, New
    /// bot, Decisions' All clear), which hasn't turned yet: a question it
    /// couldn't send comes back in the web composer's `text`, for the field.
    private var awaitingTurn = false

    /// The composer on `screen`, made and docked the first time it's asked for.
    static func on(_ screen: VisitableViewController, environment: AppEnvironment = .current) -> ComposerController {
        if let existing = objc_getAssociatedObject(screen, &key) as? ComposerController { return existing }
        let controller = ComposerController(screen: screen, environment: environment)
        objc_setAssociatedObject(screen, &key, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        KeyboardAvoidance.dock(controller.view, on: screen)
        // Its first layouts stay behind a page's skeleton, which draws its own composer.
        PageSkeleton.current(on: screen).map { screen.view.bringSubviewToFront($0) }
        return controller
    }

    static func existing(on screen: UIViewController) -> ComposerController? {
        objc_getAssociatedObject(screen, &key) as? ComposerController
    }

    private init(screen: VisitableViewController, environment: AppEnvironment) {
        self.screen = screen
        self.environment = environment
        super.init()

        view.onAction = { [weak self] action in
            guard let self else { return }
            if case .send = action, let url = self.screen?.currentVisitableURL, AppRoute(url: url).startsChats { self.awaitingTurn = true }
            self.send?(action)
        }
        view.onPlus = { [weak self] in self?.presentAttachSheet() }
        view.onModePill = { [weak self] in self?.presentChangesSheet() }
        view.onDictate = { [weak self] in self?.startDictating() }
        view.onModeChange = { [weak self] mode in self?.awake.isWanted = mode == .recording || mode == .transcribing }
        view.onWindowChange = { [weak self] onScreen in self?.awake.isOnScreen = onScreen }
        view.onStopDictating = { [weak self] in self?.finishDictating() }
        view.onCancelDictating = { [weak self] in self?.cancelDictating() }
        view.onRetryDictating = { [weak self] in self?.retryDictating() }
        view.onLayout = { [weak self] in self?.reportLayout() }
        view.onTextChange = { [weak self] text in self?.keepNewChatDraft(text) }
        view.levelSource = { [weak self] in self?.recorder.level ?? 0 }
        recorder.onLimit = { [weak self] in self?.finishDictating() }
    }

    func update(_ state: ComposerState, connected: Bool) {
        if let screen { KeyboardAvoidance.setOverlay(state.overlay || !state.visible, on: screen) }
        view.update(state)
        view.isHidden = !state.visible
        if !state.visible { view.textView.resignFirstResponder() }
        reportLayout()
        onState?(state)
        takeBackRefused(state)
        guard connected else { return }
        lastLayout = nil
        view.setNeedsLayout()
        takePending()
    }

    private func reportLayout() {
        guard view.state?.overlay == true, let screen, view.bounds.height > 0, screen.visitableView.bounds.width > 0 else { return }
        let size = CGSize(width: screen.visitableView.bounds.width, height: view.isHidden ? 0 : view.bounds.height)
        guard size != lastLayout else { return }
        lastLayout = size
        send?(.layout(height: Double(size.height), width: Double(size.width)))
    }

    /// The question a page that turns into its chat couldn't send (a refusal,
    /// an error, no connection): the page puts itself back as it was, and the
    /// words come back to the field it was sent from, now empty.
    private func takeBackRefused(_ state: ComposerState) {
        guard awaitingTurn, !state.working, !state.text.isEmpty else { return }
        awaitingTurn = false
        if view.textView.text.isEmpty { view.append(state.text) }
    }

    /// What a share, a widget or a Live Activity left for the next composer:
    /// shared words and files, and dictation to start.
    func takePending() {
        guard let state = view.state else { return }
        // A suggestion pressed on the page: its words in place of what's there, never joined to a draft, and the keyboard.
        if state.fill {
            view.replaceText(with: state.text)
            focus()
            return
        }
        // What the web composer holds already (a shared link, a draft) starts the native field,
        // or sending would replace it. A New chat left with words in it gives them to the
        // next one, the web's words after them.
        if view.textView.text.isEmpty {
            if let account = newChatAccount, let draft = NewChatDraft.text(in: account) {
                view.append(draft)
                if !state.text.isEmpty, !draft.contains(state.text) { view.append("\n\n" + state.text) }
            } else if !state.text.isEmpty {
                view.append(state.text)
            }
        }
        // Shared words join whatever draft is there, unless the server already put them in it.
        if let shared = Self.pendingText {
            Self.pendingText = nil
            if !view.textView.text.contains(shared) {
                view.append(view.textView.text.isEmpty ? shared : "\n\n" + shared)
            }
        }

        if !Self.pendingFiles.isEmpty, state.acceptsFiles {
            let files = Self.pendingFiles
            Self.pendingFiles = []
            send?(.attach(files: files))
        }
        if Self.dictatesOnConnect, state.dictation != nil, !state.locked {
            Self.dictatesOnConnect = false
            startDictating()
        }
        if Self.focusesOnConnect, let screen, AppRoute(url: screen.currentVisitableURL).kind == .newChat {
            takeKeyboard()
        }
    }

    /// The field takes the keyboard: New chat opened again while it's on top.
    func focus() {
        Self.focusesOnConnect = true
        takeKeyboard()
    }

    /// Focuses the field once it can have the keyboard: a shortcut's page can
    /// connect while the app is still coming forward or a sheet is leaving, and
    /// a redirected visit connects a screen that's replaced at once, so the
    /// wish lasts until a composer on screen has it.
    private func takeKeyboard(attempt: Int = 0) {
        guard Self.focusesOnConnect else { return }
        guard let state = view.state, state.visible, !state.locked, view.mode == .typing else {
            Self.focusesOnConnect = false
            return
        }
        if view.window?.windowScene?.activationState == .foregroundActive, screen?.presentedViewController == nil,
           screen?.navigationController?.presentedViewController == nil, view.textView.becomeFirstResponder() {
            Self.focusesOnConnect = false
            return
        }
        guard attempt < 40 else {
            if view.window != nil { Self.focusesOnConnect = false }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.takeKeyboard(attempt: attempt + 1) }
    }

    /// The organization of the New chat this composer is on; nil on any other page.
    private var newChatAccount: String? {
        guard let url = screen?.currentVisitableURL, AppRoute(url: url).kind == .newChat else { return nil }
        return AppRoute(url: url).account?.rawValue ?? ""
    }

    /// Keeps what's typed in New chat for the next New chat when it's left
    /// without sending (Back, another place): the web keeps no draft for a
    /// chat that doesn't exist yet, and the field's words are the app's own
    /// until Send.
    private func keepNewChatDraft(_ text: String) {
        guard let account = newChatAccount else { return }
        NewChatDraft.set(text, in: account)
    }

    /// Whether New chat on top of `navigator` has the keyboard.
    static func hasKeyboard(onNewChatIn navigator: UINavigationController) -> Bool {
        onNewChat(navigator)?.view.textView.isFirstResponder == true
    }

    /// The composer of the new chat on screen, if that's what the shell
    /// shows: New chat on top of the main stack, pushed or the place at its
    /// root (path configuration v4), with nothing over it.
    static func onNewChat(_ navigator: UINavigationController) -> ComposerController? {
        guard navigator.presentedViewController == nil,
              let screen = navigator.topViewController as? VisitableViewController,
              AppRoute(url: screen.currentVisitableURL).kind == .newChat,
              let composer = existing(on: screen), composer.view.state != nil
        else { return nil }
        return composer
    }

    // MARK: The "+" sheet

    private func presentAttachSheet() {
        guard let state = view.state else { return }
        presentSheet(AttachOptions(
            acceptsFiles: state.acceptsFiles,
            permissionModes: state.permissionModes,
            webSearch: view.webSearchFolded ? state.webSearch : nil,
            narrowing: state.narrowing
        ))
    }

    private func presentChangesSheet() {
        guard let modes = view.state?.permissionModes else { return }
        presentSheet(.changes(modes))
    }

    private func presentSheet(_ options: AttachOptions) {
        guard let screen else { return }
        view.textView.resignFirstResponder()

        let sizing = AttachSheetSizing()
        var host: UIHostingController<AttachSheet>!
        host = UIHostingController(rootView: AttachSheet(options: options, heightChanged: sizing.update) { [weak self] choice in
            if case .webSearch = choice { self?.handle(choice); return }
            host.dismiss(animated: true) { self?.handle(choice) }
        })
        host.view.backgroundColor = Palette.surface
        if let sheet = host.sheetPresentationController {
            let accessible = screen.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            sheet.detents = [.custom { context in min(sizing.height, context.maximumDetentValue) }, .large()]
            sizing.sheet = sheet
            if accessible { sheet.selectedDetentIdentifier = .large }
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        screen.present(host, animated: true)
    }

    private func handle(_ choice: AttachSheet.Choice) {
        switch choice {
        case .camera: presentCamera()
        case .photos: presentPhotos()
        case .files: presentFiles()
        case .scan: presentScanner()
        case .permissionMode(let value):
            guard view.state?.canSelectPermissionMode(value) == true else { return }
            send?(.permissionMode(value: value))
        case .webSearch(let on):
            guard let webSearch = view.state?.webSearch, view.state?.locked != true, !webSearch.disabled || !on else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            send?(.webSearch(on: on))
        case .narrow:
            guard view.state?.narrowing != nil else { return }
            send?(.narrow)
        case .recent(let asset):
            Task {
                if let image = await RecentPhotos.data(asset), let file = ComposerFiles.photo(image) { attach([file]) }
            }
        }
    }

    private func attach(_ files: [ComposerFile]) {
        guard !files.isEmpty else {
            view.flash(String(localized: "That file couldn't be attached here. Files over 25 MB attach from a computer."))
            return
        }
        send?(.attach(files: files))
    }

    private func presentCamera() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        screen?.present(picker, animated: true)
    }

    private func presentPhotos() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 10
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        screen?.present(picker, animated: true)
    }

    private func presentFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        screen?.present(picker, animated: true)
    }

    private func presentScanner() {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        screen?.present(scanner, animated: true)
    }

    // MARK: Dictation

    func startDictating() {
        guard view.mode == .typing, !startingDictation, view.state?.dictation != nil else { return }
        startingDictation = true
        dictationGeneration += 1
        let generation = dictationGeneration
        view.textView.resignFirstResponder()
        dictationTask = Task {
            defer {
                if generation == dictationGeneration { startingDictation = false }
            }
            do {
                try await recorder.start()
                guard !Task.isCancelled, generation == dictationGeneration else { return }
                view.setMode(.recording)
            } catch {
                guard !Task.isCancelled, generation == dictationGeneration else { return }
                if (error as? DictationRecorder.Failure) == .microphoneRefused {
                    view.flash(String(localized: "Chat with Work needs the microphone to dictate. Turn it on in Settings."))
                } else {
                    view.flash(String(localized: "Dictation couldn't start. Try again."))
                }
            }
        }
    }

    private func finishDictating() {
        guard view.mode == .recording else { return }
        guard let file = recorder.stop() else {
            view.setMode(.typing)
            view.flash(String(localized: "Nothing was heard. Try again a little closer."))
            return
        }
        guard let state = view.state, let dictation = state.dictation else {
            try? FileManager.default.removeItem(at: file)
            view.setMode(.typing)
            return
        }
        transcribe(file, at: dictation.url, state: state)
    }

    /// Kept separate from recording so a late server result can never own a newer session.
    @discardableResult
    func transcribe(_ file: URL, at path: String, state: ComposerState) -> Task<Void, Never> {
        dictationTask?.cancel()
        dictationGeneration += 1
        let generation = dictationGeneration
        view.setMode(.transcribing)
        keptRecording = nil
        let task = Task {
            var failure: String?
            defer {
                if generation == dictationGeneration {
                    if let failure {
                        // Kept, with Try again and Discard in the dictation line.
                        keptRecording = (file, path)
                        view.setMode(.failed(failure))
                    } else {
                        view.setMode(.typing)
                    }
                    dictationTask = nil
                }
            }
            do {
                let words = try await transcribeRecording(file, path, state.csrfToken, environment)
                try? FileManager.default.removeItem(at: file)
                guard !Task.isCancelled, generation == dictationGeneration else { return }
                if !words.isEmpty {
                    view.append(words)
                    send?(.text(words))
                }
            } catch {
                guard !Task.isCancelled, generation == dictationGeneration else {
                    try? FileManager.default.removeItem(at: file)
                    return
                }
                let reason = error as? DictationRecorder.Failure ?? .unavailable
                switch reason {
                case .rejected(let words):
                    try? FileManager.default.removeItem(at: file)
                    view.flash(words)
                case .refused(let words):
                    failure = words
                default:
                    failure = String(localized: "Couldn't transcribe.")
                }
            }
        }
        dictationTask = task
        return task
    }

    /// Sends a recording that couldn't be transcribed again.
    @discardableResult
    func retryDictating() -> Task<Void, Never>? {
        guard case .failed = view.mode, let kept = keptRecording, let state = view.state else { return nil }
        return transcribe(kept.file, at: kept.path, state: state)
    }

    /// Cancel while it listens or transcribes; Discard for a recording that couldn't be transcribed.
    private func cancelDictating() {
        dictationGeneration += 1
        dictationTask?.cancel()
        dictationTask = nil
        startingDictation = false
        recorder.cancel()
        if let kept = keptRecording {
            try? FileManager.default.removeItem(at: kept.file)
            keptRecording = nil
        }
        view.setMode(.typing)
    }

}

// MARK: - Pickers

extension ComposerController: PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
    UIDocumentPickerDelegate, VNDocumentCameraViewControllerDelegate {
    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let images = PickedImages()
        let group = DispatchGroup()
        for (index, result) in results.enumerated() where result.itemProvider.canLoadObject(ofClass: UIImage.self) {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                if let image = image as? UIImage { images.set(image, at: index) }
                group.leave()
            }
        }
        let picked = !results.isEmpty
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                picker.dismiss(animated: true)
                guard picked else { return }
                let files = images.inOrder.enumerated().compactMap { index, image in ComposerFiles.photo(image, name: "Photo \(index + 1)") }
                self.attach(files)
            }
        }
    }

    // UIKit calls the rest on the main thread.
    nonisolated func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        MainActor.assumeIsolated {
            picker.dismiss(animated: true)
            if let image, let file = ComposerFiles.photo(image) { self.attach([file]) }
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        MainActor.assumeIsolated { picker.dismiss(animated: true) }
    }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        MainActor.assumeIsolated {
            self.attach(urls.compactMap(ComposerFiles.file(at:)))
        }
    }

    nonisolated func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        // Handed over on the main thread and only read there.
        nonisolated(unsafe) let scan = scan
        MainActor.assumeIsolated {
            controller.dismiss(animated: true)
            if let file = ComposerFiles.pdf(from: scan) { self.attach([file]) }
        }
    }

    nonisolated func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        MainActor.assumeIsolated { controller.dismiss(animated: true) }
    }

    nonisolated func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            controller.dismiss(animated: true)
            self.view.flash(String(localized: "The scan didn't finish. Try again."))
        }
    }
}

/// Photos as the picker hands them over, from its own queues, kept in the
/// order they were picked.
nonisolated final class PickedImages: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [Int: UIImage] = [:]

    func set(_ image: UIImage, at index: Int) {
        lock.withLock { images[index] = image }
    }

    var inOrder: [UIImage] {
        lock.withLock { images.keys.sorted().compactMap { images[$0] } }
    }
}

/// The words typed in New chat, per organization, kept while the app runs:
/// leaving a New chat without sending (Back, another place) keeps them, the
/// next New chat opens with them, and Send and signing out clear them.
@MainActor
enum NewChatDraft {
    private static var texts: [String: String] = [:]

    static func text(in account: String) -> String? {
        texts[account]
    }

    static func set(_ text: String, in account: String) {
        texts[account] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    static func clear() {
        texts = [:]
    }
}
