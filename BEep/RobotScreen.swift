import SwiftUI
import WebKit

/// BEacon full-screen under native Liquid Glass bars: the navigation bar carries BEacon's page
/// title and its toolbar buttons, and a floating glass bar replaces BEacon's tabs.
struct RobotScreen: View {
    @StateObject private var beacon: BEacon

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
        Tab(panel: "people", title: "People", icon: "person.2")
    ]
    private static let more = [
        Tab(panel: "store", title: "Store", icon: "storefront"),
        Tab(panel: "server", title: "Server", icon: "server.rack"),
        Tab(panel: "etc", title: "Settings", icon: "gearshape")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.main) { tab in
                Button { beacon.show(tab.panel) } label: {
                    item(tab.title, tab.icon, selected: beacon.panel == tab.panel)
                }
            }
            Menu {
                ForEach(Self.more) { tab in
                    Button(tab.title, systemImage: tab.icon) { beacon.show(tab.panel) }
                }
            } label: {
                item("More", "ellipsis.circle", selected: Self.more.contains { $0.panel == beacon.panel })
            }
        }
        .buttonStyle(.plain)
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
        .background(selected ? Theme.green.opacity(0.16) : .clear, in: Capsule())
        .contentShape(Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
