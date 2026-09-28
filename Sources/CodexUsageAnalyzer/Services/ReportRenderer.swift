import Foundation

enum ReportRenderer {
    static func render(_ result: AnalysisResult) -> String {
        let sessions = result.sessions
        let scope = result.activitySince.map {
            "Sessions mit Aktivität ab \(UsageFormatting.localDate($0, includeTime: false)). Alle Tokens dieser Sessions zählen, auch vor dem Datum."
        } ?? "Alle Sessions. Vollständige Tokenstände je Session."
        let emptyNotice = sessions.isEmpty ? "<p class='sub'>Keine Sessions mit Aktivität im gewählten Zeitraum.</p>" : ""
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
            let credits = row.totals.creditsComplete ? formattedCredits(row.totals.estimatedCredits) : "–"
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
            return "<div class='bar-item' tabindex='0' title='\(escape("\(row.date): \(String(format: "%.2f", value)) Credits; \(UsageFormatting.integer(row.totals.totalTokens)) Tokens"))'><div class='bar-value'>\(String(format: "%.0f", value))</div><div class='bar-track'><div class='bar' style='height:\(String(format: "%.2f", height))%'></div></div><div class='bar-label'>\(label)</div></div>"
        }.joined()

        let projectRows = result.projects.map { row in
            let cachePercent = row.totals.inputTokens == 0 ? 0 : Double(row.totals.cachedInputTokens) / Double(row.totals.inputTokens) * 100
            let credits = row.totals.creditsComplete ? formattedCredits(row.totals.estimatedCredits) : "–"
            let creditSort = row.totals.creditsComplete ? String(row.totals.estimatedCredits) : ""
            return """
            <tr data-name="\(escape(row.project))" data-search="\(escape([row.project, row.workingDirectory, row.models].joined(separator: " ").lowercased()))" data-tokens="\(row.totals.totalTokens)" data-count="\(row.totals.sessions)" data-credits="\(creditSort)">
              <td data-label="Projekt"><button class="project-link" data-project="\(escape(row.workingDirectory))" title="Sessions für dieses Projekt anzeigen">\(escape(row.project))</button><small>\(escape(row.workingDirectory))</small></td>
              <td data-label="Modell">\(escape(row.models))</td><td data-label="Aufwand">\(escape(row.efforts))</td>
              <td data-label="Sessions">\(UsageFormatting.integer(row.totals.sessions))</td><td data-label="Input">\(UsageFormatting.compact(row.totals.inputTokens))</td>
              <td data-label="Cache">\(UsageFormatting.compact(row.totals.cachedInputTokens))<small>\(UsageFormatting.decimal(cachePercent, digits: 1)) %</small></td>
              <td data-label="Output">\(UsageFormatting.compact(row.totals.outputTokens))</td><td data-label="Gesamt">\(UsageFormatting.compact(row.totals.totalTokens))</td><td data-label="Credits" class="money">\(credits)</td>
            </tr>
            """
        }.joined()

        let sessionCards = sessions.sorted { $0.ended > $1.ended }.map { row in
            let cost = row.estimatedCredits.map(formattedCredits) ?? "nicht berechenbar"
            let cachePercent = row.inputTokens == 0 ? 0 : Double(row.cachedInputTokens) / Double(row.inputTokens) * 100
            let taskMarkup = row.task.hasPrefix("<")
                ? "<details class='task'><summary>Aufgabentext anzeigen</summary><p>\(escape(row.task))</p></details>"
                : "<span class='task'>\(escape(row.task))</span>"
            let search = [row.project, row.task, row.model, row.effort].joined(separator: " ").lowercased()
            return """
            <article class="session" data-project="\(escape(row.workingDirectory))" data-model="\(escape(row.model.lowercased()))" data-effort="\(escape(row.effort.lowercased()))" data-search="\(escape(search))">
              <div class="session-main"><div class="session-title-row"><strong>\(escape(row.project))</strong></div>\(taskMarkup)<div class="session-meta"><span>\(escape(row.model))</span><span>\(escape(row.effort))</span><span>\(UsageFormatting.localDate(row.ended))</span><span>\(UsageFormatting.duration(from: row.started, to: row.ended))</span></div><div class="token-line"><span><b>frisch</b> \(UsageFormatting.compact(row.uncachedInputTokens))</span><span><b>cached</b> \(UsageFormatting.compact(row.cachedInputTokens)) (\(UsageFormatting.decimal(cachePercent, digits: 1)) %)</span><span><b>output</b> \(UsageFormatting.compact(row.outputTokens))</span><span><b>reasoning</b> \(UsageFormatting.compact(row.reasoningTokens))</span></div></div><div class="session-cost"><strong>\(cost)</strong><small>geschätzte Codex-Credits</small></div>
            </article>
            """
        }.joined()

