import Foundation
import UserNotifications

#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

struct FelpFitScheduleItem: Hashable, Codable {
    enum Kind: String, Codable {
        case weekly
        case fixed
    }

    let key: String
    let preferenceKey: String
    let title: String
    let body: String
    let kind: Kind
    let hour: Int
    let minute: Int
    let weekdays: [Int]
    let fireAtMilliseconds: Double?
    let questionID: String?
    let dateKey: String?
    let calendarDate: String?
    let category: String
    let defaultUrgent: Bool?

    init?(dictionary: [String: Any]) {
        guard
            let key = dictionary["key"] as? String,
            !key.isEmpty,
            let title = dictionary["title"] as? String,
            let kindRaw = dictionary["kind"] as? String,
            let kind = Kind(rawValue: kindRaw)
        else { return nil }

        self.key = key
        self.preferenceKey = (dictionary["preferenceKey"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
        self.title = title
        self.body = (dictionary["body"] as? String) ?? "Abra o FelpFit para responder."
        self.kind = kind
        self.hour = (dictionary["hour"] as? NSNumber)?.intValue ?? 0
        self.minute = (dictionary["minute"] as? NSNumber)?.intValue ?? 0
        self.weekdays = (dictionary["weekdays"] as? [NSNumber])?.map(\.intValue) ?? []
        self.fireAtMilliseconds = (dictionary["fireAtMs"] as? NSNumber)?.doubleValue
        self.questionID = dictionary["questionID"] as? String
        self.dateKey = dictionary["dateKey"] as? String
        self.calendarDate = dictionary["calendarDate"] as? String
        self.category = (dictionary["category"] as? String) ?? "mission"
        self.defaultUrgent = (dictionary["defaultUrgent"] as? Bool) ?? (self.category == "mission")
    }

    var fireDate: Date? {
        guard let fireAtMilliseconds else { return nil }
        return Date(timeIntervalSince1970: fireAtMilliseconds / 1000)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct FelpFitAlarmMetadata: AlarmMetadata {
    let key: String
    let questionID: String?
    let dateKey: String?
}
#endif

final class FelpFitAlertCoordinator {
    static let shared = FelpFitAlertCoordinator()
    private static let testNotificationPrefix = "felpfit.native.test."

    private enum DefaultsKey {
        static let masterEnabled = "felpfit.nativeAlerts.masterEnabled.v1"
        static let enabledByKey = "felpfit.nativeAlerts.enabledByKey.v1"
        static let urgentByKey = "felpfit.nativeAlerts.urgentByKey.v1"
        static let alarmIDs = "felpfit.nativeAlerts.alarmIDs.v1"
        static let scheduleFingerprint = "felpfit.nativeAlerts.scheduleFingerprint.v3"
        static let explanationShown = "felpfit.nativeAlerts.explanationShown.v1"
        static let currentItems = "felpfit.nativeAlerts.currentItems.v2"
    }

    private let defaults = UserDefaults.standard
    private let notificationCenter = UNUserNotificationCenter.current()
    private(set) var currentItems: [FelpFitScheduleItem] = []
    private var lastFallbackCount = 0
    private var lastScheduledAlarmCount = 0
    private var lastScheduledNotificationCount = 0
    private var lastScheduleErrors: [String] = []

    private init() {
        guard
            let data = defaults.data(forKey: DefaultsKey.currentItems),
            let items = try? JSONDecoder().decode([FelpFitScheduleItem].self, from: data)
        else { return }
        currentItems = items
    }

    var shouldShowPermissionExplanation: Bool {
        !defaults.bool(forKey: DefaultsKey.explanationShown)
    }

    func markPermissionExplanationShown() {
        defaults.set(true, forKey: DefaultsKey.explanationShown)
    }

    private var masterEnabled: Bool {
        get {
            if defaults.object(forKey: DefaultsKey.masterEnabled) == nil { return true }
            return defaults.bool(forKey: DefaultsKey.masterEnabled)
        }
        set { defaults.set(newValue, forKey: DefaultsKey.masterEnabled) }
    }

    private var enabledByKey: [String: Bool] {
        get { defaults.dictionary(forKey: DefaultsKey.enabledByKey) as? [String: Bool] ?? [:] }
        set { defaults.set(newValue, forKey: DefaultsKey.enabledByKey) }
    }

    private var urgentByKey: [String: Bool] {
        get { defaults.dictionary(forKey: DefaultsKey.urgentByKey) as? [String: Bool] ?? [:] }
        set { defaults.set(newValue, forKey: DefaultsKey.urgentByKey) }
    }

    private var alarmIDs: [String: String] {
        get { defaults.dictionary(forKey: DefaultsKey.alarmIDs) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: DefaultsKey.alarmIDs) }
    }

    private func isEnabled(_ key: String) -> Bool {
        enabledByKey[key] ?? true
    }

    private func isUrgent(_ item: FelpFitScheduleItem) -> Bool {
        urgentByKey[item.preferenceKey] ?? item.defaultUrgent ?? (item.category == "mission")
    }

    func getState() async -> [String: Any] {
        await stateDictionary()
    }

    func requestPermissions() async -> [String: Any] {
        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // AlarmKit may still work even when regular notifications are denied.
        }

        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
        #endif

        await rescheduleAll(force: true)
        return await stateDictionary(message: "Permissões atualizadas.")
    }

    func sync(rawItems: [[String: Any]], force: Bool = false) async -> [String: Any] {
        var seen = Set<String>()
        currentItems = rawItems.compactMap(FelpFitScheduleItem.init(dictionary:)).filter { item in
            guard !seen.contains(item.key) else { return false }
            seen.insert(item.key)
            if item.kind == .fixed, let date = item.fireDate {
                return date > Date().addingTimeInterval(3)
            }
            return true
        }
        persistCurrentItems()

        await rescheduleAll(force: force)
        return await stateDictionary()
    }

    func setMasterEnabled(_ enabled: Bool) async -> [String: Any] {
        masterEnabled = enabled
        defaults.removeObject(forKey: DefaultsKey.scheduleFingerprint)
        await rescheduleAll(force: true)
        return await stateDictionary(message: enabled ? "Alertas ativados." : "Alertas pausados neste aparelho.")
    }

    func setEnabled(key: String, enabled: Bool) async -> [String: Any] {
        var values = enabledByKey
        values[key] = enabled
        enabledByKey = values
        defaults.removeObject(forKey: DefaultsKey.scheduleFingerprint)
        await rescheduleAll(force: true)
        return await stateDictionary(message: enabled ? "Aviso ativado." : "Aviso desativado.")
    }

    func setUrgent(key: String, urgent: Bool) async -> [String: Any] {
        var values = urgentByKey
        values[key] = urgent
        urgentByKey = values
        defaults.removeObject(forKey: DefaultsKey.scheduleFingerprint)
        await rescheduleAll(force: true)
        return await stateDictionary(message: urgent ? "Alarme ativado; a notificação continua como abertura rápida." : "Este aviso agora usa somente notificação normal.")
    }

    func testAlert() async -> [String: Any] {
        let notificationSettings = await notificationCenter.notificationSettings()
        let alarmStatus = alarmAuthorizationStatus()

        if alarmStatus == "notDetermined" || notificationSettings.authorizationStatus == .notDetermined {
            _ = await requestPermissions()
        }

        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
            let test = FelpFitScheduleItem(
                key: "__felpfit_test_alarm__",
                preferenceKey: "__felpfit_test_alarm__",
                title: "FelpFit • teste de alarme",
                body: "Se você está ouvindo isso, o AlarmKit está funcionando.",
                kind: .fixed,
                hour: 0,
                minute: 0,
                weekdays: [],
                fireAtMilliseconds: Date().addingTimeInterval(30).timeIntervalSince1970 * 1000,
                questionID: nil,
                dateKey: nil,
                calendarDate: nil,
                category: "test"
            )
            do {
                let refreshedSettings = await notificationCenter.notificationSettings()
                var notificationScheduled = false
                var verifiedPending = false
                if canUseNotifications(refreshedSettings.authorizationStatus) {
                    let content = UNMutableNotificationContent()
                    content.title = "FelpFit • teste combinado"
                    content.body = "A notificação chegou primeiro. O alarme tocará em 10 segundos."
                    content.sound = .default
                    content.categoryIdentifier = "FELPFIT_REMINDER"
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 20, repeats: false)
                    let identifier = Self.testNotificationPrefix + UUID().uuidString
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    do {
                        try await notificationCenter.add(request)
                        notificationScheduled = true
                        verifiedPending = await notificationCenter.pendingNotificationRequests().contains {
                            $0.identifier == identifier
                        }
                    } catch {
                        lastScheduleErrors.append("\(request.identifier): \(error.localizedDescription)")
                    }
                }
                try await scheduleAlarmKit(test, explicitID: testAlarmID())
                return await stateDictionary(message: notificationScheduled && verifiedPending
                    ? "Teste confirmado pelo iPhone: notificação em 20 segundos e alarme 10 segundos depois."
                    : "Teste urgente agendado para daqui a 30 segundos; notificações normais não estão autorizadas.")
            } catch {
                // If AlarmKit cannot schedule, fall through to regular notification.
            }
        }
        #endif

        let settings = await notificationCenter.notificationSettings()
        if canUseNotifications(settings.authorizationStatus) {
            let content = UNMutableNotificationContent()
            content.title = "FelpFit • teste"
            content.body = "Notificação nativa funcionando."
            content.sound = .default
            content.categoryIdentifier = "FELPFIT_REMINDER"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
            let identifier = Self.testNotificationPrefix + UUID().uuidString
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            do {
                try await notificationCenter.add(request)
                let verified = await notificationCenter.pendingNotificationRequests().contains {
                    $0.identifier == identifier
                }
                return await stateDictionary(message: verified
                    ? "Teste de notificação confirmado pelo iPhone para daqui a 30 segundos."
                    : "O iPhone aceitou o pedido, mas ele não apareceu na fila de notificações.")
            } catch {
                lastScheduleErrors.append("\(request.identifier): \(error.localizedDescription)")
                return await stateDictionary(message: "O iPhone recusou o teste de notificação: \(error.localizedDescription)")
            }
        }

        return await stateDictionary(message: "O iPhone ainda não autorizou alarmes nem notificações.")
    }

