import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AnalyzerViewModel()
    @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRawValue) ?? .system }
        nonmutating set { appearanceRawValue = newValue.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            Group {
                if let report = model.report {
                    ReportWebView(html: report.html, appearance: appearance)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                } else {
                    ContentUnavailableView(
                        "Noch keine Auswertung",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Wähle den Codex-Sitzungsordner und klicke auf Aktualisieren.")
                    )
                }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .frame(minWidth: 920, minHeight: 620)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: model.exportReport) {
                    Label("Exportieren", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.report == nil || model.isAnalyzing)

                Button(action: model.refresh) {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.sourceDirectory == nil || model.isAnalyzing)
            }
        }
        .alert("Codex Usage Analyzer", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button("Sitzungsordner auswählen …", action: model.selectSourceDirectory)
                Text(model.sourceLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                appearancePicker
            }
            HStack(spacing: 12) {
                Toggle("Nur ab", isOn: $model.usesSince)
                    .toggleStyle(.checkbox)
                DatePicker("", selection: $model.sinceDate, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!model.usesSince)
                Spacer()
                if model.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.progressText)
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(.bar)
    }

    private var appearancePicker: some View {
        Picker("Darstellung", selection: Binding(get: { appearance }, set: { appearance = $0 })) {
            ForEach(AppAppearance.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 205)
        .accessibilityLabel("Darstellung")
    }
}
