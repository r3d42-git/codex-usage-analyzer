import XCTest
import WebKit
@testable import CodexUsageAnalyzer

final class ReportInteractionTests: XCTestCase {
    @MainActor
    func testNavigationFilteringPagingAndStateRestorationInWebKit() async throws {
        let view = try await loadReport(width: 1440)
        try await expect(view, "document.querySelectorAll('.report-panel:not([hidden])').length === 1 && !document.getElementById('overview').hidden")
        try await run(view, "document.querySelector('a[href=\"#projects\"]').click()")
        try await expect(view, "document.querySelectorAll('.project-table tr[data-name]:not([hidden])').length === 20")
        try await run(view, "document.querySelector('[data-pager=projects] [data-step=\"1\"]').click()")
        try await expect(view, "document.querySelectorAll('.project-table tr[data-name]:not([hidden])').length === 3")
        try await run(view, "document.getElementById('project-search').value = 'Group 0'; document.getElementById('project-search').dispatchEvent(new Event('input'))")
        try await expect(view, "document.querySelectorAll('.project-table tr[data-name]:not([hidden])').length === 1")
        // Duplicate display names must not combine sessions from different paths.
        try await run(view, "document.querySelector('.project-table tr:not([hidden]) .project-link').click()")
        try await expect(view, "!document.getElementById('session-list').hidden && document.querySelectorAll('.session:not([hidden])').length === 3")
        try await expect(view, "[...document.querySelectorAll('.session:not([hidden])')].every(row => row.dataset.project === '/test/Group 0')")
        try await run(view, "document.getElementById('reset-filters').click()")
        try await expect(view, "document.querySelectorAll('.session:not([hidden])').length === 25")
        try await run(view, "document.querySelector('[data-pager=sessions] [data-step=\"1\"]').click()")
        try await expect(view, "document.querySelector('[data-pager=sessions] .result-count').textContent.startsWith('26–50')")
        try await run(view, "document.getElementById('search').value = 'no-match'; document.getElementById('search').dispatchEvent(new Event('input'))")
        try await expect(view, "!document.getElementById('empty').hidden && document.querySelectorAll('.session:not([hidden])').length === 0")
        try await run(view, "document.getElementById('reset-filters').click(); document.getElementById('model').value = 'gpt-6-astra'; document.getElementById('model').dispatchEvent(new Event('input')); document.getElementById('effort').value = 'hoch'; document.getElementById('effort').dispatchEvent(new Event('input'))")
        try await expect(view, "[...document.querySelectorAll('.session:not([hidden])')].every(row => row.dataset.model === 'gpt-6-astra' && row.dataset.effort === 'hoch') && document.querySelectorAll('.session:not([hidden])').length > 0")
        let state = try await view.evaluateJavaScript("JSON.stringify(window.reportViewState())") as! String
        try await run(view, "document.getElementById('reset-filters').click(); document.querySelector('a[href=\"#overview\"]').click(); window.restoreReportViewState(\(state))")
        try await expect(view, "!document.getElementById('session-list').hidden && document.getElementById('model').value === 'gpt-6-astra' && document.getElementById('effort').value === 'hoch'")
        // Exercise the native navigation delegate too, not only the JavaScript restore function.
        let coordinator = ReportWebView.Coordinator()
        coordinator.pendingViewState = state
        let reloaded = WKWebView(frame: view.frame)
        reloaded.navigationDelegate = coordinator
        reloaded.loadHTMLString(ReportRenderer.render(fixture()), baseURL: nil)
        try await waitUntilReady(reloaded)
        try await expect(reloaded, "document.getElementById('model').value === 'gpt-6-astra' && !document.getElementById('session-list').hidden")
        try await run(view, "document.querySelector('a[href=\"#projects\"]').click(); document.getElementById('project-search').value = ''; document.getElementById('project-sort').value = 'credits'; document.getElementById('project-sort').dispatchEvent(new Event('input'))")
        try await expect(view, "document.querySelector('.project-table tbody tr:not([hidden])').dataset.credits !== ''")
    }

