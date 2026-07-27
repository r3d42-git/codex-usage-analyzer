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
- MIT-Lizenz; kein Remote und keine Veröffentlichung sind in diesem Arbeitsstand angelegt.
- Nach einer akzeptierten lokalen Bedienprüfung: GitHub-Repository verbinden, CI aktivieren, v1.0.0 taggen und das heruntergeladene DMG unabhängig verifizieren.
