import SwiftUI

@main
struct BEepApp: App {
    var body: some Scene {
        WindowGroup { RobotList() }
    }
}

struct RobotList: View {
    @StateObject private var finder = RobotFinder()
    @State private var path: [Robot] = []
    @State private var address = ""
    @State private var addError: String?
    @State private var opened = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Your robots") {
                    ForEach(finder.robots) { robot in
                        NavigationLink(value: robot) {
                            VStack(alignment: .leading) {
                                Text(robot.name)
                                Text(robot.host).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { finder.robots.remove(atOffsets: $0) }
                    if finder.robots.isEmpty {
                        Label("Looking for Jibo on this Wi-Fi…", systemImage: "wifi")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    HStack {
                        TextField("192.168.1.20", text: $address)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") { add() }
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Add by IP address")
                } footer: {
                    Text(addError ?? "Jibo's IP address is in Settings › Wi-Fi on his screen.")
                }
            }
            .navigationTitle("BEep")
            .navigationDestination(for: Robot.self) { robot in
                BEaconView(robot: robot)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(robot.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .refreshable { finder.restart() }
        }
        .onAppear { finder.start() }
        .onChange(of: finder.robots) { robots in
            // With one robot, skip the list and open BEacon straight away (once per launch).
            if !opened, robots.count == 1, path.isEmpty { opened = true; path = robots }
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
