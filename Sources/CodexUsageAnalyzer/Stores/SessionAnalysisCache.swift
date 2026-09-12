import CryptoKit
import Darwin
import Foundation

/// Disposable local summaries. Raw log contents are never copied to the cache.
struct SessionAnalysisCache: Sendable {
    let directory: URL
    // Bump when parsing/normalization semantics change. Prices are recalculated on use.
    static let schemaVersion = 1

    static var local: Self {
        Self(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.c5vcpq5gsr.codexusageanalyzer/SessionAnalysis", isDirectory: true))
    }

    struct Entry: Codable, Sendable {
        let fingerprint: Fingerprint
        let session: UsageSession?
    }

    private struct Document: Codable {
        let version: Int
        let source: String
        let entries: [String: Entry]
    }

    func fileURL(for root: URL) -> URL {
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest).json")
    }

    func load(root: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL(for: root)),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.version == Self.schemaVersion,
              document.source == root.standardizedFileURL.path else { return [:] }
        return document.entries
    }

    func save(_ entries: [String: Entry], root: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let document = Document(version: Self.schemaVersion, source: root.standardizedFileURL.path, entries: entries)
        try JSONEncoder().encode(document).write(to: fileURL(for: root), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL(for: root).path)
    }

    struct Fingerprint: Codable, Equatable, Sendable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        /// Fresh stat on every call, including after parsing; URL resource caches can be stale.
        static func read(_ url: URL) -> Self? {
            var info = stat()
            let result = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return lstat(path, &info)
            }
            guard result == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
            return Self(device: info.st_dev, inode: info.st_ino, size: info.st_size,
                        modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                        changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
        }
    }
}
