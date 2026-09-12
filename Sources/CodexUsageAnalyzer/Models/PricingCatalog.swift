import Foundation

struct TokenRate: Codable, Hashable, Sendable {
    let input: Double
    let cached: Double
    let output: Double
    let verifiedAt: Date
    var retained = false

    var isValid: Bool {
        [input, cached, output].allSatisfy { $0.isFinite && $0 > 0 && $0 < 1_000_000_000 } && cached <= input
    }
}

struct PricingCatalog: Codable, Hashable, Sendable {
    var version = 1
    var checkedAt: Date
    var isBundled: Bool
    var rates: [String: TokenRate]
    var usdPerCredit: Double
    var usdPerEUR: Double
    var exchangeDate: String

    static let creditSource = URL(string: "https://learn.chatgpt.com/docs/pricing.md")!
    static let apiSource = URL(string: "https://developers.openai.com/api/docs/models/gpt-6-astra.md")!
    static let exchangeSource = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    static let anchorModel = "gpt-6-astra"

    static let bundled: PricingCatalog = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        // This resource is checked by tests and packaged with both build systems.
        let url = bundle.url(forResource: "pricing-default", withExtension: "json")!
        return try! decode(Data(contentsOf: url))
    }()

    var dateLabel: String { UsageFormatting.localDate(checkedAt, includeTime: false) }
    var retainedModels: [String] { rates.keys.filter { rates[$0]?.retained == true }.sorted() }
    var eurPerCredit: Double { usdPerCredit / usdPerEUR }

    func validate() throws {
        guard version == 1, !rates.isEmpty, rates.count <= 500,
              rates.allSatisfy({ key, rate in
                  key.range(of: "^gpt-[a-z0-9]+(?:[.-][a-z0-9]+)*$", options: .regularExpression) != nil
                  && rate.isValid && rate.verifiedAt <= checkedAt
              }), rates[Self.anchorModel] != nil,
              checkedAt.timeIntervalSince1970.isFinite,
              usdPerCredit.isFinite, usdPerCredit > 0, usdPerCredit < 100,
              usdPerEUR.isFinite, usdPerEUR > 0.01, usdPerEUR < 100,
              Self.exchangeDay(exchangeDate) != nil else {
            throw PricingError.invalid("Gespeicherte Raten")
        }
    }

    static func exchangeDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        return value
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct PricingStore: Sendable {
    let file: URL
    static var local: Self {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(file: base.appendingPathComponent("CodexUsageAnalyzer/pricing.json"))
    }
    func load() -> PricingCatalog {
        (try? PricingCatalog.decode(Data(contentsOf: file))) ?? .bundled
    }
    func save(_ catalog: PricingCatalog) throws {
        let data = try catalog.encoded()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}

enum PricingError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let source): "\(source): Raten konnten nicht eindeutig geprüft werden. Der bisherige Stand bleibt erhalten."
        }
    }
}