        let retainedRates = result.pricing.retainedModels.map { name in
            "\(name) (\(UsageFormatting.localDate(result.pricing.rates[name]!.verifiedAt, includeTime: false)))"
        }.joined(separator: ", ")
        let comparisonRows = [1, 100, 1_000].map { amount in
            let digits = amount == 1 ? 4 : 2
            return "<tr><td>\(UsageFormatting.integer(amount))</td><td>\(UsageFormatting.decimal(Double(amount) * result.pricing.usdPerCredit, digits: digits)) $</td><td>\(UsageFormatting.decimal(Double(amount) * result.pricing.eurPerCredit, digits: digits)) €</td></tr>"
        }.joined()
        let comparison = """
        <details class="table-panel" style="padding:16px;margin-top:24px"><summary>Creditwert · API-Vergleich als Orientierung</summary>
        <table><thead><tr><th>Credits</th><th>US-Dollar (≈)</th><th>Euro (≈)</th></tr></thead><tbody>\(comparisonRows)</tbody></table>
        <p>Abgeleitet aus den Standard-API- und Credit-Raten von GPT-6 Astra. Kein Credit-Kaufpreis und keine Abrechnung; Tarifpreise, Rabatte und Steuern sind nicht abgebildet.</p>
        <p>\(result.pricing.isBundled ? "Mitgelieferter Stand" : "Abgerufen"): \(escape(UsageFormatting.localDate(result.pricing.checkedAt, includeTime: !result.pricing.isBundled))). EZB-Kurs vom \(escape(result.pricing.exchangeDate)): 1 € = \(UsageFormatting.decimal(result.pricing.usdPerEUR, digits: 4)) $.</p>
        <p>Quellen: <a href="https://learn.chatgpt.com/docs/pricing">OpenAI Credit-Raten</a> · <a href="https://developers.openai.com/api/docs/models/gpt-6-astra">OpenAI API-Preise</a> · <a href="https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml">EZB</a></p></details>
        """
        let modelOptions = Array(Set(sessions.map(\.model))).sorted().map { "<option value='\(escape($0.lowercased()))'>\(escape($0))</option>" }.joined()
        let effortOptions = Array(Set(sessions.map(\.effort))).sorted().map { "<option value='\(escape($0.lowercased()))'>\(escape($0))</option>" }.joined()

        let projectOptions = result.projects.sorted { $0.workingDirectory < $1.workingDirectory }.map {
            "<option value='\(escape($0.workingDirectory))'>\(escape($0.project)) · \(escape($0.workingDirectory))</option>"
        }.joined()

