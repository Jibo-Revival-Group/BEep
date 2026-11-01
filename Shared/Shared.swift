import SwiftUI

/// Code shared by the app and the widget.

struct Robot: Identifiable, Hashable, Codable {
    var name: String
    var host: String
    var id: String { name }
    var url: URL { URL(string: "http://\(host):8123/")! }
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

    static var battery: Battery? {
        get { defaults.data(forKey: "battery").flatMap { try? JSONDecoder().decode(Battery.self, from: $0) } }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "battery") }
    }

    /// Reads the first robot's battery from BEacon and keeps it for the widget. Returns nil when
    /// Jibo can't be reached (another Wi-Fi) or his BEam doesn't report a battery yet.
    static func refreshBattery() async -> Battery? {
        struct Status: Decodable {
            struct Reading: Decodable { let level: Int; let pluggedIn: Bool? }
            let battery: Reading?
        }
        guard let robot = robots.first,
              let (data, response) = try? await URLSession.shared.data(
                  for: URLRequest(url: URL(string: "api/status", relativeTo: robot.url)!, timeoutInterval: 5)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reading = (try? JSONDecoder().decode(Status.self, from: data))?.battery else { return nil }
        let battery = Battery(robot: robot.name, level: reading.level, pluggedIn: reading.pluggedIn, updated: Date())
        self.battery = battery
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
            Image(systemName: charging ? "bolt.fill" : "battery.100")
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
