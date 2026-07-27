# Codex Usage Analyzer

A native macOS app for reviewing local Codex usage logs. It reads `rollout-*.jsonl` files from a folder you explicitly select, calculates token and estimated API-cost summaries, and renders the familiar interactive HTML report directly in the app.

## Deutsch

Die App wertet lokale Codex-Sitzungslogs aus, ohne Daten ins Netz zu senden. Beim ersten Start wählst du in der App `~/.codex/sessions`; danach genügt **Aktualisieren**. Der bisherige HTML-Bericht erscheint direkt im Fenster, und **Exportieren** legt HTML sowie vier CSV-Dateien in einem neuen, datierten Ordner ab.

## Privacy

- Completely local: no network calls, analytics, telemetry, or account login. The WebKit sandbox permission is present solely because macOS runs the local HTML renderer in a separate helper process.
- The app reads only the selected directory and remembers access through a macOS security-scoped bookmark.
- Exports can contain project paths and task text. Treat exported HTML and CSV files as private data.

## English

The app analyzes local Codex session logs without sending data over the network. At first launch select `~/.codex/sessions`, then use **Refresh**. The familiar report appears directly in the app; **Export** writes HTML and four CSV files into a new timestamped folder.

## Requirements and development

Apple Silicon Mac running macOS 14 or later, with Xcode 26.6 or newer.

```bash
swift test
./script/build_and_run.sh
```

The debug app is written to `dist/Codex Usage Analyzer.app`. Choose `~/.codex/sessions` at first launch, then click **Aktualisieren**. The original Python script remains in this repository as a compatibility reference during the Swift migration.

## Release

The first public release is [v1.0.0](https://github.com/c5vcpq5gsr-alt/codex-usage-analyzer/releases/tag/v1.0.0). It provides the notarized Apple-Silicon DMG and its SHA-256 checksum.

`script/release.sh VERSION` requires the local environment variables `DEVELOPMENT_TEAM`, `SIGNING_IDENTITY`, and `NOTARY_PROFILE`; no credentials are stored in the repository. The tag workflow expects these GitHub secrets: `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `APPLE_DEVELOPMENT_TEAM`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER`.

The release script signs, notarizes, staples, and verifies `Codex-Usage-Analyzer-VERSION-mac-arm64.dmg`. `script/publish_release.sh VERSION` downloads the published asset again and verifies it before reporting success.

## License

MIT. See [LICENSE](LICENSE).
