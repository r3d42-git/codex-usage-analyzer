import Foundation

struct PricingUpdater: Sendable {
    typealias Fetch = @Sendable (URL) async throws -> Data
    var fetch: Fetch = Self.download

    /// All three sources must validate before the caller saves or applies the result.
    func update(_ previous: PricingCatalog, now: Date = Date()) async throws -> PricingCatalog {
        async let credits = fetch(PricingCatalog.creditSource)
        async let api = fetch(PricingCatalog.apiSource)
        async let exchange = fetch(PricingCatalog.exchangeSource)
        let documents = try await (credits, api, exchange)
        return try Self.parse(credits: documents.0, api: documents.1, exchange: documents.2, previous: previous, now: now)
    }

    static func parse(credits: Data, api: Data, exchange: Data, previous: PricingCatalog, now: Date) throws -> PricingCatalog {
        let fresh = try parseCredits(credits, now: now)
        guard let anchor = fresh[PricingCatalog.anchorModel] else { throw PricingError.invalid("OpenAI Codex") }
        let apiRates = try parseAPI(api)
        let ratios = [apiRates[0] / anchor.input, apiRates[1] / anchor.cached, apiRates[2] / anchor.output]
        guard ratios.allSatisfy({ $0.isFinite && $0 > 0 && abs($0 - ratios[0]) < ratios[0] * 0.0001 }) else {
            throw PricingError.invalid("API-Vergleich (abweichende Token-Verhältnisse)")
        }
        let fx = try parseExchange(exchange, now: now)
        guard fx.date >= previous.exchangeDate else { throw PricingError.invalid("EZB (älterer Kurs)") }
        var rates = previous.rates.mapValues { rate in var retained = rate; retained.retained = true; return retained }
        rates.merge(fresh) { _, new in new }
        let result = PricingCatalog(checkedAt: now, isBundled: false, rates: rates,
                                    usdPerCredit: ratios[0], usdPerEUR: fx.rate, exchangeDate: fx.date)
        try result.validate()
        return result
    }

    static func parseCredits(_ data: Data, now: Date) throws -> [String: TokenRate] {
        let document = String(decoding: data, as: UTF8.self)
        let tables = captures("<table\\b[^>]*>(.*?)</table>", in: document).filter {
            captures("<th\\b[^>]*>(.*?)</th>", in: $0).map(clean) ==
                ["Credits per 1M tokens", "Input Tokens", "Cached input tokens", "Output Tokens"]
        }
        guard tables.count == 1, let body = captures("<tbody\\b[^>]*>(.*?)</tbody>", in: tables[0]).first else {
            throw PricingError.invalid("OpenAI Codex (Tabellenformat)")
        }
        var rates: [String: TokenRate] = [:]
        for row in captures("<tr\\b[^>]*>(.*?)</tr>", in: body) {
            let cells = captures("<td\\b[^>]*>(.*?)</td>", in: row).map(clean)
            guard let name = cells.first else { throw PricingError.invalid("OpenAI Codex (leere Zeile)") }
            // These rows do not provide a single, directly usable text-model rate.
            if name.hasPrefix("Daybreak ") || name.hasPrefix("GPT-Image-") || cells.contains(where: { $0.lowercased() == "research preview" }) { continue }
            let model = name.lowercased().replacingOccurrences(of: " ", with: "-")
            guard cells.count == 4, model.range(of: "^gpt-[a-z0-9]+(?:[.-][a-z0-9]+)*$", options: .regularExpression) != nil,
                  rates[model] == nil else { throw PricingError.invalid("OpenAI Codex (Modellzeile)") }
            let values = try cells.dropFirst().map { cell -> Double in
                guard cell.hasSuffix(" credits") else { throw PricingError.invalid("OpenAI Codex (Einheit)") }
                return try number(String(cell.dropLast(8)), source: "OpenAI Codex")
            }
            let rate = TokenRate(input: values[0], cached: values[1], output: values[2], verifiedAt: now)
            guard rate.isValid else { throw PricingError.invalid("OpenAI Codex (Tokenraten)") }
            rates[model] = rate
        }
        guard !rates.isEmpty else { throw PricingError.invalid("OpenAI Codex") }
        return rates
    }

    static func parseAPI(_ data: Data) throws -> [Double] {
        let document = String(decoding: data, as: UTF8.self)
        guard let section = captures("### Text tokens\\s+(.*?)(?:\\n##|\\z)", in: document).first else {
            throw PricingError.invalid("OpenAI API (Textpreise)")
        }
        return try ["Input", "Cached input", "Output"].map { metric in
            let matches = captures("(?m)^\\| " + metric + " \\| \\$([^|]+) \\| 1M tokens \\|\\s*$", in: section)
            guard matches.count == 1 else { throw PricingError.invalid("OpenAI API (\(metric))") }
            return try number(matches[0].trimmingCharacters(in: .whitespacesAndNewlines), source: "OpenAI API")
        }
    }

    static func parseExchange(_ data: Data, now: Date) throws -> (rate: Double, date: String) {
        let delegate = ExchangeParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.dates.count == 1, delegate.rates.count == 1,
              let date = delegate.dates.first, let day = PricingCatalog.exchangeDay(date),
              day <= now, now.timeIntervalSince(day) < 10 * 86400,
              let raw = delegate.rates.first else { throw PricingError.invalid("EZB (Kurs oder Datum)") }
        return (try number(raw, source: "EZB"), date)
    }

    private static func number(_ raw: String, source: String) throws -> Double {
        guard raw.range(of: "^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let value = Double(raw.replacingOccurrences(of: ",", with: "")), value.isFinite, value > 0 else {
            throw PricingError.invalid(source)
        }
        return value
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func download(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        let session = URLSession(configuration: configuration, delegate: SourceRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == url.host,
              response.expectedContentLength <= 2_000_000 else { throw PricingError.invalid(url.host ?? "Quelle") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { throw PricingError.invalid("Quelldatei zu groß") }
            data.append(byte)
        }
        return data
    }
}

private final class ExchangeParser: NSObject, XMLParserDelegate {
    var dates: [String] = []
    var rates: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        guard elementName == "Cube" else { return }
        if let date = attributes["time"] { dates.append(date) }
        if attributes["currency"] == "USD", let rate = attributes["rate"] { rates.append(rate) }
    }
}

private final class SourceRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == task.originalRequest?.url?.host ? request : nil)
    }
}
