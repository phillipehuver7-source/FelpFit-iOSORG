import UIKit
import WebKit
import UserNotifications
import CryptoKit

final class FelpFitViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    private static let appURL = URL(string: "https://felpfit.pages.dev/")!
    private static let bridgeName = "felpfitNative"
    private static let nativeBuild = 146
    private static let updateNotificationPrefix = "felpfit.webupdate."
    private static let nativeVersionNotificationIdentifier = "felpfit.native.version.update"

    private enum UpdateDefaults {
        static let lastWebUpdateNotificationToken = "felpfit.webUpdate.lastNotificationToken.v1"
        static let lastNativeVersionNotification = "felpfit.nativeVersion.lastNotification.v1"
        static let lastReleaseNotesSeenVersion = "felpfit.releaseNotes.lastSeen.v1"
    }

    private var pendingNotificationIntent: [String: String]?
    private var didOfferNativePermissions = false
    private var loadedWebAppVersion = ""
    private var webBaselineSignature: String?
    private var webUpdateTimer: Timer?
    private var webUpdateCheckTask: Task<Void, Never>?
    private var isApplyingWebUpdate = false
    private var alertSyncBlockedUntil: Date?

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let controller = configuration.userContentController
        controller.add(WeakScriptMessageHandler(self), name: Self.bridgeName)
        controller.addUserScript(WKUserScript(
            source: FelpFitNativeBridge.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: FelpFitUpdateExperience.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.navigationDelegate = self
        view.uiDelegate = self
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 9 / 255, green: 9 / 255, blue: 14 / 255, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.bounces = false
        view.allowsBackForwardNavigationGestures = true
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 9 / 255, green: 9 / 255, blue: 14 / 255, alpha: 1)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        loadFelpFit()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        webUpdateTimer?.invalidate()
        webUpdateCheckTask?.cancel()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeName)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    private var nativeMarketingVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.5.0"
    }

    private func loadFelpFit(forceRefresh: Bool = false) {
        var url = Self.appURL
        if forceRefresh, var components = URLComponents(url: Self.appURL, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "__ff_native_refresh", value: String(Int(Date().timeIntervalSince1970)))]
            url = components.url ?? Self.appURL
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        webView.load(request)
    }

    @objc private func applicationDidBecomeActive() {
        Task { [weak self] in
            await self?.scheduleNativeVersionNotificationIfNeeded()
        }

        guard webView.url != nil else { return }

        if alertSyncBlockedUntil.map({ Date() >= $0 }) ?? true {
            webView.evaluateJavaScript("window.__felpfitNativeSync && window.__felpfitNativeSync();")
        }

        webUpdateCheckTask?.cancel()
        webUpdateCheckTask = Task { [weak self] in
            _ = await self?.checkForWebUpdate(showCurrentMessage: false)
        }
    }

    @objc private func applicationDidEnterBackground() {
        webUpdateCheckTask?.cancel()
        webUpdateCheckTask = Task { [weak self] in
            _ = await self?.checkForWebUpdate(showCurrentMessage: false)
        }
    }

    private struct RemoteWebSnapshot {
        let signature: String
        let version: String
    }

    private func startWebUpdatePollingIfNeeded() {
        guard webUpdateTimer == nil else { return }
        webUpdateTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            self?.webUpdateCheckTask?.cancel()
            self?.webUpdateCheckTask = Task { [weak self] in
                _ = await self?.checkForWebUpdate(showCurrentMessage: false)
            }
        }
    }

    private func establishWebBaseline() async {
        guard webView.url?.host == Self.appURL.host else { return }
        do {
            let snapshot = try await fetchRemoteWebSnapshot()
            if !loadedWebAppVersion.isEmpty, !snapshot.version.isEmpty, isVersion(snapshot.version, newerThan: loadedWebAppVersion) {
                await scheduleWebUpdateNotificationIfNeeded(snapshot)
                await MainActor.run { [weak self] in
                    self?.sendPayloadToWeb([
                        "type": "webUpdate",
                        "available": true,
                        "remoteVersion": snapshot.version,
                        "currentVersion": self?.loadedWebAppVersion ?? ""
                    ])
                }
                return
            }
            webBaselineSignature = snapshot.signature
            await MainActor.run { [weak self] in
                self?.sendPayloadToWeb(["type": "webUpdate", "available": false])
            }
        } catch {
            // Sem internet ou Cloudflare indisponível: o app continua funcionando com a página já aberta.
        }
    }

    private func checkForWebUpdate(showCurrentMessage: Bool) async -> [String: Any] {
        do {
            let snapshot = try await fetchRemoteWebSnapshot()
            guard let baseline = webBaselineSignature else {
                webBaselineSignature = snapshot.signature
                var result: [String: Any] = ["type": "webUpdate", "available": false]
                if showCurrentMessage { result["message"] = "FelpFit já está na versão mais recente." }
                await MainActor.run { [weak self] in self?.sendPayloadToWeb(result) }
                return result
            }

            let newerVersion = !loadedWebAppVersion.isEmpty && !snapshot.version.isEmpty && isVersion(snapshot.version, newerThan: loadedWebAppVersion)
            let changedOnline = snapshot.signature != baseline
            let available = newerVersion || changedOnline
            var result: [String: Any] = [
                "type": "webUpdate",
                "available": available,
                "remoteVersion": snapshot.version,
                "currentVersion": loadedWebAppVersion
            ]

            if available {
                await scheduleWebUpdateNotificationIfNeeded(snapshot)
            } else if showCurrentMessage {
                result["message"] = "FelpFit já está na versão mais recente."
            }

            await MainActor.run { [weak self] in self?.sendPayloadToWeb(result) }
            return result
        } catch {
            let result: [String: Any] = [
                "type": "webUpdate",
                "available": false,
                "message": showCurrentMessage ? "Não consegui verificar atualização agora." : ""
            ]
            if showCurrentMessage {
                await MainActor.run { [weak self] in self?.sendPayloadToWeb(result) }
            }
            return result
        }
    }

    private func fetchRemoteWebSnapshot() async throws -> RemoteWebSnapshot {
        var components = URLComponents(url: Self.appURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "__ff_native_probe", value: UUID().uuidString)]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let signature: String
        if let etag = http.value(forHTTPHeaderField: "ETag"), !etag.isEmpty {
            signature = "etag:\(etag)"
        } else if let modified = http.value(forHTTPHeaderField: "Last-Modified"), !modified.isEmpty {
            signature = "modified:\(modified)|bytes:\(data.count)"
        } else {
            let digest = SHA256.hash(data: data)
            signature = "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        }

        let html = String(data: data, encoding: .utf8) ?? ""
        let version = Self.extractWebVersion(from: html)
        return RemoteWebSnapshot(signature: signature, version: version)
    }

    private static func extractWebVersion(from html: String) -> String {
        let pattern = #"APP_VERSION\s*=\s*[\"']([^\"']+)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else { return "" }
        return String(html[range])
    }

    private func isVersion(_ remote: String, newerThan current: String) -> Bool {
        let lhs = remote.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private func canUseNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private static func shortDigest(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func scheduleWebUpdateNotificationIfNeeded(_ snapshot: RemoteWebSnapshot) async {
        let token = "\(snapshot.version)|\(snapshot.signature)"
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: UpdateDefaults.lastWebUpdateNotificationToken) != token else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard canUseNotifications(settings.authorizationStatus) else { return }

        let versionLabel = snapshot.version.isEmpty ? "nova versão" : snapshot.version
        let messages: [(String, String)] = [
            ("🚀 FelpFit \(versionLabel) chegou", "Tem novidade pronta. Toque para ver o que mudou e atualizar."),
            ("💜 Atualização nova no FelpFit", "A versão \(versionLabel) já está disponível. Toque para abrir o update."),
            ("⚡ FelpFit ficou melhor", "Tem uma atualização esperando por você. Veja as novidades e atualize."),
            ("🔔 Nova versão disponível", "Seu FelpFit tem update novo. Toque para abrir a atualização."),
            ("🏆 Update \(versionLabel) pronto", "Alertas, progresso e experiência receberam melhorias. Toque para ver."),
            ("✨ Tem novidade no FelpFit", "Uma versão nova acabou de chegar. Toque para descobrir o que mudou.")
        ]
        let index = Int(Self.shortDigest(token).prefix(2), radix: 16).map { $0 % messages.count } ?? 0
        let selected = messages[index]

        let content = UNMutableNotificationContent()
        content.title = selected.0
        content.body = selected.1
        content.sound = .default
        content.userInfo = [
            "felpfitIntent": "webUpdate",
            "remoteVersion": snapshot.version,
            "signature": snapshot.signature
        ]

        let identifier = Self.updateNotificationPrefix + Self.shortDigest(token)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            defaults.set(token, forKey: UpdateDefaults.lastWebUpdateNotificationToken)
        } catch {
            // A interface continua mostrando o update mesmo se o iOS recusar a notificação.
        }
    }

    private func scheduleNativeVersionNotificationIfNeeded() async {
        let defaults = UserDefaults.standard
        let version = nativeMarketingVersion
        guard defaults.string(forKey: UpdateDefaults.lastNativeVersionNotification) != version else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard canUseNotifications(settings.authorizationStatus) else { return }

        let messages: [(String, String)] = [
            ("✅ FelpFit \(version) instalado", "A nova versão já está no seu iPhone. Toque para ver as novidades."),
            ("💜 FelpFit atualizado", "Versão \(version) pronta. Toque para conhecer o que mudou."),
            ("⚡ Update concluído", "O FelpFit \(version) já está rodando. Veja as novidades da versão."),
            ("✨ Versão nova no iPhone", "FelpFit \(version) instalado com sucesso. Toque para abrir.")
        ]
        let token = "native|\(version)"
        let index = Int(Self.shortDigest(token).prefix(2), radix: 16).map { $0 % messages.count } ?? 0
        let selected = messages[index]

        let content = UNMutableNotificationContent()
        content.title = selected.0
        content.body = selected.1
        content.sound = .default
        content.userInfo = [
            "felpfitIntent": "releaseNotes",
            "remoteVersion": version,
            "alreadyUpdated": "true"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.nativeVersionNotificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            defaults.set(version, forKey: UpdateDefaults.lastNativeVersionNotification)
        } catch {
            // Tenta de novo numa próxima ativação caso o iOS ainda não tenha autorizado notificações.
        }
    }

    private func performWebUpdate() {
        guard !isApplyingWebUpdate else { return }
        isApplyingWebUpdate = true
        sendPayloadToWeb(["type": "webUpdate", "available": false, "updating": true, "message": "Atualizando o FelpFit…"])

        let cleanupScript = """
        try {
          if (window.caches) { caches.keys().then(keys => Promise.all(keys.map(key => caches.delete(key)))); }
          if (navigator.serviceWorker) { navigator.serviceWorker.getRegistrations().then(regs => regs.forEach(reg => reg.unregister())); }
        } catch (_) {}
        """
        webView.evaluateJavaScript(cleanupScript)

        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        webView.configuration.websiteDataStore.removeData(ofTypes: cacheTypes, modifiedSince: .distantPast) { [weak self] in
            guard let self else { return }
            self.webBaselineSignature = nil
            self.loadedWebAppVersion = ""
            self.loadFelpFit(forceRefresh: true)
            self.isApplyingWebUpdate = false
        }
    }

    private func showLoadError(_ message: String = "Não foi possível conectar ao FelpFit.") {
        guard presentedViewController == nil else { return }

        let alert = UIAlertController(
            title: "FelpFit",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Tentar novamente", style: .default) { [weak self] _ in
            self?.loadFelpFit()
        })
        present(alert, animated: true)
    }

    private func offerNativePermissionsIfNeeded() {
        guard
            !didOfferNativePermissions,
            FelpFitAlertCoordinator.shared.shouldShowPermissionExplanation,
            presentedViewController == nil
        else { return }

        didOfferNativePermissions = true
        FelpFitAlertCoordinator.shared.markPermissionExplanationShown()

        let alert = UIAlertController(
            title: "Ativar alertas do FelpFit?",
            message: "O FelpFit pode usar notificações nativas e alarmes urgentes do iPhone para tocar nos horários das suas missões. Nos próximos avisos do iOS, toque em Permitir.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Agora não", style: .cancel))
        alert.addAction(UIAlertAction(title: "Ativar", style: .default) { [weak self] _ in
            Task {
                let payload = await FelpFitAlertCoordinator.shared.requestPermissions()
                await self?.scheduleNativeVersionNotificationIfNeeded()
                await MainActor.run {
                    self?.sendPayloadToWeb(payload)
                    self?.webView.evaluateJavaScript("window.__felpfitNativeSync && window.__felpfitNativeSync();")
                }
            }
        })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.__felpfitNativeKick && window.__felpfitNativeKick();")
        applyPendingNotificationIntentIfPossible()
        startWebUpdatePollingIfNeeded()

        Task { [weak self] in
            await self?.scheduleNativeVersionNotificationIfNeeded()
        }

        webUpdateCheckTask?.cancel()
        webUpdateCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            await self?.establishWebBaseline()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.offerNativePermissionsIfNeeded()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if navigationAction.targetFrame == nil {
            webView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }

        if let scheme = url.scheme?.lowercased(), !["http", "https", "about", "data", "blob"].contains(scheme) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        if (error as NSError).code != NSURLErrorCancelled {
            showLoadError()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if (error as NSError).code != NSURLErrorCancelled {
            showLoadError()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: "FelpFit", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: "FelpFit", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: "FelpFit", message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadFelpFit()
    }

    // MARK: - JavaScript <-> Swift bridge

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.name == Self.bridgeName,
            let body = message.body as? [String: Any],
            let command = body["command"] as? String
        else { return }

        Task {
            let payload: [String: Any]

            switch command {
            case "sync":
                if let blockedUntil = alertSyncBlockedUntil, Date() < blockedUntil {
                    payload = await FelpFitAlertCoordinator.shared.getState()
                } else {
                    alertSyncBlockedUntil = nil
                    let rawItems = body["items"] as? [[String: Any]] ?? []
                    let force = (body["force"] as? Bool) ?? false
                    payload = await FelpFitAlertCoordinator.shared.sync(rawItems: rawItems, force: force)
                }

            case "getState":
                payload = await FelpFitAlertCoordinator.shared.getState()

            case "requestPermissions":
                payload = await FelpFitAlertCoordinator.shared.requestPermissions()
                await scheduleNativeVersionNotificationIfNeeded()

            case "toggleMaster":
                payload = await FelpFitAlertCoordinator.shared.setMasterEnabled((body["enabled"] as? Bool) ?? true)

            case "toggleEnabled":
                guard let key = body["key"] as? String else { return }
                payload = await FelpFitAlertCoordinator.shared.setEnabled(key: key, enabled: (body["enabled"] as? Bool) ?? true)

            case "toggleUrgent":
                guard let key = body["key"] as? String else { return }
                payload = await FelpFitAlertCoordinator.shared.setUrgent(key: key, urgent: (body["urgent"] as? Bool) ?? true)

            case "testAlert":
                alertSyncBlockedUntil = Date().addingTimeInterval(45)
                payload = await FelpFitAlertCoordinator.shared.testAlert()

            case "webVersion":
                let version = String(describing: body["version"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run { [weak self] in self?.loadedWebAppVersion = version }
                payload = ["type": "webVersion", "version": version, "nativeBuild": Self.nativeBuild]

            case "checkWebUpdate":
                payload = await checkForWebUpdate(showCurrentMessage: true)

            case "applyWebUpdate":
                let version = String(describing: body["version"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !version.isEmpty {
                    UserDefaults.standard.set(version, forKey: UpdateDefaults.lastReleaseNotesSeenVersion)
                }
                await MainActor.run { [weak self] in self?.performWebUpdate() }
                payload = ["type": "webUpdate", "available": false, "updating": true]

            case "markReleaseNotesSeen":
                let version = String(describing: body["version"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !version.isEmpty {
                    UserDefaults.standard.set(version, forKey: UpdateDefaults.lastReleaseNotesSeenVersion)
                }
                payload = ["type": "releaseNotesSeen", "version": version]

            case "getCapabilities":
                payload = [
                    "type": "capabilities",
                    "nativeBuild": Self.nativeBuild,
                    "capabilities": [
                        "alerts-v1",
                        "alarmkit-v1",
                        "web-update-v1",
                        "remote-alert-sync-v1",
                        "update-notifications-v1",
                        "release-notes-v1"
                    ]
                ]

            default:
                return
            }

            await MainActor.run { [weak self] in
                self?.sendPayloadToWeb(payload)
            }
        }
    }

    private func sendPayloadToWeb(_ payload: [String: Any]) {
        guard
            JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else { return }

        webView.evaluateJavaScript("window.__felpfitNativeReceive && window.__felpfitNativeReceive(\(json));")
    }

    // MARK: - Native notification behavior

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let felpfitIntent = (info["felpfitIntent"] as? String) ?? ""

        if felpfitIntent == "webUpdate" {
            let remoteVersion = (info["remoteVersion"] as? String) ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.pendingNotificationIntent = [
                    "kind": "webUpdate",
                    "remoteVersion": remoteVersion
                ]
                self?.applyPendingNotificationIntentIfPossible()
            }
            completionHandler()
            return
        }

        if felpfitIntent == "releaseNotes" {
            let remoteVersion = (info["remoteVersion"] as? String) ?? nativeMarketingVersion
            DispatchQueue.main.async { [weak self] in
                self?.pendingNotificationIntent = [
                    "kind": "releaseNotes",
                    "remoteVersion": remoteVersion
                ]
                self?.applyPendingNotificationIntentIfPossible()
            }
            completionHandler()
            return
        }

        let questionID = (info["questionID"] as? String) ?? ""
        let storedDateKey = (info["dateKey"] as? String) ?? ""
        let calendarDate = (info["calendarDate"] as? String) ?? ""
        let intent: [String: String] = [
            "questionID": questionID,
            "dateKey": storedDateKey.isEmpty ? Self.todayKey() : storedDateKey,
            "calendarDate": calendarDate
        ]

        DispatchQueue.main.async { [weak self] in
            self?.pendingNotificationIntent = intent
            self?.applyPendingNotificationIntentIfPossible()
        }
        completionHandler()
    }

    private func applyPendingNotificationIntentIfPossible() {
        guard let intent = pendingNotificationIntent, webView.url != nil else { return }

        if intent["kind"] == "webUpdate" {
            sendPayloadToWeb([
                "type": "webUpdate",
                "available": true,
                "remoteVersion": intent["remoteVersion"] ?? "",
                "currentVersion": loadedWebAppVersion,
                "openedFromNotification": true,
                "forceReleaseNotes": true
            ])
            pendingNotificationIntent = nil
            return
        }

        if intent["kind"] == "releaseNotes" {
            sendPayloadToWeb([
                "type": "showReleaseNotes",
                "version": intent["remoteVersion"] ?? nativeMarketingVersion,
                "alreadyUpdated": true,
                "openedFromNotification": true
            ])
            pendingNotificationIntent = nil
            return
        }

        if let calendarDate = intent["calendarDate"], !calendarDate.isEmpty {
            navigateWebApp(queryItems: [URLQueryItem(name: "calendarDate", value: calendarDate)])
            pendingNotificationIntent = nil
            return
        }

        if let questionID = intent["questionID"], !questionID.isEmpty {
            navigateWebApp(queryItems: [
                URLQueryItem(name: "question", value: questionID),
                URLQueryItem(name: "date", value: intent["dateKey"] ?? Self.todayKey())
            ])
            pendingNotificationIntent = nil
        }
    }

    private func navigateWebApp(queryItems: [URLQueryItem]) {
        var components = URLComponents(url: Self.appURL, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        webView.load(request)
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
