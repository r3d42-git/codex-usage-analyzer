# Codex Usage Analyzer

A native macOS app for reviewing local Codex usage logs. It reads `rollout-*.jsonl` files from a folder you explicitly select, calculates token and estimated Codex-credit summaries, and renders the familiar interactive HTML report directly in the app.

## Deutsch

Die App wertet lokale Codex-Sitzungslogs aus, ohne Daten ins Netz zu senden. Beim ersten Start wählst du in der App `~/.codex/sessions`; danach genügt **Aktualisieren**. Der bisherige HTML-Bericht erscheint direkt im Fenster, und **Exportieren** legt HTML sowie vier CSV-Dateien in einem neuen, datierten Ordner ab.

**Sessions mit Aktivität ab** wählt Sessions anhand ihrer letzten protokollierten Aktivität aus. Auch früher begonnene, später fortgesetzte Sessions werden berücksichtigt. Es zählen jeweils sämtliche kumulierten Tokens der Session, einschließlich der Tokens vor dem Stichtag. Der Filter ist keine Messung des ausschließlich seit diesem Datum angefallenen Verbrauchs. Datum und Aktivierung werden für den nächsten Start gespeichert.

Beim ersten **Aktualisieren** liest die App alle Logs und baut einen lokalen Cache auf. Danach prüft sie Dateimetadaten und liest nur neue oder veränderte Logs erneut ein. Unveränderte Auswertungen werden auch nach einem Neustart wiederverwendet. Ein Datumswechsel nach der Auswertung filtert das Ergebnis sofort ohne erneuten Logzugriff. Neue Aktivität wird über **Aktualisieren** übernommen; die Statuszeile unterscheidet eingelesene Logs und Cachetreffer.

## Raten und Creditwert aktualisieren

**Raten & Creditwert** öffnet eine kurze Tabelle für 1, 100 und 1.000 Credits in US-Dollar und Euro. Sie zeigt ausdrücklich einen **API-Vergleichswert als Orientierung**, keinen Credit-Kaufpreis. Der Dollarwert wird aus den Standard-API- und Credit-Raten von GPT-6 Astra abgeleitet; Input, Cache und Output müssen dasselbe Verhältnis ergeben. Euro wird mit dem datierten EZB-Referenzkurs umgerechnet. Tarifpreise, Rabatte und Steuern sind nicht abgebildet. Die Tabelle ist auch im HTML-Export enthalten.

