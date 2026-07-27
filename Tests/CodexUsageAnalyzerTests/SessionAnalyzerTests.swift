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
        XCTAssertNotNil(alpha.estimatedCredits)

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

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }
}
