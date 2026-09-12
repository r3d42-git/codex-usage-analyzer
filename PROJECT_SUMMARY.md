# Codex Usage Analyzer – Projektstand

## Aktueller Stand

- Native SwiftUI-App, Bundle-Identifier `com.c5vcpq5gsr.codexusageanalyzer`.
- Ziel: Apple Silicon, macOS 14 oder neuer.
- Die lokale Analyse ersetzt die Python-Laufzeit; die Python-Datei bleibt bis zum funktionalen Vergleich als Referenz erhalten.
- Der Bericht wird als lokales HTML in `WKWebView` dargestellt. HTML und vier CSV-Dateien lassen sich bewusst in einen neuen Exportordner schreiben.
- Die Darstellung lässt sich zwischen System, Hell und Dunkel umschalten; der lokale HTML-Bericht folgt derselben Auswahl.
- Das App-Icon zeigt zwei ausgewertete Log-Zeilen mit Lupe in der Berichtspalette.
- Zugriff auf Codex-Logs erfolgt ausschließlich über einen per Dateidialog gewählten, sicherheitsbeschränkten Ordnerzugriff.

## Prüfpfad

- `swift test` für anonymisierte JSONL-Fixtures und Exporte.
- `./script/build_and_run.sh --verify` erzeugt und startet die ad-hoc signierte Test-App in `dist/`.
- `./script/release.sh VERSION` ist erst mit lokal verfügbarem Developer-ID-Zertifikat und Notarytool-Profil ausführbar.

## Ratenaktualisierung 12.09.2026

