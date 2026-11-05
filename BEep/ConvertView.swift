import SwiftUI

/// Turns a modded Jibo into a 5x1 Jibo by running the PM script on it over SSH (see Conversion).
struct ConvertView: View {
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    // Launch arguments let the simulator check run a conversion against a stand-in robot.
    @State private var host = ConvertView.testArgument("BEepConvert") ?? ""
    @State private var log: [String] = []
    @State private var running = false
    @State private var outcome: Conversion.Outcome?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Installs 5x1 (BEam and BEnch) on a Jibo that has already been modded, then restarts him. Keep BEep open; it takes several minutes.")
                        .foregroundStyle(.secondary)
                    TextField("Jibo's IP address", text: $host)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    .padding(16)
                    .glass(in: RoundedRectangle(cornerRadius: 22))
                    .disabled(running)
                    Button { start() } label: {
                        Label(running ? "Converting…" : "Convert to 5x1", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .prominentGlassButton()
                    .controlSize(.large)
                    .disabled(running || host.trimmingCharacters(in: .whitespaces).isEmpty)
                    status
                    if !log.isEmpty { output }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle("Convert a Jibo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == .converted ? "Done" : "Close") { onDone(); dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(running)
        .onAppear { if ConvertView.testArgument("BEepConvert") != nil { start() } }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder private var status: some View {
        switch outcome {
        case .converted:
            Label("Jibo is restarting into 5x1. He'll show up under Your robots in a couple of minutes.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.green)
        case .updating:
            Label("Jibo is updating to the final Jibo system first. He'll restart a few times on his own. When the update screens are done, tap Convert again to install 5x1.", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(Theme.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case nil:
            if running { Label("Working on Jibo… keep BEep open.", systemImage: "hourglass").foregroundStyle(.secondary) }
        }
    }

    private var output: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(log.indices, id: \.self) { i in
                        Text(log[i]).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading).id(i)
                    }
                }
                .textSelection(.enabled)
                .padding(14)
            }
            .frame(height: 320)
            .glass(in: RoundedRectangle(cornerRadius: 22))
            .onChange(of: log.count) { count in reader.scrollTo(count - 1, anchor: .bottom) }
        }
    }

    /// `-name value` from the launch arguments, as given (UserDefaults would parse it as a plist).
    static func testArgument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-" + name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private func start() {
        let target = host.trimmingCharacters(in: .whitespaces)
        let port = Int(ConvertView.testArgument("BEepConvertPort") ?? "") ?? 0
        let pm = ConvertView.testArgument("BEepConvertPM") ?? Conversion.script
        running = true; outcome = nil; log = []
        UIApplication.shared.isIdleTimerDisabled = true // the phone sleeping would drop the connection
        Task {
            let result = await Conversion.run(host: target, port: port > 0 ? port : 22, password: "jibo", pm: pm) { line in // "jibo" is every modded Jibo's root password
                Task { @MainActor in log.append(line); if log.count > 3000 { log.removeFirst(500) } }
            }
            await MainActor.run {
                outcome = result; running = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}
