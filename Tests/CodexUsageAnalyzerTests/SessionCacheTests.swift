import XCTest
@testable import CodexUsageAnalyzer

final class SessionCacheTests: XCTestCase {
    func testCacheSurvivesNewAnalyzerAndDateChangesKeepEntireResumedSession() throws {
        try withWorkspace { root, cache in
            let old = root.appendingPathComponent("rollout-2020-01-01.jsonl")
            try log(id: "resumed", timestamp: "2020-01-01T12:00:00Z", input: 100).write(to: old, atomically: true, encoding: .utf8)
            try log(id: "recent", timestamp: "2026-09-12T12:00:00Z", input: 200).write(to: root.appendingPathComponent("rollout-recent.jsonl"), atomically: true, encoding: .utf8)
            let first = try SessionAnalyzer(cache: cache).analyze(root: root)
            XCTAssertEqual(first.readFileCount, 2)
            XCTAssertEqual(first.reusedFileCount, 0)

            let cutoff = ISO8601DateFormatter().date(from: "2026-09-10T12:00:00Z")!
            let warm = try SessionAnalyzer(cache: SessionAnalysisCache(directory: cache.directory)).analyze(root: root, since: cutoff)
            XCTAssertEqual(warm.readFileCount, 0)
            XCTAssertEqual(warm.reusedFileCount, 2)
            XCTAssertEqual(warm.sessions.map(\.sessionID), ["recent"])

            // Resume an old file. Folder/filename start dates must never exclude it.
            let continued = log(id: "resumed", timestamp: "2026-09-11T12:00:00Z", input: 300)
            let handle = try FileHandle(forWritingTo: old)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(("\n" + continued).utf8))
            try handle.close()
            let resumed = try SessionAnalyzer(cache: cache).analyze(root: root, since: cutoff)
            XCTAssertEqual(resumed.readFileCount, 1)
            XCTAssertEqual(resumed.reusedFileCount, 1)
            XCTAssertEqual(resumed.sessions.count, 2)
            let session = try XCTUnwrap(resumed.sessions.first { $0.sessionID == "resumed" })
            XCTAssertEqual(session.inputTokens, 300) // full cumulative total, not a 200-token delta
            XCTAssertLessThan(session.started, cutoff)
            let uncached = try SessionAnalyzer().analyze(root: root, since: cutoff)
            XCTAssertEqual(resumed.sessions, uncached.sessions)
            XCTAssertEqual(resumed.projects, uncached.projects)
            XCTAssertEqual(resumed.daily, uncached.daily)

            // In-memory date filtering requires no access to the log directory.
            try FileManager.default.removeItem(at: root)
            let empty = SessionAnalyzer().filtered(first, since: Date.distantFuture)
            XCTAssertTrue(empty.sessions.isEmpty)
            XCTAssertTrue(ReportRenderer.render(empty).contains("Keine Sessions mit Aktivität"))
            XCTAssertEqual(SessionAnalyzer().filtered(first, since: nil).sessions, first.sessions)
            let html = ReportRenderer.render(resumed)
            XCTAssertTrue(html.contains("Sessions mit Aktivität ab 10.09.2026."))
            XCTAssertTrue(html.contains("auch vor dem Datum"))
        }
    }

    func testChangesAdditionsDeletionsAndUnusableLogsInvalidateOnlyAffectedFiles() throws {
        try withWorkspace { root, cache in
            let a = root.appendingPathComponent("rollout-a.jsonl")
            let b = root.appendingPathComponent("rollout-b.jsonl")
            let pending = root.appendingPathComponent("rollout-pending.jsonl")
            try log(id: "a", input: 100).write(to: a, atomically: true, encoding: .utf8)
            try log(id: "b", input: 100).write(to: b, atomically: true, encoding: .utf8)
            try "{}".write(to: pending, atomically: true, encoding: .utf8)
            _ = try SessionAnalyzer(cache: cache).analyze(root: root)
            let warm = try SessionAnalyzer(cache: cache).analyze(root: root)
            XCTAssertEqual(warm.readFileCount, 0)
            XCTAssertEqual(warm.reusedFileCount, 3)

            // Same size and restored mtime: ctime must still invalidate the cached summary.
            let originalDate = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: a.path)[.modificationDate] as? Date)
            try log(id: "a", input: 900).write(to: a, atomically: false, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: a.path)
            try FileManager.default.removeItem(at: b)
            try log(id: "c", input: 400).write(to: root.appendingPathComponent("rollout-c.jsonl"), atomically: true, encoding: .utf8)
            try log(id: "pending", input: 700).write(to: pending, atomically: true, encoding: .utf8)
            let changed = try SessionAnalyzer(cache: cache).analyze(root: root)
            XCTAssertEqual(changed.readFileCount, 3)
            XCTAssertEqual(changed.reusedFileCount, 0)
            XCTAssertEqual(changed.sessions.reduce(0) { $0 + $1.inputTokens }, 2_000)
            XCTAssertFalse(changed.sessions.contains { $0.sessionID == "b" })
            XCTAssertFalse(cache.load(root: root).keys.contains { $0.hasSuffix("/rollout-b.jsonl") })
        }
    }

    func testCacheRepricesSummariesAndRecoversFromCorruptionAndVersionChanges() throws {
        try withWorkspace { root, cache in
            let file = root.appendingPathComponent("rollout-a.jsonl")
            try log(id: "a", input: 1_000_000).write(to: file, atomically: true, encoding: .utf8)
            _ = try SessionAnalyzer(cache: cache).analyze(root: root)
            let cacheURL = cache.fileURL(for: root)
            var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any])
            var entries = try XCTUnwrap(document["entries"] as? [String: [String: Any]])
            XCTAssertEqual(entries.count, 1)
            // FileManager may expand /var to /private/var while enumerating on macOS.
            let key = try XCTUnwrap(entries.keys.first)
            var entry = try XCTUnwrap(entries[key])
            var session = try XCTUnwrap(entry["session"] as? [String: Any])
            session["estimatedCredits"] = 999_999
            session["dateKey"] = "1900-01-01"
            entry["session"] = session
            entries[key] = entry
            document["entries"] = entries
            try JSONSerialization.data(withJSONObject: document).write(to: cacheURL)
            let repriced = try SessionAnalyzer(cache: cache).analyze(root: root)
            XCTAssertEqual(repriced.readFileCount, 0)
            XCTAssertEqual(repriced.sessions.first?.estimatedCredits, 250)
            XCTAssertEqual(repriced.sessions.first?.dateKey, "2026-09-12")

            document["version"] = -1
            try JSONSerialization.data(withJSONObject: document).write(to: cacheURL)
            XCTAssertEqual(try SessionAnalyzer(cache: cache).analyze(root: root).readFileCount, 1)
            try "broken".write(to: cacheURL, atomically: true, encoding: .utf8)
            XCTAssertEqual(try SessionAnalyzer(cache: cache).analyze(root: root).readFileCount, 1)
        }
    }

    func testCacheIsScopedBySourceAndWriteFailureDoesNotLoseResults() throws {
        try withWorkspace { root, cache in
            try log(id: "a").write(to: root.appendingPathComponent("rollout-a.jsonl"), atomically: true, encoding: .utf8)
            _ = try SessionAnalyzer(cache: cache).analyze(root: root)
            let other = root.appendingPathComponent("other")
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            try log(id: "other").write(to: other.appendingPathComponent("rollout-a.jsonl"), atomically: true, encoding: .utf8)
            let result = try SessionAnalyzer(cache: cache).analyze(root: other)
            XCTAssertEqual(result.readFileCount, 1)
            XCTAssertEqual(result.sessions.map(\.sessionID), ["other"])

            let blocked = root.appendingPathComponent("cache-is-a-file")
            try Data().write(to: blocked)
            let fallback = try SessionAnalyzer(cache: SessionAnalysisCache(directory: blocked)).analyze(root: root)
            XCTAssertTrue(fallback.cacheWriteFailed)
            XCTAssertEqual(fallback.sessions.count, 2)
        }
    }

    private func withWorkspace(_ body: (URL, SessionAnalysisCache) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try body(root, SessionAnalysisCache(directory: base.appendingPathComponent("cache")))
    }

    private func log(id: String, timestamp: String = "2026-09-12T12:00:00Z", input: Int = 100) -> String {
        """
        {"timestamp":"\(timestamp)","payload":{"type":"turn_context","session_id":"\(id)","model":"gpt-6-astra"}}
        {"timestamp":"\(timestamp)","payload":{"type":"token_count","total_token_usage":{"input_tokens":\(input),"total_tokens":\(input)}}}
        """
    }
}
