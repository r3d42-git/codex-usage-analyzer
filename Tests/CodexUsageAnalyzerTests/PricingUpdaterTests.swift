import XCTest
@testable import CodexUsageAnalyzer

final class PricingUpdaterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_214_400) // 2026-09-12 UTC

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext)))
    }
    private func parsed(credits: Data? = nil, api: Data? = nil, exchange: Data? = nil) throws -> PricingCatalog {
        try PricingUpdater.parse(credits: credits ?? fixture("official-credit-rates", "html"),
                                 api: api ?? fixture("official-api-rates", "md"),
                                 exchange: exchange ?? fixture("official-exchange", "xml"), previous: .bundled, now: now)
    }

    func testOfficialSourceFormatsConversionAndRetainedRates() throws {
        let result = try parsed()
        XCTAssertFalse(result.isBundled)
        XCTAssertEqual(result.rates["gpt-6-astra"]?.output, 1250)
        XCTAssertEqual(result.rates["gpt-5.4-mini"]?.cached, 1.875)
        XCTAssertNotNil(result.rates["gpt-rosalind-research"])
        XCTAssertNil(result.rates["gpt-5.3-codex-spark"])
        XCTAssertNil(result.rates["gpt-image-2"])
        XCTAssertEqual(result.usdPerCredit, 0.04, accuracy: 0.0000001)
        XCTAssertEqual(result.eurPerCredit * 1_000, 40 / 1.1592, accuracy: 0.0000001)
        XCTAssertEqual(result.retainedModels, ["gpt-5.2", "gpt-5.3-codex"])
        XCTAssertEqual(result.rates["gpt-5.2"]?.verifiedAt, PricingCatalog.bundled.rates["gpt-5.2"]?.verifiedAt)
    }

    func testFutureModelAndChangedRateRepriceWithoutReadingLogs() throws {
        var html = String(decoding: try fixture("official-credit-rates", "html"), as: UTF8.self)
        html = html.replacingOccurrences(of: "</tbody>", with: "<tr><td>GPT-9 Future</td><td>2 credits</td><td>1 credits</td><td>8 credits</td></tr></tbody>")
        html = html.replacingOccurrences(of: ">100 credits<", with: ">200 credits<")
        let catalog = try parsed(credits: Data(html.utf8))
        XCTAssertEqual(catalog.rates["gpt-9-future"]?.input, 2)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = """
        {"timestamp":"2026-09-12T12:00:00Z","payload":{"model":"gpt-9-future","session_id":"new"}}
        {"timestamp":"2026-09-12T12:01:00Z","payload":{"type":"token_count","total_token_usage":{"input_tokens":1000000,"output_tokens":0,"total_tokens":1000000}}}
        """
        try log.write(to: root.appendingPathComponent("rollout-new.jsonl"), atomically: true, encoding: .utf8)
        let old = try SessionAnalyzer().analyze(root: root)
        try FileManager.default.removeItem(at: root)
        XCTAssertNil(old.sessions[0].estimatedCredits)
        let repriced = SessionAnalyzer(pricing: catalog).filtered(old, since: nil)
        XCTAssertEqual(repriced.sessions[0].estimatedCredits, 2)
        XCTAssertEqual(repriced.projects[0].totals.estimatedCredits, 2)
        XCTAssertEqual(repriced.pricing, catalog)
    }

    func testMalformedAmbiguousAndInconsistentSourcesAreRejected() throws {
        let credit = String(decoding: try fixture("official-credit-rates", "html"), as: UTF8.self)
        for bad in ["<html>Access denied</html>", credit + credit,
                    credit.replacingOccurrences(of: "1,250 credits", with: "1,25 credits"),
                    credit.replacingOccurrences(of: "Input Tokens", with: "Input Dollars"),
                    credit.replacingOccurrences(of: "25 credits", with: "-25 credits")] {
            XCTAssertThrowsError(try parsed(credits: Data(bad.utf8)))
        }
        let api = String(decoding: try fixture("official-api-rates", "md"), as: UTF8.self)
        XCTAssertThrowsError(try parsed(api: Data(api.replacingOccurrences(of: "$50", with: "$60").utf8)))
        XCTAssertThrowsError(try parsed(api: Data(api.replacingOccurrences(of: "1M tokens", with: "1K tokens").utf8)))
        let fx = String(decoding: try fixture("official-exchange", "xml"), as: UTF8.self)
        for bad in [fx.replacingOccurrences(of: "1.1592", with: "0"),
                    fx.replacingOccurrences(of: "2026-09-11", with: "2026-08-01"),
                    fx.replacingOccurrences(of: "2026-09-11", with: "2026-09-30"),
                    fx.replacingOccurrences(of: "USD", with: "GBP"),
                    fx.replacingOccurrences(of: "</Envelope>", with: "<Cube currency='USD' rate='2'/></Envelope>")] {
            XCTAssertThrowsError(try parsed(exchange: Data(bad.utf8)))
        }
    }

    func testPersistenceCorruptionAndFailedSaveKeepValidSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PricingStore(file: root.appendingPathComponent("pricing.json"))
        XCTAssertEqual(store.load(), .bundled)
        let valid = try parsed()
        try store.save(valid)
        XCTAssertEqual(store.load(), valid)
        var invalid = valid
        invalid.usdPerEUR = .nan
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(store.load(), valid)
        try Data("broken".utf8).write(to: store.file)
        XCTAssertEqual(store.load(), .bundled)
    }

    func testNetworkFailureDoesNotReplaceStoredRates() async throws {
        let previous = PricingCatalog.bundled
        let updater = PricingUpdater(fetch: { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await updater.update(previous)
            XCTFail("Offline update must fail")
        } catch {
            XCTAssertEqual(previous, .bundled)
        }
    }
}
