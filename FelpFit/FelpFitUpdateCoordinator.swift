import Foundation

/// Fonte nativa única do estado de atualização web.
/// A pendência só é removida depois de o usuário pedir a aplicação e a WebView
/// confirmar que carregou exatamente a versão alvo.
final class FelpFitUpdateCoordinator {
    static let shared = FelpFitUpdateCoordinator()

    struct PendingUpdate {
        let version: String
        let signature: String
        let applyRequested: Bool
    }

    private enum Key {
        static let pendingVersion = "felpfit.webUpdate.pendingVersion.v2"
        static let pendingSignature = "felpfit.webUpdate.pendingSignature.v2"
        static let applyRequested = "felpfit.webUpdate.applyRequested.v2"
        static let loadedVersion = "felpfit.webUpdate.loadedVersion.v2"
        static let appliedVersion = "felpfit.webUpdate.appliedVersion.v2"
        static let lastNotificationVersion = "felpfit.webUpdate.lastNotificationVersion.v2"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pendingUpdate: PendingUpdate? {
        guard let version = normalizedVersion(defaults.string(forKey: Key.pendingVersion)) else { return nil }
        return PendingUpdate(
            version: version,
            signature: defaults.string(forKey: Key.pendingSignature) ?? "",
            applyRequested: defaults.bool(forKey: Key.applyRequested)
        )
    }

    var loadedVersion: String {
        defaults.string(forKey: Key.loadedVersion) ?? ""
    }

    func requireUpdate(version rawVersion: String, signature: String) {
        guard let version = normalizedVersion(rawVersion) else { return }
        if let pending = pendingUpdate, compareVersions(pending.version, version) == .orderedDescending {
            return
        }

        let isNewTarget = pendingUpdate?.version != version
        defaults.set(version, forKey: Key.pendingVersion)
        defaults.set(signature, forKey: Key.pendingSignature)
        if isNewTarget {
            defaults.set(false, forKey: Key.applyRequested)
        }
    }

    func beginApplying(version: String) -> Bool {
        guard
            let pending = pendingUpdate,
            let version = normalizedVersion(version),
            pending.version == version
        else { return false }
        defaults.set(true, forKey: Key.applyRequested)
        return true
    }

    /// Retorna a atualização concluída somente quando havia aplicação solicitada.
    @discardableResult
    func confirmLoaded(version rawVersion: String) -> PendingUpdate? {
        guard let version = normalizedVersion(rawVersion) else { return nil }
        defaults.set(version, forKey: Key.loadedVersion)

        guard
            let pending = pendingUpdate,
            pending.applyRequested,
            compareVersions(version, pending.version) == .orderedSame
        else {
            if pendingUpdate == nil {
                defaults.set(version, forKey: Key.appliedVersion)
            }
            return nil
        }

        defaults.set(version, forKey: Key.appliedVersion)
        defaults.removeObject(forKey: Key.pendingVersion)
        defaults.removeObject(forKey: Key.pendingSignature)
        defaults.removeObject(forKey: Key.applyRequested)
        return pending
    }

    func shouldNotify(version rawVersion: String) -> Bool {
        guard let version = normalizedVersion(rawVersion) else { return false }
        return defaults.string(forKey: Key.lastNotificationVersion) != version
    }

    func markNotificationScheduled(version rawVersion: String) {
        guard let version = normalizedVersion(rawVersion) else { return }
        defaults.set(version, forKey: Key.lastNotificationVersion)
    }

    func isVersion(_ remote: String, newerThan current: String) -> Bool {
        guard let remote = normalizedVersion(remote), let current = normalizedVersion(current) else { return false }
        return compareVersions(remote, current) == .orderedDescending
    }

    private func normalizedVersion(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        guard !candidate.isEmpty else { return nil }
        let core = candidate.split(separator: "+", maxSplits: 1).first?.split(separator: "-", maxSplits: 1).first ?? ""
        let components = core.split(separator: ".")
        guard !components.isEmpty, components.allSatisfy({ Int($0) != nil }) else { return nil }
        return candidate
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        func numbers(_ value: String) -> [Int] {
            let core = value.split(separator: "+", maxSplits: 1).first?.split(separator: "-", maxSplits: 1).first ?? ""
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }

        let left = numbers(lhs)
        let right = numbers(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }
}

