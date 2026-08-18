import Foundation

/// Loads/saves non-destructive document metadata (bookmarks, last page, rotation, annotations)
/// to an application-support sidecar keyed by a stable file identity.
enum MetaStore {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MeiPDF", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Stable identity derived from path + size + modification date so moved/changed files don't collide.
    static func fileID(for url: URL) -> String {
        let path = url.path
        var size: Int64 = 0
        var mtime: Double = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            if let date = attrs[.modificationDate] as? Date {
                mtime = date.timeIntervalSince1970
            }
        }
        let raw = "\(path)|\(size)|\(mtime)"
        let hash = raw.data(using: .utf8)!.map { String(format: "%02x", $0) }.joined()
        return String(hash.prefix(40))
    }

    static func metaURL(for url: URL) -> URL {
        directory.appendingPathComponent(fileID(for: url) + ".json", isDirectory: false)
    }

    static func load(for url: URL) -> DocumentMeta? {
        let u = metaURL(for: url)
        guard let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(DocumentMeta.self, from: data)
    }

    static func save(_ meta: DocumentMeta, for url: URL) {
        let u = metaURL(for: url)
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: u, options: .atomic)
    }

    static func remove(for url: URL) {
        try? FileManager.default.removeItem(at: metaURL(for: url))
    }
}
