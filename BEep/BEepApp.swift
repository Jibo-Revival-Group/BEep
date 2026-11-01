import SwiftUI

import EventKit
import UserNotifications

@main
struct BEepApp: App {
    @Environment(\.scenePhase) private var phase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            Task { await Companion.shared.syncAll() }
        }
    }

    var body: some Scene {
        WindowGroup {
            Home()
                .preferredColorScheme(.dark)
                .tint(Theme.green)
                .onChange(of: phase) { phase in
                    if phase == .active { Task { await Companion.shared.syncAll() } }
                    if phase == .background { Companion.scheduleRefresh() }
                }
        }
        .backgroundTask(.appRefresh(Companion.refreshID)) {
            Companion.scheduleRefresh()
            await Companion.shared.syncAll()
        }
    }
}

struct Home: View {
    @StateObject private var finder = RobotFinder()
    @State private var path: [Robot] = []
    @State private var address = ""
    @State private var addError: String?
    // The simulator check sets this to photograph the home screen.
    @State private var opened = UserDefaults.standard.bool(forKey: "BEepStayHome")

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    robots
                    addByAddress
                    Link("Made by 5x1 · 5x1.com", destination: URL(string: "https://5x1.com")!)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.backdrop.ignoresSafeArea())
            .refreshable { finder.restart() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Robot.self) { RobotScreen(robot: $0) }
        }
        .overlay {
            if UserDefaults.standard.bool(forKey: "BEepWidgetPreview") { WidgetPreview() }
        }
        .onAppear {
            finder.start()
            autoOpen(finder.robots)
        }
        .onChange(of: finder.robots) { autoOpen($0) }
    }

    /// With one robot, skip this screen and open BEacon straight away (once per launch).
    private func autoOpen(_ robots: [Robot]) {
        if !opened, robots.count == 1, path.isEmpty { opened = true; path = robots }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 104)
                .shadow(color: Theme.green.opacity(0.35), radius: 24)
            Text("BEep").font(.largeTitle.bold())
            Text("Your Jibo, in your pocket.").foregroundStyle(.secondary)
        }
        .padding(.top, 28)
    }

    private var robots: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your robots").font(.headline).padding(.leading, 4)
            ForEach(finder.robots) { robot in
                NavigationLink(value: robot) {
                    HStack(spacing: 14) {
                        Image("Logo").resizable().scaledToFit().frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(robot.name).font(.body.weight(.semibold)).lineLimit(1)
                            Text(robot.host).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .contentShape(RoundedRectangle(cornerRadius: 24))
                    .glass(in: RoundedRectangle(cornerRadius: 24), interactive: true)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Forget \(robot.name)", systemImage: "trash", role: .destructive) {
                        finder.robots.removeAll { $0 == robot }
                    }
                }
            }
            if finder.robots.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for Jibo on this Wi-Fi…").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(16)
                .glass(in: RoundedRectangle(cornerRadius: 24))
            }
        }
    }

    private var addByAddress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add by IP address").font(.headline).padding(.leading, 4)
            HStack(spacing: 10) {
                TextField("192.168.1.20", text: $address)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.leading, 6)
                Button("Add") { add() }
                    .prominentGlassButton()
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
            .glass(in: Capsule())
            Text(addError ?? "Jibo's IP address is in Settings › Wi-Fi on his screen.")
                .font(.footnote)
                .foregroundStyle(addError == nil ? Color.secondary : Color.red)
                .padding(.horizontal, 4)
        }
    }

    private func add() {
        let host = address.trimmingCharacters(in: .whitespaces)
        addError = nil
        Task {
            if let robot = await finder.check(host) {
                address = ""
                path = [robot]
            } else {
                addError = "No Jibo with BEacon answered at \(host). Check the address and that your phone is on the same Wi-Fi."
            }
        }
    }
}

/// The battery widget's faces at their real sizes; shown only by the simulator check.
private struct WidgetPreview: View {
    @State private var battery = Shared.battery

    var body: some View {
        VStack(spacing: 24) {
            BatteryFace(battery: battery, size: .small)
                .padding(16)
                .frame(width: 170, height: 170)
                .background(Theme.backdrop, in: RoundedRectangle(cornerRadius: 22))
            BatteryFace(battery: battery, size: .circular)
                .frame(width: 76, height: 76)
                .background(.white.opacity(0.15), in: Circle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .task {
            await Companion.shared.syncAll()
            battery = Shared.battery
        }
    }
}
