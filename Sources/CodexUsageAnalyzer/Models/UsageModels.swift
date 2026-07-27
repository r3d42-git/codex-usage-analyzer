import Foundation

struct UsageSession: Identifiable, Hashable, Sendable {
    let dateKey: String
    let started: Date
    let ended: Date
    let project: String
    let workingDirectory: String
    let task: String
    let model: String
    let effort: String
    let modelEffortHistory: String
    let inputTokens: Int
    let cachedInputTokens: Int
    let uncachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let estimatedCredits: Double?
    let sessionID: String
    let logFile: String
    let malformedLines: Int

    var id: String { sessionID }
}

struct UsageTotals: Hashable, Sendable {
    var sessions = 0
    var inputTokens = 0
    var cachedInputTokens = 0
    var uncachedInputTokens = 0
    var outputTokens = 0
    var reasoningTokens = 0
    var totalTokens = 0
    var estimatedCredits = 0.0
    var creditsComplete = true

    mutating func add(_ session: UsageSession) {
        sessions += 1
        inputTokens += session.inputTokens
        cachedInputTokens += session.cachedInputTokens
        uncachedInputTokens += session.uncachedInputTokens
        outputTokens += session.outputTokens
        reasoningTokens += session.reasoningTokens
        totalTokens += session.totalTokens
        if let credits = session.estimatedCredits {
            estimatedCredits += credits
        } else {
            creditsComplete = false
        }
    }
}

struct ProjectSummary: Hashable, Sendable {
    let project: String
    let workingDirectory: String
    let models: String
    let efforts: String
    let totals: UsageTotals
}

struct DailySummary: Hashable, Sendable {
    let date: String
    let models: String
    let efforts: String
    let totals: UsageTotals
}

struct ModelEffortSummary: Hashable, Sendable {
    let model: String
    let effort: String
    let totals: UsageTotals
}

struct AnalysisResult: Hashable, Sendable {
    let sessions: [UsageSession]
    let projects: [ProjectSummary]
    let daily: [DailySummary]
    let modelEffort: [ModelEffortSummary]
    let scannedFileCount: Int
    let generatedAt: Date
}

enum AnalyzerError: LocalizedError, Sendable {
    case sourceUnavailable(URL)
    case noLogFiles(URL)
    case noUsableSessions

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable(let url):
            return "Der Sitzungsordner ist nicht erreichbar: \(url.path)"
        case .noLogFiles:
            return "Im gewählten Ordner wurden keine rollout-*.jsonl-Dateien gefunden."
        case .noUsableSessions:
            return "Die gefundenen Logdateien enthalten keine auswertbaren Token-Daten."
        }
    }
}
