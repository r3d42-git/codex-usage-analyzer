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

## Veröffentlichung

- Vorgesehenes Ziel: `c5vcpq5gsr-alt/codex-usage-analyzer`.
- Öffentliches Repository: `https://github.com/c5vcpq5gsr-alt/codex-usage-analyzer`.
- v1.0.0: `Codex-Usage-Analyzer-1.0.0-mac-arm64.dmg`, SHA-256 `512bb0a15c3314e503da3732811519dc9b4531ed5df85ed5292a64e1928d05c8`.
- Der DMG wurde lokal mit Developer ID, Hardened Runtime und Timestamp signiert, von Apple akzeptiert (Submission `890076da-6b69-47f5-b246-45de8f590195`), gestapelt und nach dem GitHub-Download erneut über `codesign`, `hdiutil`, `stapler` und Gatekeeper geprüft (`source=Notarized Developer ID`).
- CI für den initialen Quellstand lief erfolgreich in GitHub Actions (Run `30299046100`). Der tagbasierte Release-Workflow aktiviert die cloudseitige Notarisierung erst, sobald die in der README benannten GitHub Secrets gesetzt sind; v1.0.0 wurde bewusst über das lokale Keychain-Profil erzeugt und danach hochgeladen.
