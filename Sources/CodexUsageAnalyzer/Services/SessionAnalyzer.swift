import Foundation

struct SessionAnalyzer: Sendable {
    typealias Progress = @Sendable (_ completed: Int, _ total: Int) -> Void
    var cache: SessionAnalysisCache?

    var pricing: PricingCatalog = .bundled

    func analyze(root: URL, since: Date? = nil, progress: Progress? = nil) throws -> AnalysisResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AnalyzerError.sourceUnavailable(root)
        }

        let properties: Set<URLResourceKey> = [.isRegularFileKey]
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(properties), options: [.skipsHiddenFiles])?.allObjects as? [URL] ?? [])
            .filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
            .sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw AnalyzerError.noLogFiles(root) }

        let previous = cache?.load(root: root) ?? [:]
        var updated: [String: SessionAnalysisCache.Entry] = [:]
        var sessions: [UsageSession] = []
        var readCount = 0
        var reusedCount = 0
        for (index, file) in files.enumerated() {
            let before = SessionAnalysisCache.Fingerprint.read(file)
            var session: UsageSession?
            if let before, let entry = previous[file.path], entry.fingerprint == before {
                session = entry.session
                updated[file.path] = entry
                reusedCount += 1
            } else {
                readCount += 1
                do {
                    session = try analyzeFile(file)
                    // Do not persist a partial snapshot of a log that changed while being read.
                    if let before, before == SessionAnalysisCache.Fingerprint.read(file) {
                        updated[file.path] = .init(fingerprint: before, session: session)
                    }
                } catch {
                    // A temporarily unreadable file must be retried on the next refresh.
                }
            }
            if var session {
                session.dateKey = dateKey(session.ended)
                session.estimatedCredits = estimatedCredits(model: session.model, input: session.inputTokens,
                                                             cached: session.cachedInputTokens, output: session.outputTokens)
                sessions.append(session)
            }
            progress?(index + 1, files.count)
        }
        var cacheWriteFailed = false
        do { try cache?.save(updated, root: root) } catch { cacheWriteFailed = true }
        guard !sessions.isEmpty else { throw AnalyzerError.noUsableSessions }

        let result = AnalysisResult(
            sessions: sessions,
            projects: projectSummaries(sessions),
            daily: dailySummaries(sessions),
            modelEffort: modelEffortSummaries(sessions),
            scannedFileCount: files.count,
            generatedAt: Date(),
            readFileCount: readCount,
            reusedFileCount: reusedCount,
            cacheWriteFailed: cacheWriteFailed
        )
        return filtered(result, since: since)
    }

    /// Filters whole sessions by last activity, retaining all cumulative tokens.
    func filtered(_ result: AnalysisResult, since: Date?) -> AnalysisResult {
        let cutoff = since.map { Calendar.current.startOfDay(for: $0) }
        let sessions = result.sessions.filter { session in cutoff.map { session.ended >= $0 } ?? true }.map { original in
            var session = original
            session.estimatedCredits = estimatedCredits(model: session.model, input: session.inputTokens,
                                                         cached: session.cachedInputTokens, output: session.outputTokens)
            return session
        }
        return AnalysisResult(sessions: sessions, projects: projectSummaries(sessions), daily: dailySummaries(sessions),
                              modelEffort: modelEffortSummaries(sessions), scannedFileCount: result.scannedFileCount,
                              generatedAt: result.generatedAt, readFileCount: result.readFileCount,
                              reusedFileCount: result.reusedFileCount, cacheWriteFailed: result.cacheWriteFailed,
                              activitySince: cutoff, pricing: pricing)
    }

    private func analyzeFile(_ url: URL) throws -> UsageSession? {
        let fallback = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let contents = try String(contentsOf: url, encoding: .utf8)

        var firstDate: Date?
        var lastDate: Date?
        var workingDirectory = ""
        var model = ""
        var effort = ""
        var modelEffortHistory: [String] = []
        var firstPrompt = ""
        var sessionID = ""
        var sawUsage = false
        var maximum = TokenUsage()
        var malformedLines = 0

        for line in contents.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                malformedLines += 1
                continue
            }
            let eventDate = parseDate(nested(object, paths: [["timestamp"], ["created_at"], ["time"], ["payload", "timestamp"]])) ?? fallback
            firstDate = min(firstDate ?? eventDate, eventDate)
            lastDate = max(lastDate ?? eventDate, eventDate)

            let payload = dictionary(object["payload"]) ?? object
            if workingDirectory.isEmpty {
                workingDirectory = string(nested(payload, paths: [["cwd"], ["turn_context", "cwd"], ["session", "cwd"], ["metadata", "cwd"], ["context", "cwd"]]))
            }
            let detectedModel = string(nested(payload, paths: [["model"], ["turn_context", "model"], ["session", "model"], ["metadata", "model"], ["model_name"], ["config", "model"], ["settings", "model"], ["request", "model"]]))
            let detectedEffort = string(nested(payload, paths: [["effort"], ["reasoning_effort"], ["reasoning", "effort"], ["turn_context", "effort"], ["turn_context", "reasoning_effort"], ["session", "effort"], ["session", "reasoning_effort"], ["metadata", "effort"], ["metadata", "reasoning_effort"], ["config", "effort"], ["config", "reasoning_effort"], ["settings", "effort"], ["settings", "reasoning_effort"], ["request", "reasoning_effort"]]))
            if !detectedModel.isEmpty { model = detectedModel }
            if !detectedEffort.isEmpty { effort = detectedEffort }
            if !detectedModel.isEmpty || !detectedEffort.isEmpty {
                let combination = "\(normalizeModel(detectedModel.isEmpty ? model : detectedModel)) / \(normalizeEffort(detectedEffort.isEmpty ? effort : detectedEffort))"
                if !modelEffortHistory.contains(combination) { modelEffortHistory.append(combination) }
            }
            if sessionID.isEmpty {
                sessionID = string(nested(payload, paths: [["session_id"], ["thread_id"], ["id"], ["metadata", "session_id"]]))
            }
            if firstPrompt.isEmpty && isUserMessage(payload) {
                let content = nested(payload, paths: [["content"], ["message", "content"], ["item", "content"], ["text"], ["message"]])
                let text = extractText(content)
                if !text.isEmpty { firstPrompt = truncate(text) }
            }
            if let usage = tokenUsage(from: payload) {
                sawUsage = true
                maximum.mergeMaximum(usage)
            }
        }
        guard sawUsage else { return nil }

        let finalDate = lastDate ?? fallback
        let normalizedModel = normalizeModel(model)
        let normalizedEffort = normalizeEffort(effort)
        let input = maximum.input
        let cached = maximum.cached
        return UsageSession(
            dateKey: dateKey(finalDate),
            started: firstDate ?? finalDate,
            ended: finalDate,
            project: projectName(workingDirectory),
            workingDirectory: workingDirectory,
            task: firstPrompt.isEmpty ? "(Aufgabentext nicht erkannt)" : firstPrompt,
            model: normalizedModel,
            effort: normalizedEffort,
            modelEffortHistory: modelEffortHistory.isEmpty ? "\(normalizedModel) / \(normalizedEffort)" : modelEffortHistory.joined(separator: " → "),
            inputTokens: input,
            cachedInputTokens: cached,
            uncachedInputTokens: max(0, input - cached),
            outputTokens: maximum.output,
            reasoningTokens: maximum.reasoning,
            totalTokens: maximum.total,
            estimatedCredits: estimatedCredits(model: normalizedModel, input: input, cached: cached, output: maximum.output),
            sessionID: sessionID.isEmpty ? url.deletingPathExtension().lastPathComponent : sessionID,
            logFile: url.path,
            malformedLines: malformedLines
        )
    }

    private func projectSummaries(_ sessions: [UsageSession]) -> [ProjectSummary] {
        var groups: [String: (project: String, directory: String, totals: UsageTotals, models: Set<String>, efforts: Set<String>)] = [:]
        for session in sessions {
            let key = "\(session.project)\u{0}\(session.workingDirectory)"
            var group = groups[key] ?? (session.project, session.workingDirectory, UsageTotals(), [], [])
            group.totals.add(session)
            group.models.insert(session.model)
            group.efforts.insert(session.effort)
            groups[key] = group
        }
        return groups.values.map { ProjectSummary(project: $0.project, workingDirectory: $0.directory, models: $0.models.sorted().joined(separator: ", "), efforts: $0.efforts.sorted().joined(separator: ", "), totals: $0.totals) }
            .sorted { $0.totals.totalTokens > $1.totals.totalTokens }
    }

    private func dailySummaries(_ sessions: [UsageSession]) -> [DailySummary] {
        var groups: [String: (totals: UsageTotals, models: Set<String>, efforts: Set<String>)] = [:]
        for session in sessions {
            var group = groups[session.dateKey] ?? (UsageTotals(), [], [])
            group.totals.add(session)
            group.models.insert(session.model)
            group.efforts.insert(session.effort)
            groups[session.dateKey] = group
        }
        return groups.map { DailySummary(date: $0.key, models: $0.value.models.sorted().joined(separator: ", "), efforts: $0.value.efforts.sorted().joined(separator: ", "), totals: $0.value.totals) }
            .sorted { $0.totals.totalTokens > $1.totals.totalTokens }
    }

    private func modelEffortSummaries(_ sessions: [UsageSession]) -> [ModelEffortSummary] {
        var groups: [String: (model: String, effort: String, totals: UsageTotals)] = [:]
        for session in sessions {
            let key = "\(session.model)\u{0}\(session.effort)"
            var group = groups[key] ?? (session.model, session.effort, UsageTotals())
            group.totals.add(session)
            groups[key] = group
        }
        return groups.values.map { ModelEffortSummary(model: $0.model, effort: $0.effort, totals: $0.totals) }
            .sorted { $0.totals.totalTokens > $1.totals.totalTokens }
    }

    private func tokenUsage(from payload: [String: Any]) -> TokenUsage? {
        let type = string(payload["type"]).lowercased()
        if !["token_count", "turn.completed", "turn_completed"].contains(type), payload["usage"] == nil, dictionary(payload["info"]) == nil { return nil }
        guard let usage = dictionary(nested(payload, paths: [["info", "total_token_usage"], ["total_token_usage"], ["usage"], ["info", "usage"]])) else { return nil }
        let input = number(usage, keys: ["input_tokens", "prompt_tokens"])
        let cached = number(usage, keys: ["cached_input_tokens", "cached_tokens", "input_cached_tokens"])
        let output = number(usage, keys: ["output_tokens", "completion_tokens"])
        let reasoning = number(usage, keys: ["reasoning_output_tokens", "reasoning_tokens"])
        let total = number(usage, keys: ["total_tokens"])
        let computedTotal = total == 0 ? input + output : total
        guard input != 0 || cached != 0 || output != 0 || reasoning != 0 || computedTotal != 0 else { return nil }
        return TokenUsage(input: input, cached: cached, output: output, reasoning: reasoning, total: computedTotal)
    }

    private func isUserMessage(_ payload: [String: Any]) -> Bool {
        let role = string(nested(payload, paths: [["role"], ["message", "role"], ["item", "role"]])).lowercased()
        let type = string(nested(payload, paths: [["type"], ["message", "type"], ["item", "type"]])).lowercased()
        return role == "user" || ["user_message", "user_input"].contains(type)
    }

    private func estimatedCredits(model: String, input: Int, cached: Int, output: Int) -> Double? {
        // Only strip dated snapshots. Substring matching can price unknown variants
        // (e.g. gpt-5.4-pro) as the base model, or a mini snapshot as the full model.
        let base = model.replacingOccurrences(of: "-[0-9]{4}-[0-9]{2}-[0-9]{2}$", with: "", options: .regularExpression)
        let rate = pricing.rates[base]
        guard let rate else { return nil }
        return (Double(max(0, input - cached)) * rate.input + Double(cached) * rate.cached + Double(output) * rate.output) / 1_000_000
    }

    private func normalizeModel(_ value: String) -> String {
        let raw = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
        let aliases = ["astra": "gpt-6-astra", "6-astra": "gpt-6-astra", "gpt-5.6": "gpt-5.6-sol", "sol": "gpt-5.6-sol", "terra": "gpt-5.6-terra", "luna": "gpt-5.6-luna", "5.6-sol": "gpt-5.6-sol", "5.6-terra": "gpt-5.6-terra", "5.6-luna": "gpt-5.6-luna"]
        return aliases[raw] ?? (raw.isEmpty ? "unbekannt" : raw)
    }

    private func normalizeEffort(_ value: String) -> String {
        let raw = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        let aliases = ["none": "kein", "minimal": "minimal", "low": "niedrig", "medium": "mittel", "high": "hoch", "xhigh": "sehr hoch", "extra-high": "sehr hoch", "very-high": "sehr hoch", "max": "sehr hoch"]
        return aliases[raw] ?? (raw.isEmpty ? "unbekannt" : raw)
    }

    private func nested(_ object: [String: Any], paths: [[String]]) -> Any? {
        for path in paths {
            var value: Any? = object
            for component in path {
                guard let dictionary = value.flatMap(dictionary), let next = dictionary[component] else { value = nil; break }
                value = next
            }
            if let value { return value }
        }
        return nil
    }

    private func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private func string(_ value: Any?) -> String { value as? String ?? "" }
    private func number(_ dictionary: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let value = dictionary[key] as? NSNumber { return value.intValue }
            if let value = dictionary[key] as? Int { return value }
            if let value = dictionary[key] as? Double { return Int(value) }
        }
        return 0
    }

    private func extractText(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let values = value as? [Any] { return values.map(extractText).filter { !$0.isEmpty }.joined(separator: " ") }
        if let dictionary = dictionary(value) {
            for key in ["text", "content", "input_text", "message"] where dictionary[key] != nil {
                return extractText(dictionary[key])
            }
        }
        return ""
    }

    private func truncate(_ value: String, limit: Int = 110) -> String {
        let normalized = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.count <= limit ? normalized : String(normalized.prefix(limit - 1)) + "…"
    }

    private func projectName(_ path: String) -> String {
        guard !path.isEmpty else { return "(kein Arbeitsordner)" }
        return URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private func dateKey(_ date: Date) -> String {
        let values = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }
}

private struct TokenUsage: Sendable {
    var input = 0
    var cached = 0
    var output = 0
    var reasoning = 0
    var total = 0

    init(input: Int = 0, cached: Int = 0, output: Int = 0, reasoning: Int = 0, total: Int = 0) {
        self.input = input
        self.cached = cached
        self.output = output
        self.reasoning = reasoning
        self.total = total
    }

    mutating func mergeMaximum(_ other: TokenUsage) {
        input = max(input, other.input)
        cached = max(cached, other.cached)
        output = max(output, other.output)
        reasoning = max(reasoning, other.reasoning)
        total = max(total, other.total)
    }
}
