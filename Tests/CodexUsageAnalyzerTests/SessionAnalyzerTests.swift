import XCTest
@testable import CodexUsageAnalyzer

final class SessionAnalyzerTests: XCTestCase {
    func testAnalysisNormalizesAndAggregatesFixtureLogs() throws {
        let result = try SessionAnalyzer().analyze(root: try fixtureDirectory())

        XCTAssertEqual(result.scannedFileCount, 2)
        XCTAssertEqual(result.sessions.count, 2)
        let alpha = try XCTUnwrap(result.sessions.first(where: { $0.sessionID == "fixture-alpha" }))
        XCTAssertEqual(alpha.project, "Alpha")
        XCTAssertEqual(alpha.model, "gpt-5.6-sol")
        XCTAssertEqual(alpha.effort, "hoch")
        XCTAssertEqual(alpha.inputTokens, 1_000)
        XCTAssertEqual(alpha.cachedInputTokens, 250)
        XCTAssertEqual(alpha.totalTokens, 1_050)
        XCTAssertEqual(alpha.malformedLines, 1)
        XCTAssertEqual(try XCTUnwrap(alpha.estimatedCredits), 0.1025, accuracy: 0.0000001)

        let beta = try XCTUnwrap(result.sessions.first(where: { $0.sessionID == "fixture-beta" }))
        XCTAssertEqual(beta.model, "future-model")
        XCTAssertEqual(beta.effort, "mittel")
        XCTAssertNil(beta.estimatedCredits)
        XCTAssertEqual(result.projects.count, 2)
        XCTAssertEqual(result.modelEffort.count, 2)
        XCTAssertEqual(try XCTUnwrap(result.daily.first(where: { $0.date == "2026-07-20" })).models, "gpt-5.6-sol")
    }

    func testDateFilterAndReportExports() throws {
        let result = try SessionAnalyzer().analyze(root: try fixtureDirectory(), since: date("2026-07-21"))
        XCTAssertEqual(result.sessions.map(\.sessionID), ["fixture-beta"])

        let report = ReportExporter.makeReport(from: result)
        XCTAssertTrue(report.html.contains("Codex-Verbrauch"))
        XCTAssertTrue(report.html.contains("Kosten teilweise unbekannt"))
        XCTAssertTrue(report.html.contains("Projekt oder Aufgabe durchsuchen"))
        XCTAssertEqual(Set(report.files.keys), ["codex_usage_report.html", "codex_usage_sessions.csv", "codex_usage_projects.csv", "codex_usage_daily.csv", "codex_usage_models_effort.csv"])
        let sessionsCSV = try XCTUnwrap(String(data: report.files["codex_usage_sessions.csv"]!, encoding: .utf8))
        XCTAssertTrue(sessionsCSV.contains("future-model"))
        XCTAssertEqual(Array(report.files["codex_usage_sessions.csv"]!.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    private func fixtureDirectory() throws -> URL {
        try XCTUnwrap(Bundle.module.resourceURL)
    }

    func testPricingCasesIncludeAstraAliasesSnapshotsAndUnknownModels() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "pricing-cases", withExtension: "json"))
        let cases = try JSONDecoder().decode([PricingCase].self, from: Data(contentsOf: url))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for (index, item) in cases.enumerated() {
            let events: [[String: Any]] = [
                ["timestamp": "2026-09-12T12:00:00Z", "payload": ["type": "turn_context", "model": item.model, "session_id": String(index)]],
                ["timestamp": "2026-09-12T12:01:00Z", "payload": ["type": "token_count", "total_token_usage": ["input_tokens": 1_000_000, "cached_input_tokens": 500_000, "output_tokens": 100_000, "reasoning_output_tokens": 25_000, "total_tokens": 1_100_000]]]
            ]
            let lines = try events.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n")
            try lines.write(to: root.appendingPathComponent("rollout-\(index).jsonl"), atomically: true, encoding: .utf8)
        }
        let result = try SessionAnalyzer().analyze(root: root)
        XCTAssertEqual(result.sessions.count, cases.count)
        for (index, item) in cases.enumerated() {
            let session = try XCTUnwrap(result.sessions.first { $0.sessionID == String(index) })
            if let expected = item.credits {
                XCTAssertEqual(try XCTUnwrap(session.estimatedCredits, item.model), expected, accuracy: 0.000001, item.model)
            } else {
                XCTAssertNil(session.estimatedCredits, item.model)
            }
            XCTAssertEqual(session.totalTokens, 1_100_000)
        }
        let daily = try XCTUnwrap(result.daily.first)
        XCTAssertEqual(daily.totals.estimatedCredits, cases.compactMap(\.credits).reduce(0, +), accuracy: 0.000001)
        XCTAssertFalse(daily.totals.creditsComplete)
        let report = ReportExporter.makeReport(from: result)
        let warning = try XCTUnwrap(report.html.components(separatedBy: "Keine Rate hinterlegt für: ").last?.components(separatedBy: ". Tokens").first)
        let unknownModels = warning.components(separatedBy: ", ")
        XCTAssertTrue(unknownModels.contains("codex-auto-review"))
        XCTAssertFalse(unknownModels.contains("gpt-6-astra"))
        XCTAssertTrue(report.html.contains("Credits"))
        XCTAssertTrue(report.html.contains("Preisstand 12.09.2026"))
        XCTAssertTrue(report.html.contains("Kein Credit-Kaufpreis"))
        XCTAssertTrue(report.html.contains("API-Vergleich als Orientierung"))
        XCTAssertFalse(report.html.contains("API-Kosten"))
        let csv = String(decoding: try XCTUnwrap(report.files["codex_usage_sessions.csv"]), as: UTF8.self)
        XCTAssertTrue(csv.contains("262.5"))
        XCTAssertTrue(csv.contains("estimated_credits"))
    }

    private struct PricingCase: Decodable {
        let model: String
        let credits: Double?
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }
}
