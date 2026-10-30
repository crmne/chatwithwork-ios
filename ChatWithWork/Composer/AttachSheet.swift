import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// What the "+" sheet offers, from the composer's state.
struct AttachOptions {
    var acceptsFiles: Bool
    var permissionModes: ComposerState.PermissionModes? = nil
    var canScan: Bool = VNDocumentCameraViewController.isSupported
    var hasCamera: Bool = UIImagePickerController.isSourceTypeAvailable(.camera)
}

/// The "+" sheet: recent photos (where the person lets the app see their
/// library), then Camera, Photos, Files, Scan and the page’s permission modes. Dictation and web search
/// are one tap away in the composer's bar, and tools and models live
/// elsewhere, so "+" never becomes a drawer of everything.
/// (On the web, "+" holds only what its bar has no room for; at phone width
/// the app's bar has room for all of it.)
struct AttachSheet: View {
    enum Choice {
        case camera, photos, files, scan
        case permissionMode(String)
        case recent(PHAsset)
    }

    let options: AttachOptions
    var heightChanged: (CGFloat) -> Void = { _ in }
    let choose: (Choice) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var permissionIconWidth = 20
    @State private var recent: [PHAsset] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if options.acceptsFiles, !recent.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(recent, id: \.localIdentifier) { asset in
                                Button { choose(.recent(asset)) } label: { RecentThumbnail(asset: asset) }
                                    .accessibilityLabel(String(localized: "Recent photo"))
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 160 : 72), spacing: 8)], spacing: 8) {
                    if options.acceptsFiles {
                        if options.hasCamera { tile("Camera", "camera", .camera, id: "attach.camera") }
                        tile("Photos", "photo.on.rectangle", .photos, id: "attach.photos")
                        tile("Files", "doc", .files, id: "attach.files")
                        if options.canScan { tile("Scan", "doc.viewfinder", .scan, id: "attach.scan") }
                    }
                }
                if let modes = options.permissionModes {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Changes").font(.caption).foregroundStyle(Color(Palette.inkFaint))
                        ForEach(modes.options) { option in
                            Button { choose(.permissionMode(option.value)) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: option.value == "everything" ? "exclamationmark.octagon" : option.value == "edits" ? "pencil" : "hand.raised")
                                        .frame(width: permissionIconWidth)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option.label).foregroundStyle(Color(Palette.ink))
                                        if let description = option.description {
                                            Text(description).font(.caption).foregroundStyle(Color(Palette.inkMuted))
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "checkmark").opacity(option.selected ? 1 : 0)
                                }
                                .padding(.vertical, 8)
                                .foregroundStyle(Color(Palette.inkMuted))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(option.disabled)
                            .accessibilityIdentifier("composer.permission." + option.value)
                            .accessibilityAddTraits(option.selected ? [.isSelected] : [])
                        }
                    }
                }
            }
            .padding(20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: AttachSheetHeight.self, value: geometry.size.height)
            })
        }
        .tint(Color(Palette.ink))
        .onPreferenceChange(AttachSheetHeight.self, perform: heightChanged)
        .task { if options.acceptsFiles { recent = await RecentPhotos.load() } }
    }

    private func tile(_ title: LocalizedStringKey, _ symbol: String, _ choice: Choice, id: String) -> some View {
        Button { choose(choice) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.footnote)
            }
            .foregroundStyle(Color(Palette.ink))
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(Palette.canvasSunken)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

private nonisolated struct AttachSheetHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Measure only local sheet content; the web receives no native layout data here.
final class AttachSheetSizing {
    var height: CGFloat = 360
    weak var sheet: UISheetPresentationController?

    func update(_ height: CGFloat) {
        guard height > 0, abs(self.height - height) > 1 else { return }
        self.height = height
        sheet?.invalidateDetents()
    }
}

private struct RecentThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(Palette.canvasSunken))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            image = await RecentPhotos.thumbnail(asset)
        }
    }
}

/// The library’s latest photos when access was already granted. The system
/// photo picker and camera work without library access.
enum RecentPhotos {
    static func load(limit: Int = 12) async -> [PHAsset] {
        // Opening permissions must not request photo access. The system photo picker
        // works without it; recent photos appear only when access was already given.
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    static func thumbnail(_ asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 160, height: 160), contentMode: .aspectFill, options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    static func data(_ asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 2560, height: 2560), contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// Turns what the pickers return into files for `attach`.
enum ComposerFiles {
    /// The most one file may be: past it, the bridge would carry a very
    /// long string, and the person is told to attach it from a computer.
    static let largest = 25 * 1024 * 1024

    static func photo(_ image: UIImage, name: String = "Photo") -> ComposerFile? {
        let scaled = image.scaledDown(toLongestSide: 2560)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.82) else { return nil }
        return ComposerFile(name: "\(name).jpg", type: "image/jpeg", bytes: jpeg)
    }

    static func file(at url: URL) -> ComposerFile? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= largest else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return ComposerFile(name: url.lastPathComponent, type: type, bytes: data)
    }

    /// A scan's pages as one PDF, the way the web takes a scan.
    static func pdf(from scan: VNDocumentCameraScan, name: String = "Scan") -> ComposerFile? {
        guard scan.pageCount > 0 else { return nil }
        let first = scan.imageOfPage(at: 0)
        let bounds = CGRect(origin: .zero, size: first.size)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for index in 0..<scan.pageCount {
                let page = scan.imageOfPage(at: index)
                context.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                page.draw(in: CGRect(origin: .zero, size: page.size))
            }
        }
        return ComposerFile(name: "\(name).pdf", type: "application/pdf", bytes: data)
    }
}

private extension UIImage {
    func scaledDown(toLongestSide longest: CGFloat) -> UIImage {
        let side = max(size.width, size.height)
        guard side > longest else { return self }
        let scale = longest / side
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
