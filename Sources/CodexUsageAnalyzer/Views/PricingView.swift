import SwiftUI

struct PricingView: View {
    @ObservedObject var model: AnalyzerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Raten & Creditwert").font(.title2.bold())
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("API-Vergleichswert · Orientierung").font(.headline)
            Grid(alignment: .trailing, horizontalSpacing: 60, verticalSpacing: 10) {
                GridRow {
                    Text("Credits").bold()
                    Text("US-Dollar (≈)").bold()
                    Text("Euro (≈)").bold()
                }
                Divider()
                ForEach([1, 100, 1_000], id: \.self) { credits in
                    GridRow {
                        Text(UsageFormatting.integer(credits))
                        Text(money(Double(credits) * model.pricing.usdPerCredit, currency: "USD", digits: credits == 1 ? 4 : 2))
                        Text(money(Double(credits) * model.pricing.eurPerCredit, currency: "EUR", digits: credits == 1 ? 4 : 2))
                    }.monospacedDigit()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Text("Abgeleitet aus den Standard-API- und Credit-Raten von GPT-6 Astra. Kein Credit-Kaufpreis und keine Abrechnung: Tarifpreise, Rabatte und Steuern sind nicht abgebildet. Euro ist eine Umrechnung zum EZB-Referenzkurs.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(model.pricing.isBundled ? "Mitgelieferter Stand" : "Zuletzt abgerufen"): \(UsageFormatting.localDate(model.pricing.checkedAt, includeTime: !model.pricing.isBundled))")
                Text("EZB-Kurs vom \(model.pricing.exchangeDate): 1 € = \(money(model.pricing.usdPerEUR, currency: "USD", digits: 4))")
                HStack {
                    Link("OpenAI Credit-Raten", destination: URL(string: "https://learn.chatgpt.com/docs/pricing")!)
                    Text("·")
                    Link("API-Preise", destination: URL(string: "https://developers.openai.com/api/docs/models/gpt-6-astra")!)
                    Text("·")
                    Link("EZB", destination: PricingCatalog.exchangeSource)
                }
            }.font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Modellraten (Credits je 1 Mio. Tokens)") {
                ScrollView {
                    Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 7) {
                        GridRow {
                            Text("Modell / geprüft").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Input"); Text("Cache"); Text("Output")
                        }.bold()
                        ForEach(model.pricing.rates.keys.sorted(), id: \.self) { key in
                            if let rate = model.pricing.rates[key] {
                                GridRow {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(key)
                                        Text("\(rate.retained ? "Altrate · " : "")\(UsageFormatting.localDate(rate.verifiedAt, includeTime: false))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text(UsageFormatting.decimal(rate.input))
                                    Text(UsageFormatting.decimal(rate.cached, digits: 3))
                                    Text(UsageFormatting.decimal(rate.output))
                                }
                            }
                        }
                    }.font(.caption).padding(.top, 8)
                }.frame(maxHeight: 180)
            }
            Text("Altraten bleiben erhalten, wenn ein Modell nicht mehr veröffentlicht wird. Unbekannte Modelle bleiben ohne Schätzung.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Raten von OpenAI aktualisieren", action: model.refreshPricing)
                    .disabled(model.isUpdatingPricing || model.isAnalyzing)
                if model.isUpdatingPricing { ProgressView().controlSize(.small) }
            }
            Text(model.pricingStatus).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Lädt nur öffentliche Preise und Wechselkurse. Sitzungsdaten bleiben auf diesem Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 620)
    }

    private func money(_ value: Double, currency: String, digits: Int) -> String {
        value.formatted(.currency(code: currency).locale(Locale(identifier: "de_DE")).precision(.fractionLength(digits)))
    }
}
