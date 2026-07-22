import Foundation

/// Appends diagnostics to ~/Library/Application Support/Mumble/debug.log so we
/// can see runtime state even when launched via LaunchServices (where NSLog
/// doesn't surface to the unified log).
enum Log {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mumble")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    static func line(_ msg: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp) \(msg)\n"
        NSLog("Mumble: \(msg)")
        if let data = entry.data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
