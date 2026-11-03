import SwiftUI
import WebKit

/// BEacon full-screen under native Liquid Glass bars: the navigation bar carries BEacon's page
/// title and its toolbar buttons, and a floating glass bar replaces BEacon's tabs.
struct RobotScreen: View {
    @StateObject private var beacon: BEacon
    @State private var setup = false

    init(robot: Robot) {
        _beacon = StateObject(wrappedValue: BEacon(robot: robot))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen so it scrolls under the glass bars, but starts below the top one.
            GeometryReader { geometry in
                WebView(web: beacon.web, top: geometry.safeAreaInsets.top).ignoresSafeArea()
            }
            if beacon.loaded { GlassTabBar(beacon: beacon) }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(beacon.title.isEmpty ? beacon.robot.name : beacon.title)
        .subtitle(beacon.robot.name)
        .navigationBarTitleDisplayMode(.inline)
        // The first time this robot opens, ask about the iPhone features (once it's reachable).
        .onChange(of: beacon.loaded) { loaded in
            if loaded && !UserDefaults.standard.bool(forKey: "onboarded.\(beacon.robot.name)") { setup = true }
        }
        .sheet(isPresented: $setup) { SetupView(beacon: beacon) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ForEach(beacon.actions, id: \.self) { action in
                    Button(action.label) { beacon.perform(action) }.disabled(action.disabled)
                }
            }
        }
    }
}

private struct WebView: UIViewRepresentable {
    let web: WKWebView
    let top: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        web.scrollView.contentInsetAdjustmentBehavior = .never
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let scroll = web.scrollView
        guard scroll.contentInset.top != top else { return }
        let atTop = scroll.contentOffset.y <= -scroll.contentInset.top
        scroll.contentInset.top = top
        scroll.verticalScrollIndicatorInsets.top = top
        if atTop { scroll.contentOffset.y = -top }
    }
}

struct GlassTabBar: View {
    @ObservedObject var beacon: BEacon

    private struct Tab: Identifiable {
        let panel: String, title: String, icon: String
        var id: String { panel }
    }

    private static let main = [
        Tab(panel: "status", title: "Status", icon: "info.circle"),
        Tab(panel: "screen", title: "Screen", icon: "tv"),
        Tab(panel: "photos", title: "Photos", icon: "photo.on.rectangle"),
        Tab(panel: "people", title: "People", icon: "person.2"),
        Tab(panel: "store", title: "Store", icon: "storefront")
    ]
    private static let more = [
        Tab(panel: "server", title: "Server", icon: "server.rack"),
        Tab(panel: "etc", title: "Settings", icon: "gearshape")
    ]

    // The selection is one glass bubble, as in iOS 26's tab bar: it springs to the chosen tab,
    // swells while pressed, and follows a finger dragged along the bar (lifting selects).
    @State private var dragX: CGFloat?

    private var selectedIndex: Int {
        Self.main.firstIndex { $0.panel == beacon.panel } ?? (Self.more.contains { $0.panel == beacon.panel } ? Self.main.count : 0)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / CGFloat(Self.main.count + 1)
            let x = dragX.map { min(max($0 - width / 2, 0), width * CGFloat(Self.main.count - 1)) } ?? width * CGFloat(selectedIndex)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.clear)
                    .selectionGlass()
                    .frame(width: width, height: 50)
                    .scaleEffect(dragX == nil ? 1 : 1.12)
                    .offset(x: x)
                    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: x)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: dragX == nil)
                HStack(spacing: 0) {
                    ForEach(Array(Self.main.enumerated()), id: \.element.id) { index, tab in
                        Button { beacon.show(tab.panel) } label: {
                            item(tab.title, tab.icon, selected: dragX == nil ? selectedIndex == index : Int(x / width + 0.5) == index)
                        }
                    }
                    Menu {
                        ForEach(Self.more) { tab in
                            Button(tab.title, systemImage: tab.icon) { beacon.show(tab.panel) }
                        }
                    } label: {
                        item("More", "ellipsis.circle", selected: dragX == nil && selectedIndex == Self.main.count)
                    }
                }
                .buttonStyle(.plain)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in if value.startLocation.x < width * CGFloat(Self.main.count) { dragX = value.location.x } }
                    .onEnded { value in
                        guard dragX != nil else { return }
                        let index = min(max(Int(value.location.x / width), 0), Self.main.count - 1)
                        dragX = nil
                        beacon.show(Self.main[index].panel)
                    }
            )
        }
        .frame(height: 50)
        .padding(5)
        .glass(in: Capsule(), interactive: true)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func item(_ title: String, _ icon: String, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
            Text(title).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(selected ? Theme.green : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    @ViewBuilder
    func selectionGlass() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(Theme.green.opacity(0.22)).interactive(), in: Capsule())
        } else {
            background(Theme.green.opacity(0.16), in: Capsule())
        }
    }
}

/// First-time questions for a robot: the same settings as BEacon's "On this iPhone", with Skip.
private struct SetupView: View {
    let beacon: BEacon
    @Environment(\.dismiss) private var dismiss
    @State private var settings = Companion.Settings()
    @State private var people: [(id: String, name: String)] = []
    @State private var problem: String?
    @State private var saving = false

    private var robot: Robot { beacon.robot }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Who are you?", selection: $settings.member) {
                        Text("Choose").tag("")
                        ForEach(people, id: \.id) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("So \(robot.name) can answer “How is my phone’s battery?”")
                }
                Section {
                    Toggle("Save \(robot.name)’s new photos to this iPhone", isOn: $settings.savePhotos)
                    Toggle("Notify me when \(robot.name)’s battery is low", isOn: $settings.lowBattery)
                } footer: {
                    Text(problem ?? "You can change these later in BEacon under More › Settings › On this iPhone.")
                        .foregroundStyle(problem == nil ? Color.secondary : Color.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle("Set up BEep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { finish() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.disabled(saving)
                }
            }
        }
        .interactiveDismissDisabled()
        .task {
            settings = await Companion.shared.settings(for: robot)
            struct List: Decodable {
                struct Member: Decodable { let id: String; let firstName: String?; let writtenName: String?; let isJibo: Bool? }
                let members: [Member]
            }
            if let data = try? await Shared.data(robot, "GET", "api/people"), let list = try? JSONDecoder().decode(List.self, from: data) {
                people = list.members.filter { $0.isJibo != true }.map { ($0.id, $0.firstName ?? $0.writtenName ?? "Someone") }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            let (now, problem) = await Companion.shared.update(settings, for: robot)
            await beacon.showSettings(now, problem)
            saving = false
            settings = now
            if let problem { self.problem = problem } else { finish() } // a refused permission stays visible
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboarded.\(robot.name)")
        dismiss()
    }
}
