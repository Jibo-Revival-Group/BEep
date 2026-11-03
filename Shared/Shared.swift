import SwiftUI
import UIKit

/// Code shared by the app and the widget.

struct Robot: Identifiable, Hashable, Codable {
    var name: String
    var host: String
    /// BEacon's address away from home (set by long-pressing the robot), used when `host` can't be reached.
    var remote: String?
    var id: String { name }
    var url: URL { URL(string: "http://\(host):8123/")! }
    var remoteURL: URL? {
        guard let remote, !remote.isEmpty, var url = URL(string: remote), url.scheme == "http" || url.scheme == "https" else { return nil }
        if !url.absoluteString.hasSuffix("/") { url = URL(string: url.absoluteString + "/")! }
        return url
    }
}

/// 5x1 colours (5x1.com).
enum Theme {
    static let green = Color("AccentColor")
    static let background = Color("LaunchBackground")
    static let glow = Color(red: 0x1C / 255, green: 0x30 / 255, blue: 0x23 / 255)
    static let backdrop = RadialGradient(colors: [glow, background], center: .top, startRadius: 0, endRadius: 650)
}

/// Storage the app and widget both read, in their shared App Group.
enum Shared {
    struct Battery: Codable, Equatable {
        let robot: String
        let level: Int
        let pluggedIn: Bool?
        let updated: Date
    }

    static let defaults = UserDefaults(suiteName: groupID) ?? .standard

    /// AltStore and SideStore rename App Groups per Apple account and list the real names under
    /// ALTAppGroups in the app's Info.plist; the extension may only have it in the app's.
    private static var groupID: String {
        let app = Bundle.main.bundleURL.pathExtension == "appex"
            ? Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
            : Bundle.main
        for bundle in [Bundle.main, app] {
            if let groups = bundle?.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let first = groups.first {
                return first
            }
        }
        return "group.com.jiborevival.beep"
    }

    static var robots: [Robot] {
        get {
            // Robots were saved outside the App Group before the widget existed.
            let data = defaults.data(forKey: "robots") ?? UserDefaults.standard.data(forKey: "robots")
            return data.flatMap { try? JSONDecoder().decode([Robot].self, from: $0) } ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "robots") }
    }

    /// Calls BEacon at its Wi-Fi address, then at its remote address if that fails.
    static func data(_ robot: Robot, _ method: String = "GET", _ path: String, body: Data? = nil, timeout: TimeInterval = 20) async throws -> Data {
        var failure: Error = URLError(.cannotConnectToHost)
        for base in [robot.url, robot.remoteURL].compactMap({ $0 }) {
            var request = URLRequest(url: URL(string: path, relativeTo: base)!, timeoutInterval: timeout)
            request.httpMethod = method
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                return data
            } catch let error as URLError where error.code != .badServerResponse {
                failure = error // unreachable: try the next address
            }
        }
        throw failure
    }

    /// Which loop member this phone belongs to, per robot (for "how is my phone's battery?").
    static func member(for robot: Robot) -> String { defaults.string(forKey: "member.\(robot.name)") ?? "" }
    static func setMember(_ member: String, for robot: Robot) { defaults.set(member, forKey: "member.\(robot.name)") }

    /// Tells Jibo this phone's battery, so he can answer "how is my phone's battery?". iOS only
    /// lets BEep run now and then, so the app, its background refresh and the widget all send it.
    static func reportPhoneBattery(to robot: Robot) async {
        let (level, charging) = await MainActor.run { () -> (Float, Bool) in
            UIDevice.current.isBatteryMonitoringEnabled = true
            return (UIDevice.current.batteryLevel, [.charging, .full].contains(UIDevice.current.batteryState))
        }
        guard level >= 0, // -1: unknown (the simulator)
              let body = try? JSONSerialization.data(withJSONObject: ["member": member(for: robot), "level": Double(level * 100), "charging": charging])
        else { return }
        _ = try? await data(robot, "POST", "api/phone-battery", body: body, timeout: 10)
    }

    /// The last battery reading for each robot, for the widget.
    static func battery(for robot: Robot) -> Battery? {
        defaults.data(forKey: "battery.\(robot.name)").flatMap { try? JSONDecoder().decode(Battery.self, from: $0) }
    }

    /// Reads a robot's battery from BEacon and keeps it for the widget. Returns nil when Jibo
    /// can't be reached (another Wi-Fi and no remote address) or his BEam doesn't report a battery yet.
    static func refreshBattery(for robot: Robot) async -> Battery? {
        struct Status: Decodable {
            struct Reading: Decodable { let level: Int; let pluggedIn: Bool? }
            let battery: Reading?
        }
        guard let body = try? await data(robot, "GET", "api/status", timeout: 5),
              let reading = (try? JSONDecoder().decode(Status.self, from: body))?.battery else { return nil }
        let battery = Battery(robot: robot.name, level: reading.level, pluggedIn: reading.pluggedIn, updated: Date())
        defaults.set(try? JSONEncoder().encode(battery), forKey: "battery.\(robot.name)")
        return battery
    }
}

/// The battery widget's face, also used for the app's widget preview.
struct BatteryFace: View {
    enum Size { case small, circular }
    let battery: Shared.Battery?
    let size: Size

    private var colour: Color {
        guard let level = battery?.level else { return .secondary }
        return level <= 10 ? .red : level <= 20 ? .orange : Theme.green
    }

    private var charging: Bool { battery?.pluggedIn == true }

    var body: some View {
        switch size {
        case .circular: circular
        case .small: small
        }
    }

    private var circular: some View {
        Gauge(value: Double(battery?.level ?? 0), in: 0...100) {
            Image(systemName: charging ? "bolt.fill" : "battery.\(min(100, (battery?.level ?? 0) / 25 * 25))")
        } currentValueLabel: {
            Text(battery.map { "\($0.level)" } ?? "–")
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image("Logo").resizable().scaledToFit().frame(width: 18, height: 18)
                Text(battery?.robot ?? "Jibo").font(.caption.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let battery {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(battery.level)").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("%").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    if charging { Image(systemName: "bolt.fill").foregroundStyle(Theme.green) }
                }
                ProgressView(value: Double(battery.level), total: 100).tint(colour)
                (Text(charging ? "Charging · " : "On battery · ") + Text(battery.updated, style: .time))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open BEep on Jibo's Wi-Fi to see his battery.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
    }
}
