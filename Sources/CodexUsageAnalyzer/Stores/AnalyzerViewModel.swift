import AppKit
import Combine
import Foundation

@MainActor
final class AnalyzerViewModel: ObservableObject {
    @Published private(set) var sourceDirectory: URL?
    @Published private(set) var report: GeneratedReport?
    @Published private(set) var result: AnalysisResult?
    @Published private(set) var pricing = PricingStore.local.load()
    @Published private(set) var isUpdatingPricing = false
    @Published private(set) var pricingStatus = "Aktualisiert Credit-Raten, API-Vergleich und Euro-Kurs gemeinsam."
    @Published private(set) var isAnalyzing = false
    @Published private(set) var progressText = ""
    @Published private(set) var statusText = "Wähle einen Codex-Sitzungsordner aus."
    @Published var usesSince = false {
        didSet {
            defaults.set(usesSince, forKey: "usesActivitySince")
            applyActivityFilter()
        }
    }
    @Published var sinceDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date() {
        didSet {
            defaults.set(sinceDate, forKey: "activitySinceDate")
            applyActivityFilter()
        }
    }
    @Published var alertMessage: String?

    private let accessStore = SessionAccessStore()
    private let defaults: UserDefaults
    private var allSessionsResult: AnalysisResult?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        usesSince = defaults.bool(forKey: "usesActivitySince")
        if let savedDate = defaults.object(forKey: "activitySinceDate") as? Date { sinceDate = savedDate }
        sourceDirectory = accessStore.savedDirectory
        if let sourceDirectory {
            statusText = "Bereit: \(sourceDirectory.path)"
        }
    }

    var sourceLabel: String { sourceDirectory?.path ?? "Kein Sitzungsordner ausgewählt" }

    func selectSourceDirectory() {
        guard !isAnalyzing, !isUpdatingPricing else { return }
        guard let url = accessStore.chooseDirectory() else { return }
        sourceDirectory = url
        allSessionsResult = nil
        result = nil
        report = nil
        statusText = "Bereit: \(url.path)"
    }

    func refresh() {
        guard !isAnalyzing, !isUpdatingPricing else { return }
        let access: ScopedDirectoryAccess
        do {
            access = try accessStore.acquireDirectory()
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        let source = access.url
        let cache = SessionAnalysisCache.local
        let pricing = self.pricing
        isAnalyzing = true
        progressText = "Sitzungslogs werden gesucht …"
        statusText = "Auswertung läuft …"

        let progressStream = AsyncStream<ScanProgress>.makeStream()
        let progressTask = Task { [weak self] in
            for await update in progressStream.stream {
                guard let self, self.isAnalyzing else { continue }
                self.progressText = "\(update.completed) von \(update.total) Logdateien geprüft …"
            }
        }

        Task { [weak self] in
            defer {
                access.stop()
                progressStream.continuation.finish()
                progressTask.cancel()
            }
            do {
                let analysis = try await Task.detached(priority: .userInitiated) {
                    try SessionAnalyzer(cache: cache, pricing: pricing).analyze(root: source) { completed, total in
                        progressStream.continuation.yield(ScanProgress(completed: completed, total: total))
                    }
                }.value
                guard let self else { return }
                allSessionsResult = analysis
                isAnalyzing = false
                progressText = ""
                applyActivityFilter()
            } catch {
                guard let self else { return }
                isAnalyzing = false
                progressText = ""
                statusText = "Auswertung fehlgeschlagen."
                alertMessage = error.localizedDescription
            }
        }
    }

    private func applyActivityFilter() {
        guard !isAnalyzing, let allSessionsResult else { return }
        let filtered = SessionAnalyzer(pricing: pricing).filtered(allSessionsResult, since: usesSince ? sinceDate : nil)
        result = filtered
        report = ReportExporter.makeReport(from: filtered)
        statusText = "\(filtered.sessions.count) Sessions · \(filtered.readFileCount) Logs eingelesen · \(filtered.reusedFileCount) aus Cache"
        if filtered.cacheWriteFailed { statusText += " · Cache konnte nicht gespeichert werden" }
    }

    func refreshPricing() {
        guard !isUpdatingPricing, !isAnalyzing else { return }
        isUpdatingPricing = true
        pricingStatus = "OpenAI-Raten, API-Preise und EZB-Kurs werden geprüft …"
        let previous = pricing
        Task {
            defer { isUpdatingPricing = false }
            do {
                let updated = try await PricingUpdater().update(previous)
                try PricingStore.local.save(updated)
                pricing = updated
                applyActivityFilter()
                pricingStatus = "Aktualisiert: \(updated.rates.count) Modellraten, davon \(updated.retainedModels.count) beibehaltene Altraten."
                if allSessionsResult != nil { pricingStatus += " Die Auswertung wurde ohne erneutes Einlesen neu berechnet." }
            } catch {
                pricingStatus = "Aktualisierung fehlgeschlagen. Der bisherige Stand bleibt erhalten. \(error.localizedDescription)"
            }
        }
    }

    func exportReport() {
        guard let report else {
            alertMessage = "Aktualisiere die Auswertung, bevor du einen Bericht exportierst."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Bericht exportieren"
        panel.message = "Wähle den Ordner, in dem ein neuer Berichtordner angelegt werden soll."
        panel.prompt = "Hier exportieren"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let exportDirectory = destination.appendingPathComponent("Codex-Usage-Report-\(formatter.string(from: Date()))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: false)
            for (name, data) in report.files {
                try data.write(to: exportDirectory.appendingPathComponent(name), options: .atomic)
            }
            statusText = "Exportiert nach \(exportDirectory.path)"
            NSWorkspace.shared.activateFileViewerSelecting([exportDirectory])
        } catch {
            alertMessage = "Der Export ist fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

private struct ScanProgress: Sendable {
    let completed: Int
    let total: Int
}