    private func rescheduleAll(force: Bool) async {
        let notificationSettings = await notificationCenter.notificationSettings()
        let alarmStatus = alarmAuthorizationStatus()
        let fingerprint = makeFingerprint(notificationStatus: notificationSettings.authorizationStatus.rawValue, alarmStatus: alarmStatus)

        if !force, defaults.string(forKey: DefaultsKey.scheduleFingerprint) == fingerprint {
            return
        }

        lastFallbackCount = 0
        lastScheduledAlarmCount = 0
        lastScheduledNotificationCount = 0
        lastScheduleErrors = []

        // Remove somente os lembretes gerenciados pela agenda. Notificações de
        // update e o teste de 30 segundos pertencem a fluxos independentes e
        // não podem ser cancelados por uma sincronização automática.
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let managedIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { identifier in
                identifier.hasPrefix("felpfit.native.") && !identifier.hasPrefix(Self.testNotificationPrefix)
            }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: managedIdentifiers)
        cancelKnownAlarmKitAlarms()

        guard masterEnabled else {
            defaults.set(fingerprint, forKey: DefaultsKey.scheduleFingerprint)
            return
        }

        let orderedItems = currentItems.sorted { left, right in
            let priority: [String: Int] = ["mission": 0, "hydration": 1, "calendar": 2]
            let lp = priority[left.category] ?? 3
            let rp = priority[right.category] ?? 3
            if lp != rp { return lp < rp }
            if left.hour != right.hour { return left.hour < right.hour }
            return left.minute < right.minute
        }

