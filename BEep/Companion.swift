import BackgroundTasks
import EventKit
import Foundation
import Photos
import UserNotifications

/// Per-robot iPhone features, switched on in the app's BEacon (More › Settings › On this iPhone):
/// saving Jibo's new photos, a low-battery notification, and sending this iPhone's calendar to
/// one person. They run when BEep opens, when a robot is opened, when the phone's calendar
/// changes, and when iOS gives BEep background refresh time.
actor Companion {
    static let shared = Companion()
    static let refreshID = "com.jiborevival.beep.refresh"

    struct Settings: Codable, Equatable {
        var savePhotos = false
        var lowBattery = false
        var calendarMember = ""
    }

    private let defaults = UserDefaults.standard
    private let events = EKEventStore()
    private var syncing: Set<String> = []

    func settings(for robot: Robot) -> Settings {
        Settings(savePhotos: defaults.bool(forKey: "savePhotos.\(robot.name)"),
                 lowBattery: defaults.bool(forKey: "lowBattery.\(robot.name)"),
                 calendarMember: defaults.string(forKey: "calendarMember.\(robot.name)") ?? "")
    }

    /// Applies a change from BEacon, asking for the iPhone permission it needs. Returns the
    /// settings now in force (a refused permission leaves that one off) and any problem to show.
    func update(_ wanted: Settings, for robot: Robot) async -> (Settings, String?) {
        let old = settings(for: robot)
        var now = wanted
        var problem: String?
        if wanted.savePhotos && !old.savePhotos {
            if await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized {
                // Start from Jibo's next photo rather than copying everything he already has.
                guard let ids = try? await photoIDs(robot) else {
                    return (old, "Couldn't reach \(robot.name). Try again on the same Wi-Fi.")
                }
                defaults.set(ids, forKey: "savedPhotos.\(robot.name)")
            } else {
                now.savePhotos = false
                problem = "Allow BEep to add photos in iPhone Settings › Privacy & Security › Photos."
            }
        }
        if wanted.lowBattery && !old.lowBattery {
            let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            if !allowed {
                now.lowBattery = false
                problem = "Allow notifications for BEep in iPhone Settings › Notifications."
            }
        }
        if !wanted.calendarMember.isEmpty && wanted.calendarMember != old.calendarMember {
            let allowed = await calendarAccess()
            if !allowed {
                now.calendarMember = old.calendarMember
                problem = "Allow BEep full access to your calendars in iPhone Settings › Privacy & Security › Calendars."
            }
        }
        if now.calendarMember != old.calendarMember {
            defaults.removeObject(forKey: "sentCalendar.\(robot.name)")
            if !old.calendarMember.isEmpty {
                _ = try? await request(robot, "DELETE", "api/people/calendar?id=\(query(old.calendarMember))")
            }
        }
        defaults.set(now.savePhotos, forKey: "savePhotos.\(robot.name)")
        defaults.set(now.lowBattery, forKey: "lowBattery.\(robot.name)")
        defaults.set(now.calendarMember, forKey: "calendarMember.\(robot.name)")
        await sync(robot)
        return (now, problem)
    }

    func syncAll() async {
        for robot in RobotFinder.load() { await sync(robot) }
    }

    func sync(_ robot: Robot) async {
        // Only one run per robot at a time, so a photo is never saved twice.
        guard syncing.insert(robot.name).inserted else { return }
        defer { syncing.remove(robot.name) }
        let settings = settings(for: robot)
        if settings.savePhotos { await savePhotos(robot) }
        if settings.lowBattery { await checkBattery(robot) }
        if !settings.calendarMember.isEmpty { await sendCalendar(to: settings.calendarMember, robot) }
    }

    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Photos

    private struct PhotoList: Decodable {
        struct Photo: Decodable { let id: String; let available: Bool? }
        let photos: [Photo]
    }

    private func photoIDs(_ robot: Robot) async throws -> [String] {
        let list: PhotoList = try await get(robot, "api/photos")
        return list.photos.map(\.id)
    }

    private func savePhotos(_ robot: Robot) async {
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized,
              let list: PhotoList = try? await get(robot, "api/photos") else { return }
        let key = "savedPhotos.\(robot.name)"
        var saved = Set(defaults.stringArray(forKey: key) ?? [])
        for photo in list.photos where photo.available != false && !saved.contains(photo.id) {
            guard let data = try? await request(robot, "GET", "api/photos/file?id=\(query(photo.id))") else { continue }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
            } catch {
                return
            }
            saved.insert(photo.id)
            defaults.set(Array(saved), forKey: key)
        }
    }

    // MARK: Battery

    private struct Status: Decodable {
        struct Battery: Decodable { let level: Int; let pluggedIn: Bool? }
        let battery: Battery?
    }

    /// One notification each time the battery falls to 20% unplugged; it re-arms at 30% or on charge.
    private func checkBattery(_ robot: Robot) async {
        guard let status: Status = try? await get(robot, "api/status"), let battery = status.battery else { return }
        let key = "batteryAlerted.\(robot.name)"
        if battery.pluggedIn == true || battery.level >= 30 {
            defaults.set(false, forKey: key)
            return
        }
        guard battery.level <= 20, !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        let content = UNMutableNotificationContent()
        content.title = "Jibo's battery is low"
        content.body = "\(robot.name) is at \(battery.level)%. Put him back on his base soon."
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }

    // MARK: Calendar

    private func calendarAccess() async -> Bool {
        if #available(iOS 17, *) { return (try? await events.requestFullAccessToEvents()) ?? false }
        return (try? await events.requestAccess(to: .event)) ?? false
    }

    private var hasCalendarAccess: Bool {
        if #available(iOS 17, *) { return EKEventStore.authorizationStatus(for: .event) == .fullAccess }
        return EKEventStore.authorizationStatus(for: .event) == .authorized
    }

    /// Sends the coming week as an inline calendar in place of that person's calendar link
    /// (BEefy reads it like a feed). Skipped when nothing changed since the last send.
    private func sendCalendar(to member: String, _ robot: Robot) async {
        guard hasCalendarAccess else { return }
        let start = Calendar.current.startOfDay(for: Date())
        var calendar = ""
        for days in stride(from: 8, through: 1, by: -1) {
            let end = Calendar.current.date(byAdding: .day, value: days, to: start)!
            let found = events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: nil))
            calendar = "data:text/calendar;base64," + Data(Self.ics(found).utf8).base64EncodedString()
            if calendar.count <= 60_000 { break } // BEefy's limit; a busy week sends fewer days.
        }
        let key = "sentCalendar.\(robot.name)"
        guard defaults.string(forKey: key) != calendar,
              let body = try? JSONSerialization.data(withJSONObject: ["id": member, "icalUrl": calendar, "isEnabled": true]),
              (try? await request(robot, "PUT", "api/people/calendar", body: body)) != nil else { return }
        defaults.set(calendar, forKey: key)
    }

    static func ics(_ events: [EKEvent]) -> String {
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyyMMdd"
        func text(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
        }
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//5x1//BEep//EN"]
        for event in events {
            // EventKit lists each repeat separately, so every occurrence is its own event here.
            lines += ["BEGIN:VEVENT",
                      "UID:\(event.calendarItemExternalIdentifier ?? UUID().uuidString)-\(Int(event.startDate.timeIntervalSince1970))",
                      "SUMMARY:\(text(event.title ?? "Event"))"]
            if event.isAllDay {
                // EventKit ends all-day events at 23:59:59; iCal's end date is the next day.
                lines += ["DTSTART;VALUE=DATE:\(day.string(from: event.startDate))",
                          "DTEND;VALUE=DATE:\(day.string(from: event.endDate.addingTimeInterval(1)))"]
            } else {
                lines += ["DTSTART:\(utc.string(from: event.startDate))", "DTEND:\(utc.string(from: event.endDate))"]
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: BEacon requests

    private func query(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private func get<T: Decodable>(_ robot: Robot, _ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await request(robot, "GET", path))
    }

    private func request(_ robot: Robot, _ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: robot.url)!, timeoutInterval: 20)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

/// Shows the low-battery notification even while BEep is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}
