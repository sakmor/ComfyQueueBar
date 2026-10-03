import Foundation

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try manager.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? manager.removeItem(at: root) }
let source = root.appendingPathComponent("source")
let destination = root.appendingPathComponent("installed")
try manager.createDirectory(at: source, withIntermediateDirectories: false)
try Data("extension".utf8).write(to: source.appendingPathComponent("__init__.py"))
try ProgressExtensionInstaller.install(from: source, to: destination)
let installed = try Data(contentsOf: destination.appendingPathComponent("__init__.py"))
assert(installed == Data("extension".utf8))
try Data("keep".utf8).write(to: destination.appendingPathComponent("sentinel"))
do {
    try ProgressExtensionInstaller.install(from: source, to: destination)
    fatalError("Existing destination must be refused")
} catch {}
let preserved = try Data(contentsOf: destination.appendingPathComponent("sentinel"))
assert(preserved == Data("keep".utf8))
let missing = root.appendingPathComponent("missing")
do {
    try ProgressExtensionInstaller.install(from: missing, to: root.appendingPathComponent("failed"))
    fatalError("Missing source must fail")
} catch {}
assert(!manager.fileExists(atPath: root.appendingPathComponent("failed").path))
let remaining = try manager.contentsOfDirectory(atPath: root.path)
assert(remaining.allSatisfy { !$0.hasPrefix(".ComfyQueueBarProgress-") })
print("Progress installer checks passed")