- Swift und Python verwenden die [offizielle Codex Rate Card](https://learn.chatgpt.com/docs/pricing#token-rates), geprüft am 12.09.2026: Astra ergänzt (250 / 25 / 1250 Credits pro Mio. Input / Cache / Output), Sol auf 100 / 10 / 500, Terra auf 50 / 5 / 300 und Luna auf 5 / 0,5 / 30 gesenkt. GPT-5.5 und GPT-5.4 einschließlich mini unverändert.
- `astra`, `6-astra` und der offizielle Sol-Alias `gpt-5.6` werden erkannt. Datierte Snapshots werden exakt ihrem Basismodell zugeordnet; unsicheres Teilstring-Matching wurde entfernt.
- Bericht korrigiert die bisherige Dollar-Beschriftung zu Credits und nennt Preisstand und Schätzgrenzen. CSV-Schema bleibt kompatibel (`estimated_credits`). Alle Sessions werden zu den hinterlegten Standardraten neu geschätzt, ohne historische Preisstaffelung, Fast-/Langkontext-/Cache-Schreibaufschläge oder Aufteilung bei Modellwechseln.
- `codex-auto-review` bleibt ohne veröffentlichte Rate unbekannt; keine geschätzte Nullrate. GPT-5.3-Codex und GPT-5.2 behalten ausdrücklich die Altraten vom 23.07.2026, da sie nicht mehr in der aktuellen Codex-Karte stehen.
- Gemeinsame 25 Preisfälle für Swift und Python prüfen Raten, Aliase, Snapshots, Cache-Abzug und unbekannte Varianten; Swift prüft zusätzlich Aggregation, Warnung und Exporte.
- Verifiziert: `swift test` (3 Tests, erfolgreich), Python-Unittest (25 Preisfälle, erfolgreich), `./script/build_and_run.sh --verify` (Build, Ad-hoc-Signatur und Start erfolgreich). UI mit dem bereits gewählten Sitzungsordner geprüft: Astra-Credits sichtbar, Warnung enthält nur noch `codex-auto-review`, Beschriftung und Layout kontrolliert. Swift benötigte Zugriff auf die lokalen Compiler-Caches außerhalb der Ausführungssandbox.
- Lokale Test-App wird über `./script/build_and_run.sh --verify` in `dist/` gebaut. Veröffentlichung und installierte App unter `/Applications` werden durch diesen Arbeitsschritt nicht aktualisiert.

## Session-Cache und Aktivitätsfilter (12.09.2026)

- Neuer `SessionAnalysisCache` im lokalen App-Cache, pro Quellordner getrennt, mit Schema-Version und atomarem Schreiben. Enthält Session-Zusammenfassungen einschließlich kurzem Aufgabentext, keine vollständigen Logs. Ordner/Datei werden mit 0700/0600 angelegt.
- `SessionAnalyzer` prüft Dateimetadaten (Identität, Größe, mtime, ctime) und liest nur neue/geänderte Dateien vollständig. Während des Lesens veränderte oder nicht lesbare Dateien werden nicht dauerhaft gecacht. Auch Logs ohne Token-Daten können unverändert wiederverwendet werden; gelöschte Einträge fallen beim nächsten Scan heraus. Beschädigter/veralteter Cache führt zum Neuaufbau, Schreibfehler blockieren die Analyse nicht.
- Preisberechnung und lokaler Datumsschlüssel werden bei Cachetreffern neu berechnet. Bei Änderungen an Parsing/Modellnormalisierung `SessionAnalysisCache.schemaVersion` erhöhen.
- Filter heißt **Sessions mit Aktivität ab**. Grundlage bleibt `session.ended` (letzter protokollierter Zeitstempel), einschließlich des gewählten lokalen Kalendertags. Ganze kumulierte Session-Tokens zählen, auch vor dem Stichtag. Ein alter Dateiname schließt eine fortgesetzte Session nicht aus.
- `AnalyzerViewModel` hält die ungefilterte Auswertung im Speicher; Datumswechsel filtern sofort ohne Logzugriff. Datum und Aktivierung werden gespeichert. Quellwechsel verwirft die aktuelle Ansicht. Der Bericht/HTML-Export nennt Filter und Semantik; ein leerer Zeitraum ist ein reguläres leeres Ergebnis.
- Status unterscheidet eingelesene Logs und Cachetreffer. Beim ersten Lauf ohne Cache werden alle Logs eingelesen, bei weiteren Läufen und nach App-Neustart nur Änderungen. Die Python-Referenz bleibt beim vollständigen Scan.
- Verifikation: 7 Swift-Tests erfolgreich, einschließlich persistenter Wiederverwendung, fortgesetzter alter Session, vollständiger Tokenstände, geändertem Inhalt bei gleicher Größe/mtime, neuen/gelöschten Logs, leerem Zeitraum, Cache-Reparatur, Quelltrennung und aktueller Preisberechnung. Xcode-Build, Ad-hoc-Signatur und Start erfolgreich. UI-Praxistest: erster Lauf 525 Logs gelesen; nächstes Aktualisieren 1 gelesen / 524 aus Cache. Datumswechsel 07.09. → 12.09. filterte unmittelbar von 23 auf 2 Sessions ohne erneuten Scan; anschließend 07.09. wiederhergestellt.
- Nach abschließendem App-Neustart: aktivierter Filter und 07.09.2026 wiederhergestellt; Aktualisieren las nur 2 zwischenzeitlich geänderte Logs, 523 kamen aus dem persistenten Cache. Darstellung einschließlich vollständigem Filterdatum visuell geprüft. Lokale Test-App in `dist/` gestartet, keine Veröffentlichung/Installation nach `/Applications`.

## Dynamische Raten und Creditwert (12.09.2026)

- Toolbar **Raten & Creditwert** mit kurzer 1/100/1.000-Credit-Tabelle in USD/EUR sowie ausklappbaren Modellraten und Prüfdatum. Derselbe Vergleich ist im HTML-Bericht/Export enthalten; CSV bleibt in Credits.
- Nutzerentscheidung: automatisch aktualisierte **API-Vergleichswerte als Orientierung**, ausdrücklich kein Credit-Kaufpreis. Vergleich basiert auf Standard-Input/Cache/Output von GPT-6 Astra: USD-API-Raten dividiert durch Credit-Raten müssen übereinstimmen. EUR = USD / EZB-USD-pro-EUR. Aktuell 0,04 USD/Credit, 1 EUR = 1,1592 USD (EZB 11.09.2026), somit 1.000 Credits ≈ 40 USD / 34,51 EUR. Tarifpreise, Rabatte und Steuern sind nicht abgebildet.
- `PricingUpdater` lädt nur auf Knopfdruck drei öffentliche HTTPS-Dokumente: `learn.chatgpt.com/docs/pricing.md`, `developers.openai.com/api/docs/models/gpt-6-astra.md`, `ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml`. Ephemere URLSession ohne Cookies/Anmeldedaten/Cache, Zeit-/Größenlimits, nur HTTPS-Weiterleitungen auf denselben Host. Kein Logupload, kein Hintergrundabruf beim Start.
- Alle drei Dokumente müssen strukturell und numerisch validieren; erst nach atomarem Speichern wird der neue Stand angewendet. Fehler behalten den vorherigen Stand und erscheinen im Dialog. EZB-Kurs darf weder älter als der vorherige Kurs noch älter als zehn Tage oder zukünftig sein. Strukturänderungen der Quellen können weiterhin eine Parseranpassung erfordern.
- `PricingCatalog` ersetzt die Swift-Ratenkonstante; mitgeliefertes JSON ist in SwiftPM und Xcode als Resource eingebunden. Letzter Abruf liegt im App-Sandboxordner `Library/Application Support/CodexUsageAnalyzer/pricing.json`, mit Schema-Version und Prüfung beim Laden; beschädigte Daten fallen auf den gekennzeichneten mitgelieferten Stand zurück. Neue eindeutig benannte GPT-Textmodelle werden dynamisch übernommen. Preview/Image/Daybreak-Zeilen bleiben unzugeordnet; nicht mehr veröffentlichte Raten behalten ursprüngliches Prüfdatum und Altraten-Markierung. Bekannte Kurzaliase bleiben im Sessionparser.
- Ratenwechsel bewerten die im Speicher vorhandenen Sessions einschließlich aller Aggregate neu; Datumsauswahl bleibt erhalten, kein erneutes Einlesen. `AnalysisResult.pricing` bindet Bericht und Export an denselben Preisstand. Die Python-Datei bleibt statische Referenz.
- Verifikation: 12 Swift-Tests erfolgreich (offizielle Format-Fixtures, neues Modell ohne Release, Neuberechnung ohne vorhandene Logs, Zahl-/Einheiten-/Verhältnisfehler, veraltete/ungültige FX-Kurse, Speicherfehler/Korruption, Offlinefehler und bestehende Cache-/Exporttests). Xcode-Build, Ad-hoc-Signatur und App-Start erfolgreich.
- Echter UI-Abruf erfolgreich: 10 Modellraten, 2 Altraten. Lesestatus vor/nach Ratenwechsel unverändert (3 Logs / 523 Cachetreffer, 24 gefilterte Sessions). Kompakter und ausgeklappter Dialog visuell kontrolliert; nach Beenden/Neustart derselbe Abrufstand 12.09.2026, 22:49 und dieselben Geldwerte ohne neuen Abruf wiederhergestellt. Keine Veröffentlichung/Installation nach `/Applications`.

## Release-Vorbereitung v1.1.0

- Version 1.1.0, Build 2, Release-Branch `main`, arm64-DMG. Quellumfang: aktuelle Raten, dynamischer Abruf/Creditwert, Session-Cache/Aktivitätsfilter, Tests, Dokumentation und zugehörige Release-Prüfungen.
- Lokales projektspezifisches Notarytool-Profil: **`codex-usage-analyzer.notary`** (Punkt vor `notary`), bereits bei v1.0.0 benutzt und am 12.09.2026 außerhalb der Ausführungssandbox erfolgreich geprüft. `codex-usage-analyzer-notary` ist nur der Name des getrennten CI-Profils. Die irrtümlich geprüften Namen ohne Punkt waren nicht vorhanden; kein Keychain-Eintrag wurde verändert. Keine Abhängigkeit vom GitHub-Kontonamen.
- Release-Skript ergänzt: sauberer `main`, Versionsgleichheit, frühe Profilprüfung, keine Löschung vorhandener Release-Verzeichnisse, belegter Quellcommit, separate App- und DMG-Einreichungen mit Accepted-Prüfung und gespeicherten Submission-JSONs. Eingepackte App muss bereits ein gültiges Staple-Ticket tragen.
- Verifier kontrolliert nun zusätzlich App-Ticket, Developer ID/Team G6JH37W285, Hardened Runtime/Timestamp, Bundle-ID, Version und arm64. Publisher prüft lokalen Stand, Quellcommit, lokale Prüfsumme, unveröffentlichten Tag, bietet `--dry-run`, publiziert vom expliziten Repository und vergleicht frischen Download auch mit GitHubs Asset-Digest. Tag bleibt unveränderlich; Abschlussbelege folgen als Dokumentationscommit.

## Veröffentlicht: v1.1.0 (12.09.2026)

- Release: https://github.com/r3d42-git/codex-usage-analyzer/releases/tag/v1.1.0
- Unveränderlicher Tag `v1.1.0` auf Release-Commit `75e06db947d7feaffb45eb6efda1243bf9fdd29b` (Version 1.1.0 / Build 2); diese Abschlussdokumentation folgt separat.
- DMG: [Codex-Usage-Analyzer-1.1.0-mac-arm64.dmg](https://github.com/r3d42-git/codex-usage-analyzer/releases/download/v1.1.0/Codex-Usage-Analyzer-1.1.0-mac-arm64.dmg), 1.257.428 Bytes, SHA-256 `bf48d5566a452ce8d7db45557a1dc09f88e32e97a706a74215674068512b6b7c`. Öffentliche `.dmg.sha256` ist hochgeladen und gegen den frischen Download geprüft.
- Apple: App-ZIP `ebc9629f-c741-4080-a046-ea2221efd3f8` und finale DMG `78ad8684-36af-44a1-95cb-5ac8eeb6d25c` jeweils **Accepted**. App vor dem Verpacken und DMG separat gestapelt. Lokale JSON-Belege unter `.release/1.1.0/`.
- Identität: `com.c5vcpq5gsr.codexusageanalyzer`, arm64, Developer ID Application: Philipp John Hild (G6JH37W285), Hardened Runtime und Timestamp. Lokaler finaler Container und frischer GitHub-Download bestanden `codesign`, `hdiutil verify`, App-/DMG-`stapler validate` und Gatekeeper (`source=Notarized Developer ID`). GitHub-Asset-Digest, lokale Prüfsumme und Download sind identisch.
- Lokale Release-Gates: 12 Swift-Tests sowie Python-Preisfälle erfolgreich. Publisher-Trockenlauf, Versionsabwehr und sauberer Quellstand geprüft.
- GitHub CI zum Release-Commit: [34719024748](https://github.com/r3d42-git/codex-usage-analyzer/actions/runs/34719024748), Swift-Tests und Xcode-Build erfolgreich.
- GitHub Release-Workflow [34719025587](https://github.com/r3d42-git/codex-usage-analyzer/actions/runs/34719025587): Vorprüfung erfolgreich, cloudseitiges Notarisierungsjob mangels konfigurierter CI-Secrets wie vorgesehen übersprungen. Veröffentlichung erfolgte vollständig lokal über das vorhandene projektspezifische Profil.
- Verifikationsgrenze: Die Tests und Download-Prüfungen erfolgten auf diesem Mac. Installation/Start auf einem separaten sauberen Mac bleibt ungeprüft. Die installierte App unter `/Applications` wurde nicht ersetzt.

## Veröffentlichung

- Vorgesehenes Ziel: `r3d42-git/codex-usage-analyzer`.
- Öffentliches Repository: `https://github.com/r3d42-git/codex-usage-analyzer`.
- v1.0.0: `Codex-Usage-Analyzer-1.0.0-mac-arm64.dmg`, SHA-256 `512bb0a15c3314e503da3732811519dc9b4531ed5df85ed5292a64e1928d05c8`.
- Der DMG wurde lokal mit Developer ID, Hardened Runtime und Timestamp signiert, von Apple akzeptiert (Submission `890076da-6b69-47f5-b246-45de8f590195`), gestapelt und nach dem GitHub-Download erneut über `codesign`, `hdiutil`, `stapler` und Gatekeeper geprüft (`source=Notarized Developer ID`).
- CI für den initialen Quellstand lief erfolgreich in GitHub Actions (Run `30299046100`). Der tagbasierte Release-Workflow aktiviert die cloudseitige Notarisierung erst, sobald die in der README benannten GitHub Secrets gesetzt sind; v1.0.0 wurde bewusst über das lokale Keychain-Profil erzeugt und danach hochgeladen.
