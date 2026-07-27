import AppKit
import Combine
import Foundation

@MainActor
final class AnalyzerViewModel: ObservableObject {
    @Published private(set) var sourceDirectory: URL?
    @Published private(set) var report: GeneratedReport?
    @Published private(set) var result: AnalysisResult?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var progressText = ""
    @Published private(set) var statusText = "Wähle einen Codex-Sitzungsordner aus."
    @Published var usesSince = false
    @Published var sinceDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var alertMessage: String?

    private let accessStore = SessionAccessStore()

    init() {
        sourceDirectory = accessStore.savedDirectory
        if let sourceDirectory {
            statusText = "Bereit: \(sourceDirectory.path)"
        }
    }

    var sourceLabel: String { sourceDirectory?.path ?? "Kein Sitzungsordner ausgewählt" }

    func selectSourceDirectory() {
        guard let url = accessStore.chooseDirectory() else { return }
        sourceDirectory = url
        statusText = "Bereit: \(url.path)"
    }

    func refresh() {
        guard !isAnalyzing else { return }
        let access: ScopedDirectoryAccess
        do {
            access = try accessStore.acquireDirectory()
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        let source = access.url
        let cutoff = usesSince ? Calendar.current.startOfDay(for: sinceDate) : nil
        isAnalyzing = true
        progressText = "Sitzungslogs werden gesucht …"
        statusText = "Auswertung läuft …"

        let progressStream = AsyncStream<ScanProgress>.makeStream()
        let progressTask = Task { [weak self] in
            for await update in progressStream.stream {
                self?.progressText = "\(update.completed) von \(update.total) Logdateien gelesen …"
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
                    try SessionAnalyzer().analyze(root: source, since: cutoff) { completed, total in
                        progressStream.continuation.yield(ScanProgress(completed: completed, total: total))
                    }
                }.value
                guard let self else { return }
                result = analysis
                report = ReportExporter.makeReport(from: analysis)
                isAnalyzing = false
                progressText = ""
                statusText = "\(analysis.sessions.count) Sessions aus \(analysis.scannedFileCount) Logdateien ausgewertet."
            } catch {
                guard let self else { return }
                isAnalyzing = false
                progressText = ""
                statusText = "Auswertung fehlgeschlagen."
                alertMessage = error.localizedDescription
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
