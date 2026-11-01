import SwiftUI
import WebKit

/// BEacon in a web view, with what Safari would otherwise provide: alert/confirm/prompt dialogs,
/// outside links in Safari, and downloads handed to the share sheet (Save Image, Files, …).
/// File uploads work as-is.
struct BEaconView: UIViewRepresentable {
    let robot: Robot

    func makeCoordinator() -> Coordinator { Coordinator(robot: robot) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.uiDelegate = context.coordinator
        web.navigationDelegate = context.coordinator
        let refresh = UIRefreshControl()
        let home = robot.url
        refresh.addAction(UIAction { [weak web] _ in
            // The "can't reach" page has no robot URL, so retry BEacon itself.
            if web?.url?.host == home.host { web?.reload() } else { web?.load(URLRequest(url: home)) }
            web?.scrollView.refreshControl?.endRefreshing()
        }, for: .valueChanged)
        web.scrollView.refreshControl = refresh
        web.load(URLRequest(url: robot.url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
        let robot: Robot
        private var downloads: [ObjectIdentifier: URL] = [:]
        private weak var web: WKWebView?

        init(robot: Robot) { self.robot = robot }

        // MARK: Dialogs

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(alert, from: webView, orElse: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(alert, from: webView) { completionHandler(false) }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            present(alert, from: webView) { completionHandler(nil) }
        }

        // MARK: Links

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { UIApplication.shared.open(url) } // target="_blank"
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.shouldPerformDownload { return decisionHandler(.download) }
            if let url = action.request.url, url.host != robot.host, action.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
            let attachment = disposition.lowercased().hasPrefix("attachment")
            decisionHandler(attachment || !response.canShowMIMEType ? .download : .allow)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let page = """
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <body style="font: -apple-system-body; text-align: center; padding: 40px 24px; color: #555">
            <h3>Can't reach \(robot.name)</h3>
            <p>Make sure Jibo is on and your phone is on the same Wi-Fi, then pull down to try again.</p>
            </body>
            """
            webView.loadHTMLString(page, baseURL: nil)
        }

        // MARK: Downloads

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            self.web = webView
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            self.web = webView
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(suggestedFilename)
            downloads[ObjectIdentifier(download)] = file
            completionHandler(file)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)), let web else { return }
            let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = web
            share.popoverPresentationController?.sourceRect = CGRect(x: web.bounds.midX, y: web.bounds.midY, width: 0, height: 0)
            present(share, from: web, orElse: {})
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloads.removeValue(forKey: ObjectIdentifier(download))
        }

        // MARK: Helpers

        /// WebKit requires every dialog's completion handler to be called, so fall back if
        /// there's no screen to show it on (the view was closed).
        private func present(_ controller: UIViewController, from view: UIView, orElse fallback: @escaping () -> Void) {
            guard var top = view.window?.rootViewController else { return fallback() }
            while let next = top.presentedViewController { top = next }
            top.present(controller, animated: true)
        }
    }
}
