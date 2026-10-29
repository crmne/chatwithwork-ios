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
    private var startingDictation = false
    private var dictationTask: Task<Void, Never>?
    private var dictationGeneration = 0
    var transcribeRecording: (URL, String, String?, AppEnvironment) async throws -> String = {
        try await DictationRecorder.transcribe($0, at: $1, csrfToken: $2, environment: $3)
    }
    private var lastLayout: CGSize?
    private let environment: AppEnvironment

    /// The composer on `screen`, made and docked the first time it's asked for.
    static func on(_ screen: VisitableViewController, environment: AppEnvironment = .current) -> ComposerController {
        if let existing = objc_getAssociatedObject(screen, &key) as? ComposerController { return existing }
        let controller = ComposerController(screen: screen, environment: environment)
        objc_setAssociatedObject(screen, &key, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        KeyboardAvoidance.dock(controller.view, on: screen)
        return controller
    }

    static func existing(on screen: UIViewController) -> ComposerController? {
        objc_getAssociatedObject(screen, &key) as? ComposerController
    }

    private init(screen: VisitableViewController, environment: AppEnvironment) {
        self.screen = screen
        self.environment = environment
        super.init()

        view.onAction = { [weak self] action in self?.send?(action) }
        view.onPlus = { [weak self] in self?.presentAttachSheet() }
        view.onDictate = { [weak self] in self?.startDictating() }
        view.onStopDictating = { [weak self] in self?.finishDictating() }
        view.onCancelDictating = { [weak self] in self?.cancelDictating() }
        view.onLayout = { [weak self] in self?.reportLayout() }
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

    /// What a share, a widget or a Live Activity left for the next composer:
    /// shared words and files, and dictation to start.
    func takePending() {
        guard let state = view.state else { return }
        // What the web composer holds already (a shared link, a draft) starts the native field,
        // or sending would replace it.
        if view.textView.text.isEmpty, !state.text.isEmpty { view.append(state.text) }
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
    }

    /// The composer of the new chat on screen, if that's what the shell shows.
    static func onNewChat(_ navigator: UINavigationController) -> ComposerController? {
        guard navigator.presentedViewController == nil, navigator.viewControllers.count == 1,
              let screen = navigator.viewControllers.first as? VisitableViewController,
              AppRoute(url: screen.currentVisitableURL).kind == .newChat,
              let composer = existing(on: screen), composer.view.state != nil
        else { return nil }
        return composer
    }

    // MARK: The "+" sheet

    private func presentAttachSheet() {
        guard let screen, let state = view.state else { return }
        view.textView.resignFirstResponder()

        let options = AttachOptions(acceptsFiles: state.acceptsFiles)
        var host: UIHostingController<AttachSheet>!
        host = UIHostingController(rootView: AttachSheet(options: options) { [weak self] choice in
            host.dismiss(animated: true) { self?.handle(choice) }
        })
        host.view.backgroundColor = Palette.surface
        if let sheet = host.sheetPresentationController {
            // The recent photos and one row of tiles.
            sheet.detents = [.custom { _ in 240 }, .medium()]
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
        let task = Task {
            defer {
                if generation == dictationGeneration {
                    view.setMode(.typing)
                    dictationTask = nil
                }
            }
            do {
                let words = try await transcribeRecording(file, path, state.csrfToken, environment)
                guard !Task.isCancelled, generation == dictationGeneration else { return }
                if !words.isEmpty {
                    view.append(words)
                    send?(.text(words))
                }
            } catch {
                guard !Task.isCancelled, generation == dictationGeneration else { return }
                if case DictationRecorder.Failure.refused(let reason) = error {
                    view.flash(reason)
                } else {
                    view.flash(String(localized: "That didn't transcribe. Try again."))
                }
            }
        }
        dictationTask = task
        return task
    }

    private func cancelDictating() {
        dictationGeneration += 1
        dictationTask?.cancel()
        dictationTask = nil
        startingDictation = false
        recorder.cancel()
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
private final class PickedImages: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [Int: UIImage] = [:]

    func set(_ image: UIImage, at index: Int) {
        lock.withLock { images[index] = image }
    }

    var inOrder: [UIImage] {
        lock.withLock { images.keys.sorted().compactMap { images[$0] } }
    }
}
