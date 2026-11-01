import AppIntents
import SwiftUI
import WidgetKit

@main
struct BEepWidgets: WidgetBundle {
    var body: some Widget { BatteryWidget() }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "battery", intent: ChooseJibo.self, provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("Jibo's battery")
        .description("Jibo's battery level. Updates while your iPhone is on his Wi-Fi. Edit the widget to choose which Jibo.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

/// Edit Widget › Jibo: any robot saved in BEep. Left empty, the widget shows the first one.
struct ChooseJibo: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Jibo"
    static var description = IntentDescription("Pick which Jibo's battery to show.")

    @Parameter(title: "Jibo")
    var robot: JiboEntity?
}

struct JiboEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Jibo"
    static var defaultQuery = JiboQuery()
    let id: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct JiboQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [JiboEntity] {
        Shared.robots.filter { identifiers.contains($0.name) }.map { JiboEntity(id: $0.name) }
    }

    func suggestedEntities() async throws -> [JiboEntity] {
        Shared.robots.map { JiboEntity(id: $0.name) }
    }

    func defaultResult() async -> JiboEntity? {
        Shared.robots.first.map { JiboEntity(id: $0.name) }
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let battery: Shared.Battery?
}

struct BatteryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), battery: Shared.Battery(robot: "Jibo", level: 80, pluggedIn: true, updated: Date()))
    }

    func snapshot(for configuration: ChooseJibo, in context: Context) async -> BatteryEntry {
        guard let robot = robot(configuration), let battery = Shared.battery(for: robot) else { return placeholder(in: context) }
        return BatteryEntry(date: Date(), battery: battery)
    }

    /// Tries Jibo first and falls back to the last reading (the app also saves one whenever it syncs).
    func timeline(for configuration: ChooseJibo, in context: Context) async -> Timeline<BatteryEntry> {
        var battery: Shared.Battery?
        if let robot = robot(configuration) {
            battery = await Shared.refreshBattery(for: robot) ?? Shared.battery(for: robot)
        }
        return Timeline(entries: [BatteryEntry(date: Date(), battery: battery)],
                        policy: .after(Date(timeIntervalSinceNow: 15 * 60)))
    }

    private func robot(_ configuration: ChooseJibo) -> Robot? {
        let robots = Shared.robots
        return robots.first { $0.name == configuration.robot?.id } ?? robots.first
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
