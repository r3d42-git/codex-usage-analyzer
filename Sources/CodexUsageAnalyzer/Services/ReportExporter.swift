import Foundation

struct GeneratedReport: Sendable {
    let html: String
    let files: [String: Data]
}

enum ReportExporter {
    static func makeReport(from result: AnalysisResult) -> GeneratedReport {
        let html = ReportRenderer.render(result)
        return GeneratedReport(
            html: html,
            files: [
                "codex_usage_report.html": Data(html.utf8),
                "codex_usage_sessions.csv": csvData(sessionRows(result.sessions)),
                "codex_usage_projects.csv": csvData(projectRows(result.projects)),
                "codex_usage_daily.csv": csvData(dailyRows(result.daily)),
                "codex_usage_models_effort.csv": csvData(modelEffortRows(result.modelEffort))
            ]
        )
    }

    private static func sessionRows(_ sessions: [UsageSession]) -> [[String]] {
        let header = ["date", "started", "ended", "project", "cwd", "task", "model", "effort", "model_effort_history", "input_tokens", "cached_input_tokens", "uncached_input_tokens", "output_tokens", "reasoning_tokens", "total_tokens", "estimated_credits", "session_id", "log_file", "malformed_lines"]
        let iso = ISO8601DateFormatter()
        return [header] + sessions.map { session in
            [session.dateKey, iso.string(from: session.started), iso.string(from: session.ended), session.project, session.workingDirectory, session.task, session.model, session.effort, session.modelEffortHistory, "\(session.inputTokens)", "\(session.cachedInputTokens)", "\(session.uncachedInputTokens)", "\(session.outputTokens)", "\(session.reasoningTokens)", "\(session.totalTokens)", session.estimatedCredits.map { String($0) } ?? "", session.sessionID, session.logFile, "\(session.malformedLines)"]
        }
    }

    private static func projectRows(_ rows: [ProjectSummary]) -> [[String]] {
        let header = ["project", "cwd", "sessions", "estimated_credits", "credits_complete", "input_tokens", "cached_input_tokens", "uncached_input_tokens", "output_tokens", "reasoning_tokens", "total_tokens", "models", "efforts"]
        return [header] + rows.map { row in totalsCells(row.totals, prefix: [row.project, row.workingDirectory]) + [row.models, row.efforts] }
    }

    private static func dailyRows(_ rows: [DailySummary]) -> [[String]] {
        let header = ["date", "sessions", "estimated_credits", "credits_complete", "input_tokens", "cached_input_tokens", "uncached_input_tokens", "output_tokens", "reasoning_tokens", "total_tokens", "models", "efforts"]
        return [header] + rows.map { row in totalsCells(row.totals, prefix: [row.date]) + [row.models, row.efforts] }
    }

    private static func modelEffortRows(_ rows: [ModelEffortSummary]) -> [[String]] {
        let header = ["model", "effort", "sessions", "estimated_credits", "credits_complete", "input_tokens", "cached_input_tokens", "uncached_input_tokens", "output_tokens", "reasoning_tokens", "total_tokens", "models", "efforts"]
        return [header] + rows.map { row in totalsCells(row.totals, prefix: [row.model, row.effort]) + [row.model, row.effort] }
    }

    private static func totalsCells(_ totals: UsageTotals, prefix: [String]) -> [String] {
        prefix + ["\(totals.sessions)", String(totals.estimatedCredits), totals.creditsComplete ? "True" : "False", "\(totals.inputTokens)", "\(totals.cachedInputTokens)", "\(totals.uncachedInputTokens)", "\(totals.outputTokens)", "\(totals.reasoningTokens)", "\(totals.totalTokens)"]
    }

    private static func csvData(_ rows: [[String]]) -> Data {
        let text = "\u{FEFF}" + rows.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
        return Data(text.utf8)
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
