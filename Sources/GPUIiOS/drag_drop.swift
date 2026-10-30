// Ported from: crates/gpui_ios/src/drag_drop.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import Foundation
import GPUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Document Picker Result Continuation Types

/// Continuation wrapper matching upstream `PickerResultSender` for single-URL (`promptForNewPath`)
/// and multi-URL (`promptForPaths`) `UIDocumentPickerViewController` flows.
public enum PickerResultSender: Sendable {
    case multiple(CheckedContinuation<[URL]?, Never>)
    case single(CheckedContinuation<URL?, Never>)
}

/// Retains the active `PickerResultSender` continuation and optional temporary export file URL
/// until `UIDocumentPickerViewController` finishes or cancels, matching upstream
/// `DocumentPickerCallbackContext`.
// PORT NOTE: Mutated exclusively on the main actor when `UIDocumentPickerDelegate` fires once.
public final class DocumentPickerCallbackContext: @unchecked Sendable {
    private var sender: PickerResultSender?
    private let temporaryExportUrl: URL?

    public init(sender: PickerResultSender, temporaryExportUrl: URL? = nil) {
        self.sender = sender
        self.temporaryExportUrl = temporaryExportUrl
    }

    @MainActor
    func complete(with urls: [URL]?) {
        guard let pending = sender else { return }
        sender = nil

        if let tempUrl = temporaryExportUrl {
            try? FileManager.default.removeItem(at: tempUrl)
        }

        switch pending {
        case .multiple(let continuation):
            continuation.resume(returning: urls)
        case .single(let continuation):
            continuation.resume(returning: urls?.first)
        }
    }

    deinit {
        if let pending = sender {
            switch pending {
            case .multiple(let continuation):
                continuation.resume(returning: nil)
            case .single(let continuation):
                continuation.resume(returning: nil)
            }
        }
        if let tempUrl = temporaryExportUrl {
            try? FileManager.default.removeItem(at: tempUrl)
        }
    }
}

// MARK: - UIDocumentPickerDelegate Implementation

// PORT NOTE: Replaces upstream ObjC runtime `ClassDecl("GPUIDocumentPickerDelegate")` with a native
// Swift `NSObject` conforming to `UIDocumentPickerDelegate` (ADR-0011).

@MainActor
final class GPUIDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let context: DocumentPickerCallbackContext
    /// Self-retaining cycle broken as soon as the picker completes or cancels so callers don't
    /// have to manually store delegate lifetimes across async suspensions.
    private var retainedSelf: GPUIDocumentPickerDelegate?

    init(context: DocumentPickerCallbackContext) {
        self.context = context
        super.init()
        self.retainedSelf = self
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        _ = controller
        var resolvedUrls: [URL] = []
        resolvedUrls.reserveCapacity(urls.count)

        for url in urls {
            let started = url.startAccessingSecurityScopedResource()
            resolvedUrls.append(url)
            if started {
                // Copy or retain access as appropriate; balance security-scoped resource once
                // resolved path is handed off when temporary bookmarking isn't held long-term.
                url.stopAccessingSecurityScopedResource()
            }
        }

        context.complete(with: resolvedUrls.isEmpty ? nil : resolvedUrls)
        retainedSelf = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        _ = controller
        context.complete(with: nil)
        retainedSelf = nil
    }
}

// MARK: - UIDropInteractionDelegate Implementation

// PORT NOTE: Replaces upstream ObjC runtime `ClassDecl("GPUIDropDelegate")` with a native Swift
// `NSObject` conforming to `UIDropInteractionDelegate` (ADR-0011).

/// Handles system-wide drag-and-drop file sessions (e.g. Split View / Slide Over from Files.app
/// on iPadOS and iOS) and forwards `FileDropEvent`s into `IosWindowState`.
@MainActor
final class GPUIDropDelegate: NSObject, UIDropInteractionDelegate {
    weak var windowState: IosWindowState?

    init(windowState: IosWindowState? = nil) {
        self.windowState = windowState
        super.init()
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        canHandle session: any UIDropSession
    ) -> Bool {
        _ = interaction
        return session.hasItemsConforming(toTypeIdentifiers: [
            UTType.fileURL.identifier,
            UTType.url.identifier,
            UTType.item.identifier,
        ]) || session.canLoadObjects(ofClass: NSURL.self)
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        sessionDidEnter session: any UIDropSession
    ) {
        guard let view = interaction.view, let state = windowState else { return }
        let position = gpuiPoint(from: session.location(in: view))
        _ = dispatchInput(state, .fileDrop(.pending(position: position)))
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        sessionDidUpdate session: any UIDropSession
    ) -> UIDropProposal {
        if let view = interaction.view, let state = windowState {
            let position = gpuiPoint(from: session.location(in: view))
            _ = dispatchInput(state, .fileDrop(.pending(position: position)))
        }
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        sessionDidExit session: any UIDropSession
    ) {
        _ = interaction
        _ = session
        guard let state = windowState else { return }
        _ = dispatchInput(state, .fileDrop(.exited))
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        performDrop session: any UIDropSession
    ) {
        guard let view = interaction.view, let state = windowState else { return }
        let dropPosition = gpuiPoint(from: session.location(in: view))
        let items = session.items
        guard !items.isEmpty else {
            _ = dispatchInput(state, .fileDrop(.exited))
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var collectedPaths: [String] = []

        for dragItem in items {
            let provider = dragItem.itemProvider
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, _, _ in
                    if let url {
                        let accessed = url.startAccessingSecurityScopedResource()
                        let path = Self.materializeDroppedFileIfNeeded(url)
                        if accessed {
                            url.stopAccessingSecurityScopedResource()
                        }
                        if let path {
                            lock.lock()
                            collectedPaths.append(path)
                            lock.unlock()
                        }
                    }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: NSURL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    if let nsUrl = object as? URL {
                        let path = nsUrl.isFileURL ? nsUrl.path : nsUrl.absoluteString
                        if !path.isEmpty {
                            lock.lock()
                            collectedPaths.append(path)
                            lock.unlock()
                        }
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak state] in
            MainActor.assumeIsolated {
                guard let state else { return }
                lock.lock()
                let paths = collectedPaths
                lock.unlock()

                if !paths.isEmpty {
                    _ = dispatchInput(
                        state,
                        .fileDrop(.entered(position: dropPosition, paths: ExternalPaths(paths: paths)))
                    )
                    _ = dispatchInput(
                        state,
                        .fileDrop(.submit(position: dropPosition))
                    )
                }
                _ = dispatchInput(state, .fileDrop(.exited))
            }
        }
    }

    func dropInteraction(
        _ interaction: UIDropInteraction,
        sessionDidEnd session: any UIDropSession
    ) {
        _ = interaction
        _ = session
        guard let state = windowState else { return }
        _ = dispatchInput(state, .fileDrop(.exited))
    }

    nonisolated private static func materializeDroppedFileIfNeeded(_ url: URL) -> String? {
        guard url.isFileURL else {
            return url.absoluteString
        }
        if FileManager.default.isReadableFile(atPath: url.path) {
            // Copy transient drag-and-drop inbox files into temporaryDirectory so GPUI handlers
            // can read them safely after UIDropSession's security scope ends.
            let destDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("gpui-ios-drops", isDirectory: true)
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let destUrl = destDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: destUrl)
            if (try? FileManager.default.copyItem(at: url, to: destUrl)) != nil {
                return destUrl.path
            }
            return url.path
        }
        return url.path
    }
}
#endif
