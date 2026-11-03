import SwiftUI
import WebKit

struct BEaconAction: Hashable, Decodable {
    let label: String
    let action: String
    let disabled: Bool
}

/// One robot's BEacon page. Restyles it in 5x1 colours, hides its own header and tabs (the app
/// draws glass ones), and reports its title, tab and toolbar buttons back to SwiftUI. Also
/// provides what Safari otherwise would: alert/confirm/prompt dialogs, outside links in Safari,
/// and downloads handed to the share sheet. File uploads work as-is.
final class BEacon: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate, WKScriptMessageHandler {
    @Published var title = ""
    @Published var panel = ""
    @Published var actions: [BEaconAction] = []
    @Published var loaded = false
    let robot: Robot
    let web: WKWebView
    private var downloads: [ObjectIdentifier: URL] = [:]
    private var usingRemote = false

    init(robot: Robot) {
        self.robot = robot
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(source: Self.theme, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(
            WKUserScript(source: Self.bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.addUserScript(
            WKUserScript(source: Self.iPhoneSettings, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(WeakHandler(self), name: "beep")
        config.userContentController.add(WeakHandler(self), name: "beepSettings")
        web.uiDelegate = self
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = UIColor(named: "LaunchBackground")
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in
            self?.reload()
            self?.web.scrollView.refreshControl?.endRefreshing()
        }, for: .valueChanged)
        web.scrollView.refreshControl = refresh
        web.load(localRequest)
        Task { await Companion.shared.sync(robot) }
    }

    func show(_ panel: String) { call("tab", panel) }
    func perform(_ action: BEaconAction) { call("act", action.action) }

    /// The "can't reach" page isn't BEacon, so retry BEacon itself (on Wi-Fi first).
    func reload() {
        if isBEacon(web.url) { web.reload() } else { usingRemote = false; web.load(localRequest) }
    }

    /// Away from home the Wi-Fi address may never answer, so with a remote address to try, give up on it sooner.
    private var localRequest: URLRequest {
        URLRequest(url: robot.url, timeoutInterval: robot.remoteURL == nil ? 60 : 6)
    }

    private func isBEacon(_ url: URL?) -> Bool {
        url?.host != nil && (url?.host == robot.host || url?.host == robot.remoteURL?.host)
    }

    private func call(_ function: String, _ argument: String) {
        guard let data = try? JSONEncoder().encode(argument), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__beep && window.__beep.\(function)(\(json))")
    }

    // MARK: Page state

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "beepSettings" {
            guard let text = message.body as? String,
                  let wanted = try? JSONDecoder().decode(Companion.Settings.self, from: Data(text.utf8)) else { return }
            Task {
                let (now, problem) = await Companion.shared.update(wanted, for: robot)
                await showSettings(now, problem)
            }
            return
        }
        struct State: Decodable { let title: String; let panel: String; let actions: [BEaconAction] }
        guard let text = message.body as? String, let state = try? JSONDecoder().decode(State.self, from: Data(text.utf8)) else { return }
        title = state.title
        panel = state.panel
        actions = state.actions
        if !loaded, let start = UserDefaults.standard.string(forKey: "BEepPanel") { show(start) } // simulator check
        loaded = true
    }

    /// Fills in the "On this iPhone" settings that the page script adds to BEacon's Settings.
    @MainActor
    func showSettings(_ settings: Companion.Settings, _ problem: String?) {
        guard let data = try? JSONEncoder().encode(settings), let json = String(data: data, encoding: .utf8),
              let note = try? JSONEncoder().encode(problem ?? ""), let noteJSON = String(data: note, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__beepSettings && window.__beepSettings(\(json), \(noteJSON))")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            let settings = await Companion.shared.settings(for: robot)
            await showSettings(settings, nil)
        }
    }

    // MARK: Dialogs

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, orElse: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        present(alert) { completionHandler(nil) }
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
        if let url = action.request.url, !isBEacon(url), action.navigationType == .linkActivated {
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
        if !usingRemote, let remote = robot.remoteURL {
            usingRemote = true
            webView.load(URLRequest(url: remote))
            return
        }
        loaded = false
        title = ""
        actions = []
        let page = """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <body style="font: -apple-system-body; text-align: center; padding: 120px 24px; color: #b0bbb2; background: #111513">
        <h3 style="color: #eef1ec">Can't reach \(robot.name)</h3>
        <p>Make sure Jibo is on and your phone is on the same Wi-Fi\(robot.remoteURL == nil ? "" : ", or that his remote address works"), then pull down to try again.</p>
        </body>
        """
        webView.loadHTMLString(page, baseURL: nil)
    }

    // MARK: Downloads

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
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
        guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = web
        share.popoverPresentationController?.sourceRect = CGRect(x: web.bounds.midX, y: web.bounds.midY, width: 0, height: 0)
        present(share, orElse: {})
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
    }

    // MARK: Helpers

    /// WebKit requires every dialog's completion handler to be called, so fall back if
    /// there's no screen to show it on (the view was closed).
    private func present(_ controller: UIViewController, orElse fallback: @escaping () -> Void) {
        guard var top = web.window?.rootViewController else { return fallback() }
        while let next = top.presentedViewController { top = next }
        top.present(controller, animated: true)
    }

    // MARK: Scripts

    /// 5x1 colours (5x1.com) over BEacon's own variables, always dark. `html:root` outranks
    /// BEacon's `:root` rules, which load after this.
    private static let theme = """
    (function () {
      try { localStorage.setItem('beacon-appearance', 'dark'); } catch (e) {}
      var colours = '--pearl:#111513;--bg:#111513;--bg-soft:#111513;--bg-card:#18201b;--steel:#b0bbb2;--muted:#b0bbb2;' +
        '--light-grey:#303b33;--line:#303b33;--line-solid:#303b33;--text:#eef1ec;--toolbar-bg:#161c18;' +
        '--jibo-blue:#29d780;--accent-blue:#1fa866;--charlotte:#a8f0c8;--hover:#1d2a22;--surface-hover:#1a2a20;' +
        '--progress-track:#2a352d;--none-banner:#1d2620;--banner-start:#1c2b22;--banner-end:#1f3d2c;' +
        '--readme-link:#6fe3a6;--role-line:#2c6b4a;--accent-dim:rgba(41,215,128,.14);--store-link:#9fe0bd;--store-muted:#b0bbb2;';
      // Liquid Glass: translucent, blurred surfaces with a light edge, over soft 5x1 glows.
      var glass = 'background: rgba(30,44,35,.5) !important; -webkit-backdrop-filter: blur(22px) saturate(170%); backdrop-filter: blur(22px) saturate(170%);' +
        'border: 1px solid rgba(255,255,255,.1) !important; box-shadow: inset 0 1px 0 rgba(255,255,255,.08), 0 10px 30px rgba(0,0,0,.25) !important';
      var surfaces = '.card, .stat, .setting-row, .setting-block, .photo-card, .empty, .skill, .store-card, .store-switch, .store-options-menu,' +
        ' .store-options-button, .theme-details-card, .modal-box, .toast, .store-safety-note, .menu-editor, .menu-folder-edit';
      var lighter = '.btn:not(.btn-primary):not(.btn-danger):not(.store-details), .form-row input, .form-row select, select, input[type=text], input[type=url], textarea';
      var style = document.createElement('style');
      style.textContent = 'html:root, html:root[data-appearance="dark"] {' + colours + 'color-scheme: dark}' +
        '.toolbar, .bottom-nav { display: none !important }' +
        'body { background: #111513; padding-bottom: calc(96px + env(safe-area-inset-bottom, 0px)) !important }' +
        '.btn-primary, .btn-primary:hover, .btn-primary:active { color: #0d2015 !important }' +
        'body { background: radial-gradient(60% 40% at 10% 0%, #1c3023 0%, transparent 70%), radial-gradient(50% 35% at 100% 55%, #17291e 0%, transparent 70%), #111513 fixed !important }' +
        surfaces + ' {' + glass + '}' +
        '.store-card-content, .store-options-menu button { background: transparent !important }' +
        lighter + ' { background: rgba(255,255,255,.06) !important; border: 1px solid rgba(255,255,255,.12) !important;' +
        ' -webkit-backdrop-filter: blur(16px); backdrop-filter: blur(16px) }' +
        '.btn-primary { box-shadow: inset 0 1px 0 rgba(255,255,255,.35), 0 6px 18px rgba(41,215,128,.25) !important }' +
        // The Store draws its buttons, switch and progress in fixed blues.
        '.store-switch-slider, .store-card .store-apply, .store-card .store-install { background: #29d780 !important; border-color: #29d780 !important; color: #0d2015 !important }' +
        '.store-card .store-install:hover:not(:disabled) { background: #1fa866 !important; border-color: #1fa866 !important }' +
        '.store-switch-tab[aria-selected="true"], .store-switch-tab[aria-checked="true"] { color: #0d2015 !important }' +
        '.store-switch-tab:focus-visible { outline-color: #29d780 !important }' +
        '.theme-download-progress progress { accent-color: #29d780 !important }' +
        '.theme-download-progress progress::-webkit-progress-value { background: #29d780 !important }' +
        'a:not(.btn) { color: #6fe3a6 }' +
        // Store: Details is a text link, and its popup sits between BEep's bars on a frosted backdrop.
        '.store-card .store-details { background: rgba(255,255,255,.06) !important; border: 1px solid rgba(255,255,255,.12) !important;' +
        ' -webkit-backdrop-filter: blur(16px); backdrop-filter: blur(16px); color: #6fe3a6 !important; padding: 9px 26px !important; border-radius: 10px; font-weight: 600 }' +
        '.theme-details { background: rgba(5,10,7,.55) !important; -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);' +
        ' padding: calc(env(safe-area-inset-top, 0px) + 64px) 16px calc(env(safe-area-inset-bottom, 0px) + 100px) !important }' +
        '.theme-details .theme-details-card { background: rgba(22,31,25,.92) !important }';
      document.documentElement.appendChild(style);
    })();
    """

    /// Adds "On this iPhone" to BEacon's Settings (app only). Values come from and go to Companion.
    private static let iPhoneSettings = """
    (function () {
      var panel = document.getElementById('panel-etc');
      if (!panel) return;
      var wrap = document.createElement('div');
      wrap.innerHTML = '<p class="section-header">On this iPhone</p><div class="setting-block">' +
        '<label class="unit-choice"><input type="checkbox" data-beep="savePhotos"><span>Save Jibo’s new photos to this iPhone</span></label>' +
        '<label class="unit-choice"><input type="checkbox" data-beep="lowBattery"><span>Notify me when Jibo’s battery is low</span></label>' +
        '<p class="hint" id="beep-battery-hint" hidden>This Jibo needs a newer BEam to report his battery.</p>' +
        '<div class="form-row"><label for="beep-member">This iPhone belongs to</label>' +
        '<select id="beep-member" data-beep="member"><option value="">Nobody chosen</option></select></div>' +
        '<p class="hint">So Jibo can tell you this phone’s battery when you ask “How is my phone’s battery?”</p>' +
        '<label class="unit-choice"><input type="checkbox" data-beep="calendar"><span>Send this iPhone’s calendar for my personal report</span></label>' +
        '<p class="hint">Sends the next week of events from this iPhone in place of your calendar link.</p>' +
        '<p class="hint">These work while BEep is open and when your iPhone lets it refresh in the background, so they can lag a little.</p>' +
        '<p class="hint" id="beep-settings-status" role="status"></p></div>';
      panel.insertBefore(wrap, panel.firstChild);
      var inputs = wrap.querySelectorAll('[data-beep]'), selects = wrap.querySelectorAll('select[data-beep]'), chosen = {};
      function send() {
        var settings = {};
        [].forEach.call(inputs, function (input) {
          settings[input.getAttribute('data-beep')] = input.type === 'checkbox' ? input.checked : input.value;
        });
        wrap.querySelector('#beep-settings-status').textContent = 'Saving…';
        window.webkit.messageHandlers.beepSettings.postMessage(JSON.stringify(settings));
      }
      [].forEach.call(inputs, function (input) { input.addEventListener('change', send); });
      window.__beepSettings = function (settings, problem) {
        wrap.querySelector('[data-beep="savePhotos"]').checked = settings.savePhotos;
        wrap.querySelector('[data-beep="lowBattery"]').checked = settings.lowBattery;
        wrap.querySelector('[data-beep="calendar"]').checked = settings.calendar;
        chosen = { member: settings.member };
        [].forEach.call(selects, function (s) { s.value = chosen[s.getAttribute('data-beep')]; });
        wrap.querySelector('#beep-settings-status').textContent = problem;
      };
      fetch('/api/people').then(function (r) { return r.json(); }).then(function (data) {
        [].forEach.call(selects, function (select) {
          (data.members || []).forEach(function (m) {
            if (m.isJibo) return;
            var option = document.createElement('option');
            option.value = m.id;
            option.textContent = [m.firstName, m.lastName].filter(Boolean).join(' ') || m.writtenName || 'Someone';
            select.appendChild(option);
          });
          select.value = chosen[select.getAttribute('data-beep')] || '';
        });
      }).catch(function () {});
      fetch('/api/status').then(function (r) { return r.json(); }).then(function (status) {
        if ('battery' in status) return;
        wrap.querySelector('[data-beep="lowBattery"]').disabled = true;
        wrap.querySelector('#beep-battery-hint').hidden = false;
      }).catch(function () {});
    })();
    """

    /// Reports BEacon's title, active tab and toolbar buttons whenever they change, and lets the
    /// app press its (hidden) tabs and toolbar buttons.
    private static let bridge = """
    (function () {
      var last = '', queued = false;
      function state() {
        var title = document.getElementById('toolbar-title');
        var tab = document.querySelector('.tab.is-active');
        return JSON.stringify({
          title: title ? title.textContent.trim() : '',
          panel: tab ? tab.getAttribute('data-panel') : '',
          actions: [].map.call(document.querySelectorAll('#toolbar-actions .toolbar-action'), function (b) {
            return { label: b.textContent.trim(), action: b.getAttribute('data-action') || '', disabled: !!b.disabled };
          })
        });
      }
      function send() {
        if (queued) return;
        queued = true;
        setTimeout(function () {
          queued = false;
          var next = state();
          if (next !== last) { last = next; window.webkit.messageHandlers.beep.postMessage(next); }
        }, 50);
      }
      window.__beep = {
        tab: function (name) { var t = document.querySelector('.tab[data-panel="' + name + '"]'); if (t) t.click(); },
        act: function (name) { var b = document.querySelector('#toolbar-actions [data-action="' + name + '"]'); if (b) b.click(); }
      };
      new MutationObserver(send).observe(document.documentElement, {
        subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['class', 'disabled']
      });
      send();
    })();
    """
}

/// WKUserContentController keeps its handlers alive; this stops it keeping the page (and its
/// screen stream) alive after you leave the robot.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
