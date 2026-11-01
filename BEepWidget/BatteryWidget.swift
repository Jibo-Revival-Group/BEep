import SwiftUI
import WidgetKit

@main
struct BEepWidgets: WidgetBundle {
    var body: some Widget { BatteryWidget() }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "battery", provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("Jibo's battery")
        .description("Jibo's battery level. Updates while your iPhone is on his Wi-Fi.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let battery: Shared.Battery?
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), battery: Shared.Battery(robot: "Jibo", level: 80, pluggedIn: true, updated: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(Shared.battery.map { BatteryEntry(date: Date(), battery: $0) } ?? placeholder(in: context))
    }

    /// Tries Jibo first and falls back to the last reading (the app also saves one whenever it syncs).
    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        Task {
            let battery = await Shared.refreshBattery() ?? Shared.battery
            let entry = BatteryEntry(date: Date(), battery: battery)
            completion(Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 15 * 60))))
        }
    }
}

struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatteryEntry

    var body: some View {
        BatteryFace(battery: entry.battery, size: family == .accessoryCircular ? .circular : .small)
            .containerBackground(for: .widget) {
                if family == .accessoryCircular { AccessoryWidgetBackground() } else { Theme.backdrop }
            }
    }
}