        for item in orderedItems where isEnabled(item.preferenceKey) {
            if isUrgent(item) {
                var didScheduleUrgent = false
                #if canImport(AlarmKit)
                if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
                    do {
                        try await scheduleAlarmKit(item)
                        didScheduleUrgent = true
                        lastScheduledAlarmCount += 1
                    } catch {
                        // AlarmKit has a system maximum. Falling back keeps the reminder alive.
                    }
                }
                #endif

                if canUseNotifications(notificationSettings.authorizationStatus) {
                    // Quando o AlarmKit estiver ativo, a notificação chega dez
                    // segundos antes e serve como atalho para a tarefa. Se o
                    // alarme não puder ser criado, o aviso fica no horário exato.
                    let count = await scheduleLocalNotification(item, leadSeconds: didScheduleUrgent ? 10 : 0)
                    if !didScheduleUrgent, count > 0 { lastFallbackCount += 1 }
                    lastScheduledNotificationCount += count
                }
            } else if canUseNotifications(notificationSettings.authorizationStatus) {
                lastScheduledNotificationCount += await scheduleLocalNotification(item)
            }
        }

        defaults.set(fingerprint, forKey: DefaultsKey.scheduleFingerprint)
    }

    private func pendingNotificationIdentifiers() -> [String] {
        currentItems.map { notificationIdentifier(for: $0.key) }
    }

    private func notificationIdentifier(for key: String) -> String {
        "felpfit.native.\(key)"
    }

    @discardableResult
    private func scheduleLocalNotification(_ item: FelpFitScheduleItem, leadSeconds: Int = 0) async -> Int {
        let makeContent: () -> UNMutableNotificationContent = {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = item.category == "hydration"
                ? "FELPFIT_HYDRATION"
                : "FELPFIT_REMINDER"
            content.threadIdentifier = "felpfit.\(item.category)"
            content.userInfo = [
                "scheduleKey": item.key,
                "questionID": item.questionID ?? "",
                "dateKey": item.dateKey ?? "",
                "calendarDate": item.calendarDate ?? ""
            ]
            return content
        }

        switch item.kind {
        case .weekly:
            var scheduled = 0
            for weekday in item.weekdays {
                var adjustedWeekday = weekday
                var adjustedSeconds = item.hour * 3_600 + item.minute * 60 - max(0, leadSeconds)
                if adjustedSeconds < 0 {
                    adjustedSeconds += 24 * 3_600
                    adjustedWeekday = weekday == 1 ? 7 : weekday - 1
                }
                var components = DateComponents()
                components.hour = adjustedSeconds / 3_600
                components.minute = (adjustedSeconds % 3_600) / 60
                components.second = adjustedSeconds % 60
                components.weekday = adjustedWeekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(notificationIdentifier(for: item.key)).w\(weekday)",
                    content: makeContent(),
                    trigger: trigger
                )
                do {
                    try await notificationCenter.add(request)
                    scheduled += 1
                } catch {
                    lastScheduleErrors.append("\(request.identifier): \(error.localizedDescription)")
                }
            }
            return scheduled
        case .fixed:
            guard let originalDate = item.fireDate else { return 0 }
            let date = originalDate.addingTimeInterval(TimeInterval(-max(0, leadSeconds)))
            guard date > Date().addingTimeInterval(2) else { return 0 }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(for: item.key),
                content: makeContent(),
                trigger: trigger
            )
            do {
                try await notificationCenter.add(request)
                return 1
            } catch {
                lastScheduleErrors.append("\(request.identifier): \(error.localizedDescription)")
                return 0
            }
        }
    }

    func snooze(notification: UNNotification, minutes: Int = 10) async {
        let source = notification.request.content
        let content = UNMutableNotificationContent()
        content.title = source.title
        content.subtitle = source.subtitle
        content.body = source.body
        content.sound = source.sound ?? .default
        content.userInfo = source.userInfo
        content.categoryIdentifier = source.categoryIdentifier
        content.threadIdentifier = source.threadIdentifier
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, minutes) * 60),
            repeats: false
        )
        let identifier = "felpfit.native.snooze.\(UUID().uuidString)"
        do {
            try await notificationCenter.add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            )
        } catch {
            lastScheduleErrors.append("\(identifier): \(error.localizedDescription)")
        }
    }

    func cancelAlarm(forKey key: String) {
        guard !key.isEmpty else { return }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let rawID = alarmIDs[key], let id = UUID(uuidString: rawID) {
            try? AlarmManager.shared.cancel(id: id)
        }
        #endif
    }

    private func persistCurrentItems() {
        guard let data = try? JSONEncoder().encode(currentItems) else { return }
        defaults.set(data, forKey: DefaultsKey.currentItems)
    }

    private func canUseNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func notificationAuthorizationStatus() async -> String {
        switch (await notificationCenter.notificationSettings()).authorizationStatus {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    private func alarmAuthorizationStatus() -> String {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .notDetermined: return "notDetermined"
            case .authorized: return "authorized"
            case .denied: return "denied"
            @unknown default: return "unknown"
            }
        }
        #endif
        return "unsupported"
    }

    private func makeFingerprint(notificationStatus: Int, alarmStatus: String) -> String {
        let itemPart = currentItems.sorted { $0.key < $1.key }.map { item in
            "\(item.key)|pref=\(item.preferenceKey)|\(item.kind.rawValue)|\(item.hour):\(item.minute)|\(item.weekdays)|\(item.fireAtMilliseconds ?? 0)|\(isEnabled(item.preferenceKey))|\(isUrgent(item))"
        }.joined(separator: "~")
        return "native-v2|master=\(masterEnabled)|notif=\(notificationStatus)|alarm=\(alarmStatus)|\(itemPart)"
    }

    private func stateDictionary(message: String? = nil) async -> [String: Any] {
        let notificationStatus = await notificationAuthorizationStatus()
        let alarmStatus = alarmAuthorizationStatus()
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let pendingManaged = pendingRequests.filter {
            $0.identifier.hasPrefix("felpfit.native.") && !$0.identifier.hasPrefix(Self.testNotificationPrefix)
        }
        var prefs: [String: [String: Bool]] = [:]
        for item in currentItems {
            prefs[item.preferenceKey] = [
                "enabled": isEnabled(item.preferenceKey),
                "urgent": isUrgent(item)
            ]
        }

        var result: [String: Any] = [
            "type": "state",
            "masterEnabled": masterEnabled,
            "notificationStatus": notificationStatus,
            "alarmStatus": alarmStatus,
            "preferences": prefs,
            "scheduledAlarmCount": lastScheduledAlarmCount,
            "scheduledNotificationCount": lastScheduledNotificationCount,
            "verifiedPendingNotificationCount": pendingManaged.count,
            "fallbackCount": lastFallbackCount,
            "scheduleErrors": Array(lastScheduleErrors.suffix(12)),
            "native": true
        ]
        if let message { result["message"] = message }
        return result
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleAlarmKit(_ item: FelpFitScheduleItem, explicitID: UUID? = nil) async throws {
        typealias AlarmConfiguration = AlarmManager.AlarmConfiguration<FelpFitAlarmMetadata>

        let id = explicitID ?? alarmID(for: item.key)
        let alertTitle = LocalizedStringResource(stringLiteral: item.title)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            // iOS 26.1+ supplies the Stop control automatically.
            alert = AlarmPresentation.Alert(title: alertTitle)
        } else {
            // iOS 26.0 requires the original explicit Stop button initializer.
            let stopButton = AlarmButton(
                text: LocalizedStringResource(stringLiteral: "Parar"),
                textColor: .white,
                systemImageName: "stop.circle"
            )
            alert = AlarmPresentation.Alert(
                title: alertTitle,
                stopButton: stopButton,
                secondaryButton: nil,
                secondaryButtonBehavior: nil
            )
        }
        let metadata = FelpFitAlarmMetadata(
            key: item.key,
            questionID: item.questionID,
            dateKey: item.dateKey
        )
        let attributes = AlarmAttributes<FelpFitAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: metadata,
            tintColor: Color(red: 139.0 / 255.0, green: 92.0 / 255.0, blue: 246.0 / 255.0)
        )

        let schedule: Alarm.Schedule
        switch item.kind {
        case .weekly:
            let localeWeekdays = item.weekdays.compactMap(localeWeekday(fromCalendarWeekday:))
            guard !localeWeekdays.isEmpty else { return }
            let time = Alarm.Schedule.Relative.Time(hour: item.hour, minute: item.minute)
            let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(localeWeekdays)
            schedule = .relative(.init(time: time, repeats: recurrence))
        case .fixed:
            guard let date = item.fireDate, date > Date().addingTimeInterval(2) else { return }
            schedule = .fixed(date)
        }

        try? AlarmManager.shared.cancel(id: id)
        let configuration = AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            sound: .default
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    @available(iOS 26.0, *)
    private func localeWeekday(fromCalendarWeekday value: Int) -> Locale.Weekday? {
        switch value {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }
    #endif

    private func alarmID(for key: String) -> UUID {
        var ids = alarmIDs
        if let value = ids[key], let existing = UUID(uuidString: value) {
            return existing
        }
        let id = UUID()
        ids[key] = id.uuidString
        alarmIDs = ids
        return id
    }

    private func testAlarmID() -> UUID {
        alarmID(for: "__felpfit_test_alarm__")
    }

    private func cancelKnownAlarmKitAlarms() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for (key, value) in alarmIDs where key != "__felpfit_test_alarm__" {
                guard let id = UUID(uuidString: value) else { continue }
                try? AlarmManager.shared.cancel(id: id)
            }
        }
        #endif
    }
}

private extension FelpFitScheduleItem {
    init(
        key: String,
        preferenceKey: String,
        title: String,
        body: String,
        kind: Kind,
        hour: Int,
        minute: Int,
        weekdays: [Int],
        fireAtMilliseconds: Double?,
        questionID: String?,
        dateKey: String?,
        calendarDate: String?,
        category: String,
        defaultUrgent: Bool? = nil
    ) {
        self.key = key
        self.preferenceKey = preferenceKey
        self.title = title
        self.body = body
        self.kind = kind
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.fireAtMilliseconds = fireAtMilliseconds
        self.questionID = questionID
        self.dateKey = dateKey
        self.calendarDate = calendarDate
        self.category = category
        self.defaultUrgent = defaultUrgent ?? (category == "mission")
    }
}
