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

## Release-Vorbereitung v1.1.1: GPL-3.0-or-later

- Nutzerauftrag: neuer Release mit GPL-3.0-or-later; anschließend öffentliche Release-Seite und Tag `v1.1.0` löschen. Der historische MIT-Quellstand bleibt in Git-Geschichte und vorhandenen Klonen rechtlich unverändert, wird aber nicht weiter als GitHub-Release angeboten.
- `LICENSE` ist der unveränderte offizielle GNU-Text der GPL Version 3 vom 29.06.2007. README und Release Notes bezeichnen den Wechsel eindeutig als vorwärtsgerichtet ab v1.1.1.
- Die DMG enthält `LICENSE.txt`. `release.sh` verlangt vor dem Build den GPL-Text; `verify_release.sh` verlangt nach dem Mount dieselbe Datei und vergleicht sie bytegenau mit dem Quellstand. Damit kann kein Release ohne sichtbare GPL-Lizenz im ausgelieferten Container erstellt werden.
- Version 1.1.1, Build 3, arm64. Die Preislogik bleibt unverändert; der Hinweis, dass Astra für den Nutzer in Codex derzeit nicht auswählbar ist, ist kein Änderungsauftrag.

## Zurückgezogen: v1.1.0 (12.09.2026)

- Die öffentliche Release-Seite, Assets und der lokale/entfernte Git-Tag `v1.1.0` wurden auf ausdrücklichen Nutzerauftrag nach Veröffentlichung von v1.1.1 gelöscht. Die frühere DMG wird nicht mehr angeboten.
- Der frühere Quellcommit `75e06db947d7feaffb45eb6efda1243bf9fdd29b` bleibt Teil der öffentlichen Git-Geschichte. Seine damals veröffentlichte MIT-Lizenz ist nicht rückwirkend widerrufbar.
- Apple: App-ZIP `ebc9629f-c741-4080-a046-ea2221efd3f8` und finale DMG `78ad8684-36af-44a1-95cb-5ac8eeb6d25c` jeweils **Accepted**. App vor dem Verpacken und DMG separat gestapelt. Lokale JSON-Belege unter `.release/1.1.0/`.
- Identität: `com.c5vcpq5gsr.codexusageanalyzer`, arm64, Developer ID Application: Philipp John Hild (G6JH37W285), Hardened Runtime und Timestamp. Lokaler finaler Container und frischer GitHub-Download bestanden `codesign`, `hdiutil verify`, App-/DMG-`stapler validate` und Gatekeeper (`source=Notarized Developer ID`). GitHub-Asset-Digest, lokale Prüfsumme und Download sind identisch.
- Lokale Release-Gates: 12 Swift-Tests sowie Python-Preisfälle erfolgreich. Publisher-Trockenlauf, Versionsabwehr und sauberer Quellstand geprüft.
- GitHub CI zum Release-Commit: [34719024748](https://github.com/r3d42-git/codex-usage-analyzer/actions/runs/34719024748), Swift-Tests und Xcode-Build erfolgreich.
- GitHub Release-Workflow [34719025587](https://github.com/r3d42-git/codex-usage-analyzer/actions/runs/34719025587): Vorprüfung erfolgreich, cloudseitiges Notarisierungsjob mangels konfigurierter CI-Secrets wie vorgesehen übersprungen. Veröffentlichung erfolgte vollständig lokal über das vorhandene projektspezifische Profil.
- Verifikationsgrenze: Die Tests und Download-Prüfungen erfolgten auf diesem Mac. Installation/Start auf einem separaten sauberen Mac bleibt ungeprüft. Die installierte App unter `/Applications` wurde nicht ersetzt.

## Veröffentlicht: v1.1.1 (12.09.2026, GPL-3.0-or-later)

- Release: https://github.com/r3d42-git/codex-usage-analyzer/releases/tag/v1.1.1
- Unveränderlicher Tag `v1.1.1` auf Release-Commit `3c17eb488322aa4ae14ea220efbf4c155ff24d31` (Version 1.1.1 / Build 3). Diese Abschlussdokumentation folgt separat.
- DMG: [Codex-Usage-Analyzer-1.1.1-mac-arm64.dmg](https://github.com/r3d42-git/codex-usage-analyzer/releases/download/v1.1.1/Codex-Usage-Analyzer-1.1.1-mac-arm64.dmg), 1.272.894 Bytes, SHA-256 `fbadf1458d90d0d8dc0e1ce3d87288f6a7ca194eb719d8c2b030edb9be27702a`. Öffentliche `.dmg.sha256` und GitHub-Asset-Digest stimmen mit dem frischen Download überein.
- Apple: App-ZIP `e2926c0e-64cc-4b49-bf81-a3be9d7cb2a7` und finale DMG `3f32f328-a344-4264-8656-1d85fa725565` jeweils **Accepted**. App vor dem Verpacken und DMG separat gestapelt.
- DMG und enthaltener App: arm64, Bundle-ID `com.c5vcpq5gsr.codexusageanalyzer`, Developer ID Application: Philipp John Hild (G6JH37W285), Hardened Runtime und Timestamp. Lokaler finaler Container und frischer GitHub-Download bestanden `codesign`, `hdiutil verify`, App-/DMG-`stapler validate`, Gatekeeper (`source=Notarized Developer ID`) sowie die bytegenaue GPL-`LICENSE.txt`-Prüfung.
- Release-Gates: 12 Swift-Tests, Python-Preisfälle, Lizenz-Prüfungen und Publisher-Trockenlauf erfolgreich. Ein anfänglich fehlendes `ROOT_DIR` im neuen Lizenz-Verifier wurde vor der Veröffentlichung erkannt, korrigiert und am finalen Artefakt sowie ungültigem Pfad geprüft. Die erste unvollständige lokale Release-Ausführung liegt als `.release/1.1.1-preflight-failed/` vor; sie wurde nie veröffentlicht.
- Verifikationsgrenze: Kein separater sauberer Mac getestet; die installierte App unter `/Applications` wurde nicht ersetzt.

## Veröffentlichung

- Vorgesehenes Ziel: `r3d42-git/codex-usage-analyzer`.
- Öffentliches Repository: `https://github.com/r3d42-git/codex-usage-analyzer`.
- v1.0.0: `Codex-Usage-Analyzer-1.0.0-mac-arm64.dmg`, SHA-256 `512bb0a15c3314e503da3732811519dc9b4531ed5df85ed5292a64e1928d05c8`.
- Der DMG wurde lokal mit Developer ID, Hardened Runtime und Timestamp signiert, von Apple akzeptiert (Submission `890076da-6b69-47f5-b246-45de8f590195`), gestapelt und nach dem GitHub-Download erneut über `codesign`, `hdiutil`, `stapler` und Gatekeeper geprüft (`source=Notarized Developer ID`).
- CI für den initialen Quellstand lief erfolgreich in GitHub Actions (Run `30299046100`). Der tagbasierte Release-Workflow aktiviert die cloudseitige Notarisierung erst, sobald die in der README benannten GitHub Secrets gesetzt sind; v1.0.0 wurde bewusst über das lokale Keychain-Profil erzeugt und danach hochgeladen.

## Berichtsbedienung (28.09.2026, v1.2.0)

- Anlass: feste Berichtsbreite, lange Gesamtdarstellung und wechselndes Scrollziel in der zunächst höhenbegrenzten Projekttabelle. Die Zwischenlösung mit innerem vertikalem Scrollbereich wurde vollständig ersetzt.
- Bericht nutzt die Fensterbreite und bietet feststehende Bereichsnavigation: Übersicht, Projekte, Sessions, Modelle & Aufwand. Pro Ansicht scrollt nur das Dokument. Übersicht zeigt Kennzahlen und Tagesverlauf unmittelbar; Modellkarten haben einen eigenen Bereich.
- Projekte: Suche nach Name/Pfad/Modell, Sortierung nach Tokens/Credits/Sessionzahl/Name, 20 Ergebnisse pro Seite mit Bedienung oben und unten. Projektname öffnet Sessions für den exakten Arbeitsordner, auch bei gleichnamigen Projekten. Tabellenkopf bleibt beim Scrollen unter der Navigation sichtbar; unter 1.100 px werden Projektzeilen als beschriftete Datenblöcke dargestellt, ohne horizontale Scrollfläche.
- Sessions: kombinierte Suche und Projekt-/Modell-/Aufwandfilter, Zurücksetzen, Trefferzahl und 25 Ergebnisse pro Seite. Technische Aufgabentexte mit führendem `<` sind aufklappbar; Daten und Exporte bleiben vollständig enthalten. Bereich, Filter, Seite und Scrollposition werden bei HTML-Neuladung durch Aktualisieren oder Darstellungswechsel wiederhergestellt; verschwundene Filteroptionen fallen auf „Alle“ zurück.
- Tagesbalken stehen auf gemeinsamer Grundlinie. Beschriftungsdichte passt sich an die Breite an. Dunkle Darstellung verwendet hellere Projektlinks; der Leerzustand hält die nativen Bedienelemente am oberen Fensterrand.
- Prüfung: 15 Swift-Tests erfolgreich, davon drei echte WKWebView-Interaktionstests für Navigation, Filterkombinationen, Pagination, leere Ergebnisse, HTML-Escaping, identische Projektnamen mit verschiedenen Pfaden, native Zustandswiederherstellung und Layout bei 600/920/1.440/1.920 px. Keine verschachtelten vertikalen Scrollflächen oder horizontale Dokumentüberläufe in diesen Layoutprüfungen. Lokaler Xcode-Build und Ad-hoc-Signatur erfolgreich; Bedienwege zusätzlich in der Test-App mit vorhandenen Logs geprüft.
- Veröffentlicht als Version 1.2.0 / Build 4; vollständige Belege unten. Die installierte App unter `/Applications` wurde nicht ersetzt.


## Veröffentlicht: v1.2.0 (28.09.2026)

- Release: https://github.com/r3d42-git/codex-usage-analyzer/releases/tag/v1.2.0
- Unveränderlicher Tag `v1.2.0` auf Release-Commit `564fea2528ed30f2882e49087be5e6de48a1e572`, Version 1.2.0 / Build 4. Dieser Dokumentationsabschluss folgt separat auf `main`.
- DMG: [Codex-Usage-Analyzer-1.2.0-mac-arm64.dmg](https://github.com/r3d42-git/codex-usage-analyzer/releases/download/v1.2.0/Codex-Usage-Analyzer-1.2.0-mac-arm64.dmg), 1.269.868 Bytes. SHA-256: `6e330c1f5c0c14acb38aaafa97b2e4b18f8e8a8d0deac429c04122d448b07a93`.
- Apple: App-ZIP `5217314d-f5b8-4144-a215-3f8833f9ed04` und finale DMG `591b03b1-1d35-442e-92a4-4e743cad2d3a` jeweils **Accepted**. App vor dem Verpacken und DMG separat gestapelt; Belege unter `.release/1.2.0/`.
- Identität: arm64, Bundle-ID `com.c5vcpq5gsr.codexusageanalyzer`, Developer ID Application: Philipp John Hild (G6JH37W285), Hardened Runtime und Timestamp. Unverändert GPL-3.0-or-later; `LICENSE.txt` in der DMG bytegenau geprüft.
- Lokale Release-Prüfungen: 15 Swift-Tests in Release-Konfiguration, Python-Preisfälle, Xcode-Archivierung und Veröffentlichungstrockenlauf erfolgreich.
- GitHub-CI des exakten Release-Commits: [36482992333](https://github.com/r3d42-git/codex-usage-analyzer/actions/runs/36482992333), Tests und Xcode-Build erfolgreich. Tag-Workflow [36483297257](https://github.com/r3d42-git/codex-usage-analyzer/actions/runs/36483297257): Vorprüfung erfolgreich, Cloud-Notarisierung mangels konfigurierter CI-Secrets wie vorgesehen übersprungen. Veröffentlichung erfolgte lokal über `script/publish_release.sh`.
- Öffentlichen Download frisch nach `/private/tmp/codex-usage-analyzer-release.jgFSjv/` geladen: lokale SHA-256, GitHub-Asset-Digest und Download identisch. Veröffentlichte Prüfsummendatei zusätzlich heruntergeladen und bytegenau verglichen. Download-DMG und ihre enthaltene App bestanden `codesign`, `hdiutil verify`, beide `stapler validate`-Prüfungen und Gatekeeper (`source=Notarized Developer ID`).
- Verifikationsgrenze: Kein separater sauberer Mac getestet. Die installierte App unter `/Applications` wurde nicht ersetzt; lokale Test-App bleibt unter `dist/`.

## Abgeschlossener G2-Release 1.2.1 — 2026-10-02

- Release [1.2.1](https://github.com/r3d42-git/codex-usage-analyzer/releases/tag/v1.2.1) ist öffentlich veröffentlicht. Annotierter Tag `v1.2.1` bleibt auf Quellcommit `4931e082482975e90d1d3893a5a08803fa63b5c7`; diese Abschlussbelege folgen separat. App-Funktionen bleiben gegenüber dem Vorgänger unverändert.
- 15 Swift-Tests und Python-Preisprüfung erfolgreich; exakte Quellcommit-CI [Run 36972715447](https://github.com/r3d42-git/codex-usage-analyzer/actions/runs/36972715447) erfolgreich.
- Apple-Submission(s) `9fdfc4e7-2233-4f22-9679-8c3b3db8d919 / 46b2f525-6df0-4c32-ace4-2fcb6975bb19`: Accepted; App-Ticket angeheftet. Bei DMGs wurden App und Container getrennt notarisiert und gestapelt.
- Native lokale und frische GitHub-Downloadprüfung: strikte Signatur, Hardened Runtime, sicherer Zeitstempel, Architektur/Bundle-Metadaten, Lizenzmaterial, Stapling und Gatekeeper erfolgreich. Zusätzliche öffentliche Leaf-Prüfung bestätigt exakt G2 SHA-1 `D548540E7FE1BD9B3C4518CC02D8786E1BFEB885`.
- Asset `Codex-Usage-Analyzer-1.2.1-mac-arm64.dmg`; SHA-256 `b9e9520cce851929524067704942da3982c83c87aaa938bb6a3bb8362f2eab33` stimmt lokal, mit Download und veröffentlichter Prüfsumme überein. Build `5`, Bundle-ID `com.c5vcpq5gsr.codexusageanalyzer`.
- Keine neue manuelle UI-Abnahme aus diesen Distributionsprüfungen abgeleitet. Bestehende Laufzeit-/UI-Nachweise gelten weiterhin nur für ihren dokumentierten Umfang.