        return """
        <!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Codex-Verbrauch</title>
        <style>\(styles)</style></head><body><main>
        <header class="header"><div><div class="header-title"><h1>Codex-Verbrauch</h1></div><p class="sub">Lokale Sitzungslogs · \(UsageFormatting.localDate(result.generatedAt))</p></div><div class="total">geschätzte Credits (bekannte Raten)<strong>\(formattedCredits(knownCredits))</strong></div></header>
        <p class="sub">\(escape(scope))</p>\(emptyNotice)
        <nav class="report-nav" aria-label="Berichtsbereiche">
          <a href="#overview" aria-current="page">Übersicht</a><a href="#projects">Projekte <small>\(result.projects.count)</small></a><a href="#session-list">Sessions <small>\(sessions.count)</small></a><a href="#models">Modelle & Aufwand <small>\(result.modelEffort.count)</small></a>
        </nav>
        <section id="overview" class="report-panel" aria-label="Übersicht">
        \(warning)
        <h2 class="section-title">Übersicht</h2><div class="summary-grid"><div class="summary-card"><small>Sessions</small><strong>\(UsageFormatting.integer(sessions.count))</strong></div><div class="summary-card"><small>Token gesamt</small><strong>\(UsageFormatting.compact(total))</strong></div><div class="summary-card"><small>Frischer Input</small><strong>\(UsageFormatting.compact(uncached))</strong></div><div class="summary-card"><small>Cached Input</small><strong>\(UsageFormatting.compact(cached))</strong></div><div class="summary-card"><small>Cache-Anteil</small><strong>\(UsageFormatting.decimal(cacheRatio, digits: 1)) %</strong></div><div class="summary-card"><small>Output</small><strong>\(UsageFormatting.compact(output))</strong></div></div>
        <h2 class="section-title">Verlauf: Credits pro Tag</h2><section class="chart-panel"><div class="chart">\(bars)</div></section>
        \(comparison)
        <footer>* Geschätzte Codex-Credits zu Standardraten, Preisstand \(result.pricing.dateLabel) (OpenAI Codex Rate Card). Alle Sessions werden mit diesen Raten neu bewertet; keine historische Abrechnung. Beibehaltene Altraten (im aktuellen Abruf nicht veröffentlicht): \(escape(retainedRates)). Fast-Modus, Langkontext- und Cache-Schreibaufschläge werden nicht berücksichtigt. Credits sind keine US-Dollar und entsprechen nicht zwingend dem tatsächlichen Kontingentverbrauch. Cached Input wird als Teilmenge des Input-Werts behandelt. Pro Session wird der höchste kumulierte Tokenstand verwendet.</footer>
        </section>
        <section id="projects" class="report-panel" aria-labelledby="projects-title">
          <div class="panel-heading"><h2 id="projects-title">Projekte</h2><p>Projekt anklicken, um seine Sessions zu sehen.</p></div>
          <div class="filters"><label>Suche<input id="project-search" type="search" placeholder="Projekt, Pfad oder Modell durchsuchen …"></label><label>Sortierung<select id="project-sort"><option value="tokens">Tokens: höchste zuerst</option><option value="credits">Credits: höchste zuerst</option><option value="count">Sessions: meiste zuerst</option><option value="name">Projektname: A–Z</option></select></label></div>
          \(pager("projects", noun: "Projekte", live: true))
          <section class="table-panel"><table class="project-table"><thead><tr><th>Projekt</th><th>Modell</th><th>Aufwand</th><th>Sessions</th><th>Input</th><th>Cache</th><th>Output</th><th>Gesamt</th><th>Credits*</th></tr></thead><tbody>\(projectRows)</tbody></table><p id="projects-empty" class="empty" hidden>Keine passenden Projekte gefunden.</p></section>
          \(pager("projects", noun: "Projekte"))
          <p class="sub">* Credits sind Schätzwerte. – bedeutet: Für mindestens ein Modell fehlt eine Rate.</p>
        </section>
        <section id="session-list" class="report-panel" aria-labelledby="sessions-title">
          <div class="panel-heading"><h2 id="sessions-title">Sessions</h2><p>Neueste Aktivität zuerst.</p></div>
          <div class="filters">
            <label>Suche<input id="search" type="search" placeholder="Projekt oder Aufgabe durchsuchen …"></label>
            <label>Projekt<select id="project"><option value="">Alle Projekte</option>\(projectOptions)</select></label>
            <label>Modell<select id="model"><option value="">Alle Modelle</option>\(modelOptions)</select></label>
            <label>Aufwand<select id="effort"><option value="">Alle Aufwände</option>\(effortOptions)</select></label>
            <button id="reset-filters" type="button">Zurücksetzen</button>
          </div>
          \(pager("sessions", noun: "Sessions", live: true))
          <section class="sessions-panel"><div id="sessions">\(sessionCards)</div><p id="empty" class="empty" hidden>Keine passenden Sessions gefunden. Passe die Filter an oder setze sie zurück.</p></section>
          \(pager("sessions", noun: "Sessions"))
        </section>
        <section id="models" class="report-panel" aria-labelledby="models-title">
          <div class="panel-heading"><h2 id="models-title">Modelle & Aufwand</h2><p>Summen je Modell und Reasoning-Aufwand.</p></div><div class="model-grid">\(modelCards)</div>
        </section>
        <script>\(interactionScript)</script></main></body></html>
        """
    }

    private static func pager(_ target: String, noun: String, live: Bool = false) -> String {
        """
        <div class="pager" data-pager="\(target)"><span class="result-count" \(live ? "aria-live='polite'" : "")></span><div class="pager-controls"><button type="button" data-step="-1" aria-label="\(noun): vorherige Seite">Zurück</button><span class="page-number"></span><button type="button" data-step="1" aria-label="\(noun): nächste Seite">Weiter</button></div></div>
        """
    }

    private static let styles = """
        :root{--bg:#f4f3ef;--panel:#fbfaf7;--text:#232522;--muted:#777970;--line:#d9d7cf;--green:#2e7854;--orange:#c87539;--shadow:0 1px 2px #0000000b}
        *{box-sizing:border-box}
        body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:14px}
        main{width:100%;padding:24px 28px 40px}
        h1,h2,p{margin:0}
        h1{font-size:18px;letter-spacing:.08em;text-transform:uppercase}
        .header{display:flex;justify-content:space-between;align-items:flex-end;padding-bottom:18px;border-bottom:1px solid var(--line)}
        .header-title{display:flex;align-items:center;gap:10px}
        .header-title:before{content:"";width:8px;height:8px;border-radius:50%;background:var(--green)}
        .total{text-align:right;color:var(--muted);font-size:11px;letter-spacing:.12em;text-transform:uppercase}
        .total strong{display:block;color:var(--text);font-size:25px;letter-spacing:0}
        .sub{color:var(--muted);font-size:12px;margin-top:6px}
        .notice{display:flex;gap:12px;border:1px solid #cdbb76;background:var(--panel);padding:11px 14px;margin:18px 0}
        .notice p{color:var(--muted);margin-top:2px;font-size:12px}
        .section-title{font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--muted);margin:28px 0 12px;display:flex;align-items:center;gap:12px}
        .section-title:after{content:"";height:1px;background:var(--line);flex:1}
        .summary-grid{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:10px}
        .summary-card,.model-card{background:var(--panel);border:1px solid #e5e2da;box-shadow:var(--shadow);padding:16px}
        .summary-card small{display:block;color:var(--muted);text-transform:uppercase;letter-spacing:.1em;font-size:10px}
        .summary-card strong{display:block;font-size:22px;margin-top:7px}
        .model-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px}
        .model-head{display:flex;align-items:center;gap:8px;text-transform:uppercase;font-size:11px;letter-spacing:.08em}
        .model-dot{width:8px;height:8px;background:var(--green);border-radius:50%}
        .model-effort{color:var(--muted);font-size:12px;margin:7px 0 14px}
        dl{margin:0}
        dl div{display:flex;justify-content:space-between;padding:3px 0}
        dt{color:var(--muted)}
        dd{margin:0;font-variant-numeric:tabular-nums}
        .model-cost{font-size:19px;font-weight:700;text-align:right;margin-top:12px}
        .chart-panel,.table-panel,.sessions-panel{background:var(--panel);border:1px solid #e5e2da;padding:16px;box-shadow:var(--shadow)}
        .chart{height:230px;display:flex;gap:7px;align-items:stretch;border-bottom:1px solid var(--line);padding:12px 4px 0}
        .bar-item{flex:1;min-width:0;display:grid;grid-template-rows:20px 1fr 24px;text-align:center}
        .bar-value{font-size:9px;color:var(--muted)}
        .bar-track{position:relative;height:100%;display:flex;align-items:flex-end}
        .bar{width:70%;margin:0 auto;background:linear-gradient(180deg,var(--orange),#d89562);min-height:2px}
        .bar-label{font-size:10px;color:var(--muted);padding-top:6px}
        table{width:100%;border-collapse:collapse;white-space:nowrap}
        th{font-size:10px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);text-align:right;padding:10px;border-bottom:1px solid var(--line)}
        th:first-child,td:first-child{text-align:left}
        td{padding:12px 10px;text-align:right;border-bottom:1px solid #e8e6df;font-variant-numeric:tabular-nums}
        td small{display:block;color:var(--muted);font-size:10px;margin-top:3px;max-width:360px;overflow:hidden;text-overflow:ellipsis}
        .money{font-weight:700}
        .filters{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px}
        input,select{background:#fff;border:1px solid var(--line);padding:8px 10px;color:var(--text);font:inherit}
        input{min-width:280px;flex:1}
        .session{display:grid;grid-template-columns:minmax(0,1fr) 170px;gap:18px;padding:16px 4px;border-top:1px solid #e1dfd8;background:var(--panel)}
        .session:first-of-type{border-top:0}
        .session-meta,.token-line{display:flex;gap:11px;flex-wrap:wrap;color:var(--muted);font-size:11px;margin-top:6px}
        .token-line b{color:var(--muted);font-weight:600}
        .session-cost{text-align:right;align-self:center}
        .session-cost strong{font-size:16px;display:block}
        .session-cost small{color:var(--muted);font-size:10px}
        .empty{display:block;text-align:center;color:var(--muted);padding:30px}
        footer{color:var(--muted);font-size:11px;line-height:1.5;margin-top:22px}
        @media(max-width:900px){.summary-grid{grid-template-columns:repeat(2,1fr)}
        }
        @media(max-width:560px){main{padding:20px 12px}
        .summary-grid{grid-template-columns:1fr 1fr}
        .header{align-items:flex-start}
        .total strong{font-size:19px}
        input{min-width:100%}
        }
        @media(prefers-color-scheme:dark){:root{--bg:#191a18;--panel:#232420;--text:#ecece7;--muted:#a6a79f;--line:#3d3e38;--green:#82bf9e;--shadow:none}
        input,select{background:#1d1e1b;color:var(--text)}
        .summary-card,.model-card,.chart-panel,.table-panel,.sessions-panel,.session{border-color:#353630}
        td{border-color:#353630}
        }
        [hidden]{display:none!important}
        button{font:inherit;color:var(--text);background:var(--panel);border:1px solid var(--line);padding:7px 12px;border-radius:5px;cursor:pointer}
        button:hover{background:var(--bg)}button:disabled{opacity:.45;cursor:default}
        :is(a,button,input,select,summary):focus-visible{outline:2px solid var(--green);outline-offset:3px}
        .report-nav{position:sticky;top:0;z-index:5;display:flex;gap:6px;flex-wrap:wrap;background:var(--bg);padding:12px 0;border-bottom:1px solid var(--line);margin-top:16px}
        .report-nav a{color:var(--muted);text-decoration:none;padding:9px 14px;border-radius:6px;font-weight:600}
        .report-nav a:hover{color:var(--text);background:var(--panel)}
        .report-nav a[aria-current="page"]{background:var(--text);color:var(--bg)}
        .report-nav small{font-size:11px;font-weight:400;margin-left:7px}
        .panel-heading{display:flex;justify-content:space-between;align-items:baseline;gap:12px;margin:24px 0 16px}
        .panel-heading h2{font-size:18px}.panel-heading p{color:var(--muted);font-size:12px}
        .filters label{display:flex;flex-direction:column;gap:5px;color:var(--muted);font-size:11px;min-width:0}
        .filters label:first-child{flex:1;min-width:220px}.filters input{min-width:0;width:100%}
        .filters select{max-width:300px;min-width:140px}.filters input,.filters select{font-size:13px;border-radius:5px}
        .filters button{align-self:flex-end;min-height:34px}.pager{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 0;color:var(--muted);font-size:12px;flex-wrap:wrap}
        .pager-controls{display:flex;align-items:center;gap:8px}.pager-controls span{min-width:85px;text-align:center}
        .project-table{table-layout:fixed;white-space:normal}.project-table th,.project-table td{padding:12px 8px;overflow-wrap:anywhere}
        .project-table th:nth-child(1){width:24%}.project-table th:nth-child(2){width:19%}.project-table th:nth-child(3){width:12%}.project-table th:last-child{width:12%}
        .project-table td small{max-width:none;overflow:visible;overflow-wrap:anywhere}
        .project-link{border:0;padding:0;background:none;text-align:left;font-weight:650;color:var(--green);overflow-wrap:anywhere}
        .project-link:hover{text-decoration:underline;background:none}
        .project-table th{position:sticky;top:var(--nav-height,60px);z-index:2;background:var(--panel)}
        .task summary{cursor:pointer}.task p{margin-top:5px}
        .notice strong{color:var(--text)}
        .session-main{min-width:0}
        .session-title-row{display:block;min-width:0}.session-title-row strong{font-size:14px;overflow-wrap:anywhere}
        .task{color:var(--muted);display:block;white-space:normal;overflow-wrap:anywhere;margin-top:5px;font-size:12px;line-height:1.5}
        .session-meta{font-size:12px}.token-line{line-height:1.5}
        .chart-panel{overflow:hidden}.bar-value{overflow:hidden;text-overflow:ellipsis}.bar-label{white-space:nowrap;font-size:9px}
        .notice{font-size:12px}.notice p{line-height:1.5}
        .report-panel{scroll-margin-top:70px}.report-panel>footer{margin-bottom:20px}
        @media(max-width:1100px){
        .project-table,.project-table tbody{display:block}.project-table thead{display:none}
        .project-table tr{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:12px;border-bottom:1px solid var(--line);padding:18px 0}
        .project-table td{display:block;border:0;padding:0;text-align:left}
        .project-table td:before{content:attr(data-label);display:block;font-size:10px;color:var(--muted);margin-bottom:5px}
        .project-table td:first-child{grid-column:1/-1}.project-table td:nth-child(2),.project-table td:nth-child(3){grid-column:span 3}
        .project-table td:first-child:before{display:none}.project-table td:last-child{font-size:12px}
        .filters select{max-width:220px}.summary-card{padding:12px}.summary-card strong{font-size:19px}
        }
        @media(max-width:700px){
        main{padding:18px 14px 32px}.report-nav{gap:2px}.report-nav a{padding:8px;font-size:12px}.report-nav small{display:none}
        .header{gap:12px;flex-wrap:wrap}.total{text-align:left}.panel-heading{display:block}.panel-heading p{margin-top:6px}
        .project-table tr{grid-template-columns:repeat(3,minmax(0,1fr))}.project-table td:nth-child(2),.project-table td:nth-child(3){grid-column:1/-1}
        .filters label{flex:1;min-width:140px}.filters select{max-width:100%;width:100%}.session{grid-template-columns:1fr}.session-cost{text-align:left}
        .bar-label{font-size:8px}.bar-item:nth-child(even) .bar-label{visibility:hidden}
        }
        @media print{.report-nav,.filters,.pager{display:none!important}.report-panel[hidden],.session[hidden],.project-table tr[hidden]{display:block!important}.project-table tr[hidden]{display:table-row!important}}
        """

    private static let interactionScript = #"""
        (() => {
          const byID = id => document.getElementById(id);
          const panels = [...document.querySelectorAll('.report-panel')];
          const navigation = [...document.querySelectorAll('.report-nav a')];
          const projectRows = [...document.querySelectorAll('.project-table tbody tr')];
          const sessions = [...document.querySelectorAll('.session')];
          const sessionFilters = ['search', 'project', 'model', 'effort'].map(byID);
          const pageSizes = {projects: 20, sessions: 25};
          const pages = {projects: 0, sessions: 0};
          let currentPanel = 'overview';

          function showPanel(id, moveFocus = false) {
            if (!panels.some(panel => panel.id === id)) id = 'overview';
            currentPanel = id;
            panels.forEach(panel => panel.hidden = panel.id !== id);
            navigation.forEach(link => {
              const active = link.hash === '#' + id;
              if (active) link.setAttribute('aria-current', 'page');
              else link.removeAttribute('aria-current');
            });
            window.scrollTo(0, 0);
            if (moveFocus) navigation.find(link => link.hash === '#' + id).focus({preventScroll: true});
            fitChartLabels();
          }
          navigation.forEach(link => link.addEventListener('click', event => {
            event.preventDefault();
            showPanel(link.hash.slice(1));
          }));

          function paginate(target, matches, all, noun) {
            const size = pageSizes[target];
            const count = Math.max(1, Math.ceil(matches.length / size));
            pages[target] = Math.min(Math.max(0, pages[target]), count - 1);
            const start = pages[target] * size;
            const end = Math.min(start + size, matches.length);
            const range = start + 1 === end ? String(end) : (start + 1) + '–' + end;
            const label = matches.length === 1 ? (target === 'projects' ? 'Projekt' : 'Session') : noun;
            all.forEach(row => row.hidden = true);
            matches.slice(start, start + size).forEach(row => row.hidden = false);
            document.querySelectorAll('[data-pager="' + target + '"]').forEach(pager => {
              pager.querySelector('.result-count').textContent = matches.length
                ? range + ' von ' + matches.length + ' ' + label + (matches.length !== all.length ? ' · ' + all.length + ' insgesamt' : '')
                : '0 von ' + all.length + ' ' + noun;
              pager.querySelector('.page-number').textContent = 'Seite ' + (pages[target] + 1) + ' / ' + count;
              pager.querySelector('[data-step="-1"]').disabled = pages[target] === 0;
              pager.querySelector('[data-step="1"]').disabled = pages[target] === count - 1;
            });
          }
          function filterSessions() {
            const [query, project, model, effort] = sessionFilters.map(control => control.value);
            const q = query.trim().toLowerCase();
            const matches = sessions.filter(row => (!q || row.dataset.search.includes(q)) &&
              (!project || row.dataset.project === project) && (!model || row.dataset.model === model) &&
              (!effort || row.dataset.effort === effort));
            paginate('sessions', matches, sessions, 'Sessions');
            byID('empty').hidden = matches.length !== 0;
          }
          function filterProjects() {
            const query = byID('project-search').value.trim().toLowerCase();
            const sort = byID('project-sort').value;
            const matches = projectRows.filter(row => !query || row.dataset.search.includes(query));
            matches.sort((a, b) => {
              if (sort === 'name') return a.dataset.name.localeCompare(b.dataset.name, 'de');
              const av = a.dataset[sort] === '' ? -1 : Number(a.dataset[sort]);
              const bv = b.dataset[sort] === '' ? -1 : Number(b.dataset[sort]);
              return bv - av || a.dataset.name.localeCompare(b.dataset.name, 'de');
            });
            const body = document.querySelector('.project-table tbody');
            matches.forEach(row => body.appendChild(row));
            paginate('projects', matches, projectRows, 'Projekte');
            byID('projects-empty').hidden = matches.length !== 0;
          }
          sessionFilters.forEach(control => control.addEventListener('input', () => {
            pages.sessions = 0;
            filterSessions();
          }));
          ['project-search', 'project-sort'].forEach(id => byID(id).addEventListener('input', () => {
            pages.projects = 0;
            filterProjects();
          }));
          byID('reset-filters').addEventListener('click', () => {
            sessionFilters.forEach(control => control.value = '');
            pages.sessions = 0;
            filterSessions();
            byID('search').focus();
          });
          document.querySelectorAll('.project-link').forEach(button => button.addEventListener('click', () => {
            sessionFilters.forEach(control => control.value = '');
            byID('project').value = button.dataset.project;
            pages.sessions = 0;
            filterSessions();
            showPanel('session-list', true);
          }));
          document.querySelectorAll('[data-pager] button').forEach(button => button.addEventListener('click', () => {
            const target = button.closest('[data-pager]').dataset.pager;
            pages[target] += Number(button.dataset.step);
            if (target === 'projects') filterProjects(); else filterSessions();
            // Keep the next page and its controls in view, including when using the bottom pager.
            window.scrollTo(0, 0);
            const topPager = document.querySelector('[data-pager="' + target + '"]');
            const nextFocus = [...topPager.querySelectorAll('button')].find(candidate => !candidate.disabled);
            if (nextFocus) nextFocus.focus({preventScroll: true});
          }));

          function fitChartLabels() {
            const chart = document.querySelector('.chart');
            if (!chart || !chart.clientWidth) return;
            const bars = [...chart.querySelectorAll('.bar-item')];
            const stride = Math.max(1, Math.ceil(bars.length * 38 / chart.clientWidth));
            chart.style.gap = Math.min(7, chart.clientWidth / Math.max(1, bars.length * 5)) + 'px';
            bars.forEach((bar, index) => {
              bar.querySelector('.bar-label').style.visibility = index % stride === 0 ? 'visible' : 'hidden';
              bar.querySelector('.bar-value').style.visibility = stride === 1 ? 'visible' : 'hidden';
            });
          }
          // Preserve navigation and filters when the native host changes the appearance or refreshes data.
          window.reportViewState = () => ({panel: currentPanel, filters: sessionFilters.map(control => control.value),
            projectSearch: byID('project-search').value, projectSort: byID('project-sort').value,
            pages: {...pages}, scrollY: window.scrollY});
          window.restoreReportViewState = state => {
            if (!state || typeof state !== 'object') return;
            sessionFilters.forEach((control, index) => {
              const value = state.filters?.[index];
              if (typeof value === 'string') control.value = value;
              if (control.tagName === 'SELECT' && control.selectedIndex < 0) control.selectedIndex = 0;
            });
            if (typeof state.projectSearch === 'string') byID('project-search').value = state.projectSearch;
            if (['tokens', 'credits', 'count', 'name'].includes(state.projectSort)) byID('project-sort').value = state.projectSort;
            for (const target of ['projects', 'sessions']) {
              if (Number.isInteger(state.pages?.[target])) pages[target] = Math.max(0, state.pages[target]);
            }
            filterProjects(); filterSessions(); showPanel(state.panel);
            if (Number.isFinite(state.scrollY)) window.scrollTo(0, state.scrollY);
          };
          filterProjects();
          filterSessions();
          showPanel(location.hash.slice(1) || 'overview');
          new ResizeObserver(fitChartLabels).observe(document.querySelector('.chart'));
          const nav = document.querySelector('.report-nav');
          new ResizeObserver(() => document.documentElement.style.setProperty('--nav-height', nav.offsetHeight + 'px')).observe(nav);
        })();
        """#

    private static func formattedCredits(_ value: Double) -> String { "\(UsageFormatting.decimal(value)) Credits" }

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
