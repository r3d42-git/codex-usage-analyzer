import Foundation

enum ReportRenderer {
    static func render(_ result: AnalysisResult) -> String {
        let sessions = result.sessions
        let input = sessions.reduce(0) { $0 + $1.inputTokens }
        let cached = sessions.reduce(0) { $0 + $1.cachedInputTokens }
        let uncached = sessions.reduce(0) { $0 + $1.uncachedInputTokens }
        let output = sessions.reduce(0) { $0 + $1.outputTokens }
        let total = sessions.reduce(0) { $0 + $1.totalTokens }
        let knownCredits = sessions.compactMap(\.estimatedCredits).reduce(0, +)
        let cacheRatio = input == 0 ? 0 : Double(cached) / Double(input) * 100
        let unknownModels = Array(Set(sessions.filter { $0.estimatedCredits == nil }.map(\.model))).sorted()
        let warning = unknownModels.isEmpty ? "" : "<div class='notice'><span>!</span><div><strong>Kosten teilweise unbekannt</strong><p>Keine Rate hinterlegt für: \(escape(unknownModels.joined(separator: ", "))). Tokens werden dennoch vollständig angezeigt.</p></div></div>"

        let modelCards = result.modelEffort.map { row in
            let credits = row.totals.creditsComplete ? money(row.totals.estimatedCredits) : "–"
            return """
            <article class="model-card">
              <div class="model-head"><span class="model-dot"></span><strong>\(escape(row.model))</strong></div>
              <div class="model-effort">Aufwand: \(escape(row.effort))</div>
              <dl><div><dt>Sessions</dt><dd>\(UsageFormatting.integer(row.totals.sessions))</dd></div><div><dt>Input</dt><dd>\(UsageFormatting.compact(row.totals.inputTokens))</dd></div><div><dt>Cache</dt><dd>\(UsageFormatting.compact(row.totals.cachedInputTokens))</dd></div><div><dt>Output</dt><dd>\(UsageFormatting.compact(row.totals.outputTokens))</dd></div></dl>
              <div class="model-cost">\(credits)</div>
            </article>
            """
        }.joined()

        let sortedDaily = result.daily.sorted { $0.date < $1.date }
        let maxDaily = max(sortedDaily.map { $0.totals.estimatedCredits }.max() ?? 0, 1)
        let bars = sortedDaily.map { row in
            let value = row.totals.estimatedCredits
            let height = value == 0 ? 2 : max(2, value / maxDaily * 100)
            let label = dayLabel(row.date)
            return "<div class='bar-item' title='\(escape("\(row.date): $\(String(format: "%.2f", value)); \(UsageFormatting.integer(row.totals.totalTokens)) Tokens"))'><div class='bar-value'>$\(String(format: "%.0f", value))</div><div class='bar-track'><div class='bar' style='height:\(String(format: "%.2f", height))%'></div></div><div class='bar-label'>\(label)</div></div>"
        }.joined()

        let projectRows = result.projects.map { row in
            let cachePercent = row.totals.inputTokens == 0 ? 0 : Double(row.totals.cachedInputTokens) / Double(row.totals.inputTokens) * 100
            let credits = row.totals.creditsComplete ? money(row.totals.estimatedCredits) : "–"
            return "<tr><td><strong>\(escape(row.project))</strong><small>\(escape(row.workingDirectory))</small></td><td>\(escape(row.models))</td><td>\(escape(row.efforts))</td><td>\(UsageFormatting.integer(row.totals.sessions))</td><td>\(UsageFormatting.compact(row.totals.inputTokens))</td><td>\(UsageFormatting.compact(row.totals.cachedInputTokens))<small>\(UsageFormatting.decimal(cachePercent, digits: 1)) %</small></td><td>\(UsageFormatting.compact(row.totals.outputTokens))</td><td>\(UsageFormatting.compact(row.totals.totalTokens))</td><td class='money'>\(credits)</td></tr>"
        }.joined()

        let sessionCards = sessions.sorted { $0.ended > $1.ended }.map { row in
            let cost = row.estimatedCredits.map(money) ?? "nicht berechenbar"
            let cachePercent = row.inputTokens == 0 ? 0 : Double(row.cachedInputTokens) / Double(row.inputTokens) * 100
            let search = [row.project, row.task, row.model, row.effort].joined(separator: " ").lowercased()
            return """
            <article class="session" data-project="\(escape(row.project.lowercased()))" data-model="\(escape(row.model.lowercased()))" data-effort="\(escape(row.effort.lowercased()))" data-search="\(escape(search))">
              <div class="session-main"><div class="session-title-row"><span class="badge">CODEX</span><strong>\(escape(row.project))</strong><span class="task">\(escape(row.task))</span></div><div class="session-meta"><span>\(escape(row.model))</span><span>\(escape(row.effort))</span><span>\(UsageFormatting.localDate(row.ended))</span><span>\(UsageFormatting.duration(from: row.started, to: row.ended))</span></div><div class="token-line"><span><b>frisch</b> \(UsageFormatting.compact(row.uncachedInputTokens))</span><span><b>cached</b> \(UsageFormatting.compact(row.cachedInputTokens)) (\(UsageFormatting.decimal(cachePercent, digits: 1)) %)</span><span><b>output</b> \(UsageFormatting.compact(row.outputTokens))</span><span><b>reasoning</b> \(UsageFormatting.compact(row.reasoningTokens))</span></div></div><div class="session-cost"><strong>\(cost)</strong><small>hypothetische API-Kosten</small></div>
            </article>
            """
        }.joined()

        let modelOptions = Array(Set(sessions.map(\.model))).sorted().map { "<option value='\(escape($0.lowercased()))'>\(escape($0))</option>" }.joined()
        let effortOptions = Array(Set(sessions.map(\.effort))).sorted().map { "<option value='\(escape($0.lowercased()))'>\(escape($0))</option>" }.joined()

        return """
        <!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Codex-Verbrauch</title>
        <style>
        :root{--bg:#f4f3ef;--panel:#fbfaf7;--text:#232522;--muted:#777970;--line:#d9d7cf;--green:#2e7854;--orange:#c87539;--shadow:0 1px 2px #0000000b}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:14px}main{max-width:1440px;margin:auto;padding:34px 28px 60px}h1,h2,p{margin:0}h1{font-size:18px;letter-spacing:.08em;text-transform:uppercase}.header{display:flex;justify-content:space-between;align-items:flex-end;padding-bottom:18px;border-bottom:1px solid var(--line)}.header-title{display:flex;align-items:center;gap:10px}.header-title:before{content:"";width:8px;height:8px;border-radius:50%;background:var(--green)}.total{text-align:right;color:var(--muted);font-size:11px;letter-spacing:.12em;text-transform:uppercase}.total strong{display:block;color:var(--text);font-size:25px;letter-spacing:0}.sub{color:var(--muted);font-size:12px;margin-top:6px}.notice{display:flex;gap:12px;border:1px solid #cdbb76;background:#fffdf4;padding:11px 14px;margin:18px 0}.notice p{color:var(--muted);margin-top:2px;font-size:12px}.section-title{font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:#696b64;margin:28px 0 12px;display:flex;align-items:center;gap:12px}.section-title:after{content:"";height:1px;background:var(--line);flex:1}.summary-grid{display:grid;grid-template-columns:repeat(6,minmax(130px,1fr));gap:10px}.summary-card,.model-card{background:var(--panel);border:1px solid #e5e2da;box-shadow:var(--shadow);padding:16px}.summary-card small{display:block;color:var(--muted);text-transform:uppercase;letter-spacing:.1em;font-size:10px}.summary-card strong{display:block;font-size:22px;margin-top:7px}.model-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px}.model-head{display:flex;align-items:center;gap:8px;text-transform:uppercase;font-size:11px;letter-spacing:.08em}.model-dot{width:8px;height:8px;background:var(--green);border-radius:50%}.model-effort{color:var(--muted);font-size:12px;margin:7px 0 14px}dl{margin:0}dl div{display:flex;justify-content:space-between;padding:3px 0}dt{color:var(--muted)}dd{margin:0;font-variant-numeric:tabular-nums}.model-cost{font-size:19px;font-weight:700;text-align:right;margin-top:12px}.chart-panel,.table-panel,.sessions-panel{background:var(--panel);border:1px solid #e5e2da;padding:16px;box-shadow:var(--shadow)}.chart{height:250px;display:flex;gap:7px;align-items:stretch;border-bottom:1px solid var(--line);padding:12px 4px 0}.bar-item{flex:1;min-width:22px;display:grid;grid-template-rows:20px 1fr 24px;text-align:center}.bar-value{font-size:9px;color:var(--muted)}.bar-track{position:relative;height:100%;display:flex;align-items:flex-end}.bar{width:70%;margin:auto;background:linear-gradient(180deg,var(--orange),#d89562);min-height:2px}.bar-label{font-size:10px;color:var(--muted);padding-top:6px}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;white-space:nowrap}th{font-size:10px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);text-align:right;padding:10px;border-bottom:1px solid var(--line)}th:first-child,td:first-child{text-align:left}td{padding:12px 10px;text-align:right;border-bottom:1px solid #e8e6df;font-variant-numeric:tabular-nums}td small{display:block;color:var(--muted);font-size:10px;margin-top:3px;max-width:360px;overflow:hidden;text-overflow:ellipsis}.money{font-weight:700}.filters{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px}input,select{background:#fff;border:1px solid var(--line);padding:8px 10px;color:var(--text);font:inherit}input{min-width:280px;flex:1}.session{display:grid;grid-template-columns:1fr 180px;gap:18px;padding:14px 12px;border-top:1px solid #e1dfd8;background:var(--panel)}.session:first-of-type{border-top:0}.session-title-row{display:flex;align-items:baseline;gap:9px;min-width:0}.badge{font-size:9px;letter-spacing:.08em;border:1px solid #9da29c;padding:2px 5px;color:#626762}.task{color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.session-meta,.token-line{display:flex;gap:11px;flex-wrap:wrap;color:var(--muted);font-size:11px;margin-top:6px}.token-line b{color:#5d605a;font-weight:600}.session-cost{text-align:right;align-self:center}.session-cost strong{font-size:18px;display:block}.session-cost small{color:var(--muted);font-size:10px}.empty{display:none;text-align:center;color:var(--muted);padding:30px}footer{color:var(--muted);font-size:11px;line-height:1.5;margin-top:22px}@media(max-width:900px){.summary-grid{grid-template-columns:repeat(2,1fr)}.session{grid-template-columns:1fr}.session-cost{text-align:left}}@media(max-width:560px){main{padding:20px 12px}.summary-grid{grid-template-columns:1fr 1fr}.header{align-items:flex-start}.total strong{font-size:19px}input{min-width:100%}}@media(prefers-color-scheme:dark){:root{--bg:#191a18;--panel:#232420;--text:#ecece7;--muted:#a6a79f;--line:#3d3e38;--shadow:none}input,select{background:#1d1e1b;color:var(--text)}.summary-card,.model-card,.chart-panel,.table-panel,.sessions-panel,.session{border-color:#353630}td{border-color:#353630}}
        </style></head><body><main>
        <header class="header"><div><div class="header-title"><h1>Codex-Verbrauch</h1></div><p class="sub">Lokale Sitzungslogs · erzeugt am \(UsageFormatting.localDate(result.generatedAt))</p></div><div class="total">geschätzte Gesamtkosten<strong>\(money(knownCredits))</strong></div></header>\(warning)
        <h2 class="section-title">Übersicht</h2><div class="summary-grid"><div class="summary-card"><small>Sessions</small><strong>\(UsageFormatting.integer(sessions.count))</strong></div><div class="summary-card"><small>Token gesamt</small><strong>\(UsageFormatting.compact(total))</strong></div><div class="summary-card"><small>Frischer Input</small><strong>\(UsageFormatting.compact(uncached))</strong></div><div class="summary-card"><small>Cached Input</small><strong>\(UsageFormatting.compact(cached))</strong></div><div class="summary-card"><small>Cache-Anteil</small><strong>\(UsageFormatting.decimal(cacheRatio, digits: 1)) %</strong></div><div class="summary-card"><small>Output</small><strong>\(UsageFormatting.compact(output))</strong></div></div>
        <h2 class="section-title">Summen nach Modell und Aufwand</h2><div class="model-grid">\(modelCards)</div><h2 class="section-title">Verlauf: Kosten pro Tag</h2><section class="chart-panel"><div class="chart">\(bars)</div></section><h2 class="section-title">Projekte</h2><section class="table-panel"><div class="table-wrap"><table><thead><tr><th>Projekt</th><th>Modell</th><th>Aufwand</th><th>Sessions</th><th>Input</th><th>Cache</th><th>Output</th><th>Gesamt</th><th>Kosten*</th></tr></thead><tbody>\(projectRows)</tbody></table></div></section><h2 class="section-title">Sessions</h2><section class="sessions-panel"><div class="filters"><input id="search" type="search" placeholder="Projekt oder Aufgabe durchsuchen …"><select id="model"><option value="">Alle Modelle</option>\(modelOptions)</select><select id="effort"><option value="">Alle Aufwände</option>\(effortOptions)</select></div><div id="sessions">\(sessionCards)</div><div id="empty" class="empty">Keine passenden Sessions gefunden.</div></section><footer>* Hypothetische API-Kosten anhand der im Quellcode hinterlegten Rate-Card. Sie entsprechen nicht zwingend der tatsächlichen Codex-Kontingentberechnung. Cached Input wird als Teilmenge des Input-Werts behandelt. Pro Session wird der höchste kumulierte Tokenstand verwendet.</footer><script>const search=document.getElementById('search'),model=document.getElementById('model'),effort=document.getElementById('effort');function filterSessions(){const q=search.value.trim().toLowerCase(),m=model.value,e=effort.value;let visible=0;document.querySelectorAll('.session').forEach(el=>{const ok=(!q||el.dataset.search.includes(q))&&(!m||el.dataset.model===m)&&(!e||el.dataset.effort===e);el.style.display=ok?'grid':'none';if(ok)visible++;});document.getElementById('empty').style.display=visible?'none':'block';}[search,model,effort].forEach(el=>el.addEventListener('input',filterSessions));</script></main></body></html>
        """
    }

    private static func money(_ value: Double) -> String { "$\(UsageFormatting.decimal(value))" }

    private static func dayLabel(_ value: String) -> String {
        let parts = value.split(separator: "-")
        return parts.count == 3 ? "\(parts[2]).\(parts[1])." : value
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
    }
}