**Raten von OpenAI aktualisieren** lädt die [offizielle Credit-Tabelle](https://learn.chatgpt.com/docs/pricing.md), die [API-Preise](https://developers.openai.com/api/docs/models/gpt-6-astra.md) und den [EZB-Tageskurs](https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml). Erst wenn alle Quellen erfolgreich geprüft und gespeichert wurden, wird der Stand übernommen. Die aktuelle Auswertung wird ohne erneutes Einlesen der Logs neu berechnet. Der Preisstand bleibt nach einem Neustart erhalten; offline steht zunächst der mitgelieferte JSON-Stand, später der letzte erfolgreiche Abruf zur Verfügung.

Neue eindeutig benannte GPT-Textmodelle werden aus der Tabelle übernommen. Nicht mehr veröffentlichte Raten bleiben mit ihrem ursprünglichen Prüfdatum als **Altraten** sichtbar. Preview-, Image- und Daybreak-Zeilen werden nicht ungesichert einem Textmodell zugeordnet. Unbekannte Modelle bleiben ohne Schätzung. Geänderte Quellformate können weiterhin eine Anpassung des Parsers erfordern; fehlgeschlagene Aktualisierungen überschreiben keine gültigen Daten. Die Python-Referenz nutzt weiterhin ihren statischen Ratenstand.

## Privacy

- Session analysis stays local: no log uploads, analytics, telemetry, or account login. Only the explicit **Raten von OpenAI aktualisieren** action downloads public pricing documents from OpenAI and the ECB reference exchange rate. No network request runs at startup.
- The app reads only the selected directory and remembers access through a macOS security-scoped bookmark.
- The native app keeps disposable summaries in its sandbox's `Library/Caches/com.c5vcpq5gsr.codexusageanalyzer/SessionAnalysis` directory, separately per selected source. These include token counts, model names, project paths, and the short task text shown in the report, but no complete log contents. Corrupt or incompatible caches are rebuilt; cache write failures leave the current analysis usable.
- Exports can contain project paths and task text. Treat exported HTML and CSV files as private data.

## English

The app analyzes local Codex session logs without sending data over the network. At first launch select `~/.codex/sessions`, then use **Refresh**. The familiar report appears directly in the app; **Export** writes HTML and four CSV files into a new timestamped folder.

## Requirements and development

### Preisstand / Pricing

Standard-Credits je 1 Million Tokens, geprüft am **12.09.2026** anhand der [offiziellen OpenAI Codex Rate Card](https://learn.chatgpt.com/docs/pricing#token-rates):

| Modell | Input | Cached Input | Output |
| --- | ---: | ---: | ---: |
| GPT-6 Astra | 250 | 25 | 1.250 |
| GPT-5.6 Sol | 100 | 10 | 500 |
| GPT-5.6 Terra | 50 | 5 | 300 |
| GPT-5.6 Luna | 5 | 0,5 | 30 |
| GPT-5.5 | 125 | 12,5 | 750 |
| GPT-5.4 | 62,5 | 6,25 | 375 |
| GPT-5.4 mini | 18,75 | 1,875 | 113 |

Sol ist gegenüber dem bisherigen Stand beim Input/Cache um 20 % und beim Output um ein Drittel günstiger; Terra um 20 %, Luna um 80 %. Sols aktueller Tarif ist laut Quelle ein Angebot mindestens bis 21.11.2026.

Die Verbrauchsanzeige und die CSV-Spalte `estimated_credits` enthalten **Credits, keine US-Dollar**. Alle Sessions werden beim Aktualisieren mit dem aktuell geladenen Preisstand neu geschätzt. Der mitgelieferte Stand liegt in `Sources/CodexUsageAnalyzer/Resources/pricing-default.json`; erfolgreiche Abrufe liegen im App-Sandboxordner `Library/Application Support/CodexUsageAnalyzer/pricing.json`. Das ist keine historische Abrechnung; Fast-Modus, Langkontext- und Cache-Schreibaufschläge werden nicht berücksichtigt. Bei Modellwechseln innerhalb einer Session verwendet die bestehende Schätzung das zuletzt erkannte Modell für den höchsten kumulierten Tokenstand.

Für GPT-5.3-Codex und GPT-5.2 bleiben die Altraten vom 23.07.2026 erhalten (43,75 / 4,375 / 350); diese stehen nicht mehr in der aktuellen Codex-Karte. Für `codex-auto-review` wurde keine offizielle Rate gefunden: Tokens bleiben sichtbar, Credits unbekannt. Unbekannte Varianten werden nicht über Teilnamen einer anderen Rate zugeordnet; datierte Snapshots bekannter Modelle werden unterstützt.

### Build and tests

Apple Silicon Mac running macOS 14 or later, with Xcode 26.6 or newer.

```bash
swift test
python3 -m unittest discover -s Tests -p 'test_*.py'
./script/build_and_run.sh
```

The debug app is written to `dist/Codex Usage Analyzer.app`. Choose `~/.codex/sessions` at first launch, then click **Aktualisieren**. The original Python script remains in this repository as a compatibility reference during the Swift migration.

Caching and immediate activity filtering are features of the native app; the Python reference still performs a full scan. The cache checks file identity, size, modification time and metadata change time, and only saves summaries of files that remained unchanged during parsing. Deleted files drop out on refresh. Prices and local calendar dates are recalculated from cached sessions so a rate or time-zone change does not freeze old results.

## Release

The first public release is [v1.0.0](https://github.com/r3d42-git/codex-usage-analyzer/releases/tag/v1.0.0). It provides the notarized Apple-Silicon DMG and its SHA-256 checksum.

`script/release.sh VERSION` requires the local environment variables `DEVELOPMENT_TEAM` and `SIGNING_IDENTITY`. The existing local Keychain profile defaults to `codex-usage-analyzer.notary` (override with `NOTARY_PROFILE`); no credentials are stored in the repository. The tag workflow expects these GitHub secrets: `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `APPLE_DEVELOPMENT_TEAM`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER`.

The release script requires a clean `main` and matching Xcode version. It notarizes and staples the app before packaging, then signs, notarizes, staples, and verifies `Codex-Usage-Analyzer-VERSION-mac-arm64.dmg` including its enclosed app. Existing release directories are preserved. `script/publish_release.sh --dry-run VERSION` checks the commit, local artifact, checksum and free tag before publication. `script/publish_release.sh VERSION` downloads the published asset again and verifies it before reporting success.

## License

MIT. See [LICENSE](LICENSE).
