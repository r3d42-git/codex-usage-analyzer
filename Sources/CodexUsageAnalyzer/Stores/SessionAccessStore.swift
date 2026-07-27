import AppKit
import Foundation

@MainActor
final class SessionAccessStore {
    private let bookmarkKey = "selectedSessionsDirectoryBookmark"

    var savedDirectory: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale { try? save(url) }
        return url
    }

    func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Codex-Sitzungsordner auswählen"
        panel.message = "Wähle normalerweise ~/.codex/sessions. Die App liest ausschließlich die darin enthaltenen Sitzungslogs."
        panel.prompt = "Ordner verwenden"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = savedDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try save(url)
            return url
        } catch {
            return nil
        }
    }

    func acquireDirectory() throws -> ScopedDirectoryAccess {
        guard let url = savedDirectory else { throw AccessError.noSelection }
        guard url.startAccessingSecurityScopedResource() else { throw AccessError.accessDenied(url) }
        return ScopedDirectoryAccess(url: url)
    }

    private func save(_ url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
}

final class ScopedDirectoryAccess {
    let url: URL
    private var isActive = true

    init(url: URL) { self.url = url }

    func stop() {
        guard isActive else { return }
        url.stopAccessingSecurityScopedResource()
        isActive = false
    }

    deinit { stop() }
}

enum AccessError: LocalizedError {
    case noSelection
    case accessDenied(URL)

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "Wähle zuerst den Codex-Sitzungsordner aus."
        case .accessDenied(let url):
            return "Der Zugriff auf \(url.path) wurde nicht gewährt. Wähle den Ordner bitte erneut aus."
        }
    }
}
