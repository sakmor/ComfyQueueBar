import Foundation

enum ProgressExtensionInstaller {
    static func install(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".ComfyQueueBarProgress-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let stagedExtension = staging.appendingPathComponent("ComfyQueueBarProgress", isDirectory: true)
        try manager.copyItem(at: source, to: stagedExtension)
        // moveItem refuses an existing destination, including one created during copying.
        try manager.moveItem(at: stagedExtension, to: destination)
    }
}