    @MainActor
    func testReportUsesSingleScrollSurfaceAtWideAndNarrowWidths() async throws {
        for width in [1920.0, 1440.0, 920.0, 600.0] {
            let view = try await loadReport(width: width)
            try await expect(view, "[...document.querySelectorAll('.bar')].every(bar => Math.abs(bar.getBoundingClientRect().bottom - bar.parentElement.getBoundingClientRect().bottom) < 1)", message: "Chart baseline: \(width)")
            for panel in ["overview", "projects", "session-list", "models"] {
                try await run(view, "document.querySelector('a[href=\"#\(panel)\"]').click()")
                try await expect(view, "document.documentElement.scrollWidth <= window.innerWidth + 1", message: "Horizontal overflow: \(width), \(panel)")
                try await expect(view, "![...document.querySelectorAll('main *')].some(el => el.getClientRects().length && /^(auto|scroll)$/.test(getComputedStyle(el).overflowY) && el.scrollHeight > el.clientHeight + 1)", message: "Nested vertical scroll area: \(width), \(panel)")
            }
        }
    }

    @MainActor
    func testEmptyReportAndEscapedProjectNames() async throws {
        let empty = AnalysisResult(sessions: [], projects: [], daily: [], modelEffort: [], scannedFileCount: 0, generatedAt: Date())
        let view = try await loadReport(width: 920, result: empty)
        try await run(view, "document.querySelector('a[href=\"#projects\"]').click()")
        try await expect(view, "!document.getElementById('projects-empty').hidden && document.querySelector('[data-pager=projects] [data-step=\"1\"]').disabled")
        try await run(view, "document.querySelector('a[href=\"#session-list\"]').click()")
        try await expect(view, "!document.getElementById('empty').hidden")
        let populated = try await loadReport(width: 920)
        try await expect(populated, "!window.injected && [...document.querySelectorAll('.project-link')].some(el => el.textContent.includes('<img'))")
    }

    @MainActor
    private func loadReport(width: Double, result: AnalysisResult? = nil) async throws -> WKWebView {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 800))
        view.loadHTMLString(ReportRenderer.render(result ?? fixture()), baseURL: nil)
        try await waitUntilReady(view)
        return view
    }

    @MainActor
    private func waitUntilReady(_ view: WKWebView) async throws {
        for _ in 0..<150 {
            if let ready = try? await view.evaluateJavaScript("typeof window.reportViewState === 'function'"), ready as? Bool == true {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "ReportInteractionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Report script did not initialize"])
    }

    @MainActor
    private func run(_ view: WKWebView, _ script: String) async throws {
        _ = try await view.evaluateJavaScript("(() => { \(script); return true; })()")
    }

    @MainActor
    private func expect(_ view: WKWebView, _ expression: String, message: String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
        let result = try await view.evaluateJavaScript(expression)
        XCTAssertEqual(result as? Bool, true, message.isEmpty ? expression : message, file: file, line: line)
    }

    private func fixture() -> AnalysisResult {
        var sessions: [UsageSession] = []
        for index in 0..<61 {
            let group = index % 23
            let project = group == 0 ? "Same name <img src=x onerror='window.injected=true'>" : "Same name"
            let model = (index % 2 == 0 || group == 22) ? "gpt-6-astra" : "unknown-model"
            let effort = index % 3 == 0 ? "hoch" : "mittel"
            let task = "Task \(index) " + String(repeating: "long-text-", count: 20)
            let session = UsageSession(dateKey: "2026-09-28", started: Date(timeIntervalSince1970: Double(index)), ended: Date(timeIntervalSince1970: Double(index + 1)),
                                       project: project, workingDirectory: "/test/Group \(group)", task: task,
                                       model: model, effort: effort, modelEffortHistory: "",
                                       inputTokens: 1_000, cachedInputTokens: 500, uncachedInputTokens: 500, outputTokens: 100, reasoningTokens: 50, totalTokens: 1_100,
                                       estimatedCredits: nil, sessionID: "\(index)", logFile: "", malformedLines: 0)
            sessions.append(session)
        }
        // Reuse production aggregation, including grouping by path rather than display name.
        let base = AnalysisResult(sessions: sessions, projects: [], daily: [], modelEffort: [], scannedFileCount: 61, generatedAt: Date())
        let result = SessionAnalyzer().filtered(base, since: nil)
        let daily = (0..<100).map { index in
            var totals = UsageTotals()
            totals.estimatedCredits = Double(index + 1)
            return DailySummary(date: "2026-09-28", models: "gpt-6-astra", efforts: "hoch", totals: totals)
        }
        return AnalysisResult(sessions: result.sessions, projects: result.projects, daily: daily, modelEffort: result.modelEffort, scannedFileCount: 61, generatedAt: Date())
    }
}
