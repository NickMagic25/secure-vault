import Darwin
import Foundation
import SecureVaultCore

protocol VaultChangeMonitoring: AnyObject {
    func start(onChange: @escaping @Sendable () -> Void)
    func stop()
}

final class VaultDirectoryMonitor: VaultChangeMonitoring {
    private let databaseURL: URL
    private let directoryURL: URL
    private let queue = DispatchQueue(label: "io.securevault.vault-directory-monitor")
    private var source: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?
    private var onChange: (@Sendable () -> Void)?
    private var lastWriteSignature: VaultWriteSignature

    init(databaseURL: URL = CredentialStore.defaultDatabaseURL) {
        self.databaseURL = databaseURL
        self.directoryURL = databaseURL.deletingLastPathComponent()
        self.lastWriteSignature = Self.writeSignature(databaseURL: databaseURL)
    }

    deinit {
        stop()
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        stop()
        self.onChange = onChange

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            lastWriteSignature = Self.writeSignature(databaseURL: databaseURL)
        } catch {
            onChange()
            return
        }

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            onChange()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleChange()
        }
        source.setCancelHandler {
            close(descriptor)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        pendingChange?.cancel()
        pendingChange = nil
        source?.cancel()
        source = nil
        onChange = nil
    }

    private func scheduleChange() {
        pendingChange?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.emitIfVaultWriteChanged()
        }
        pendingChange = workItem
        queue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func emitIfVaultWriteChanged() {
        let currentSignature = Self.writeSignature(databaseURL: databaseURL)
        guard currentSignature != lastWriteSignature else { return }

        lastWriteSignature = currentSignature
        onChange?()
    }

    private static func writeSignature(databaseURL: URL) -> VaultWriteSignature {
        VaultWriteSignature(
            database: fileSignature(databaseURL),
            wal: fileSignature(URL(fileURLWithPath: databaseURL.path + "-wal"))
        )
    }

    private static func fileSignature(_ url: URL) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        return FileSignature(
            modificationDate: attributes[.modificationDate] as? Date,
            size: attributes[.size] as? Int64
        )
    }
}

private struct VaultWriteSignature: Equatable {
    var database: FileSignature?
    var wal: FileSignature?
}

private struct FileSignature: Equatable {
    var modificationDate: Date?
    var size: Int64?
}
