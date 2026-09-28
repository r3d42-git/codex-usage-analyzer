import SwiftUI
import WebKit

struct ReportWebView: NSViewRepresentable {
    let html: String
    let appearance: AppAppearance

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        let renderedHTML = htmlForAppearance
        context.coordinator.lastHTML = renderedHTML
        view.loadHTMLString(renderedHTML, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let renderedHTML = htmlForAppearance
        guard context.coordinator.lastHTML != renderedHTML else { return }
        context.coordinator.lastHTML = renderedHTML
        let coordinator = context.coordinator
        view.evaluateJavaScript("JSON.stringify(window.reportViewState?.())") { state, _ in
            guard coordinator.lastHTML == renderedHTML else { return }
            coordinator.pendingViewState = state as? String
            view.loadHTMLString(renderedHTML, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        var pendingViewState: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let state = pendingViewState else { return }
            pendingViewState = nil
            webView.evaluateJavaScript("window.restoreReportViewState?.(\(state))", completionHandler: nil)
        }
    }

    private var htmlForAppearance: String {
        let theme = appearance.rawValue
        let override = """
        <style>
        html[data-app-theme="light"]{color-scheme:light;--bg:#f4f3ef;--panel:#fbfaf7;--text:#232522;--muted:#777970;--line:#d9d7cf;--green:#2e7854;--shadow:0 1px 2px #0000000b}
        html[data-app-theme="dark"]{color-scheme:dark;--bg:#191a18;--panel:#232420;--text:#ecece7;--muted:#a6a79f;--line:#3d3e38;--green:#82bf9e;--shadow:none}
        html[data-app-theme="light"] input,html[data-app-theme="light"] select{background:#fff;color:#232522}
        html[data-app-theme="dark"] input,html[data-app-theme="dark"] select{background:#1d1e1b;color:#ecece7}
        html[data-app-theme="dark"] .summary-card,html[data-app-theme="dark"] .model-card,html[data-app-theme="dark"] .chart-panel,html[data-app-theme="dark"] .table-panel,html[data-app-theme="dark"] .sessions-panel,html[data-app-theme="dark"] .session{border-color:#353630}
        html[data-app-theme="dark"] td{border-color:#353630}
        </style>
        """
        return html
            .replacingOccurrences(of: "<html lang=\"de\">", with: "<html lang=\"de\" data-app-theme=\"\(theme)\">")
            .replacingOccurrences(of: "</head>", with: "\(override)</head>")
    }
}
