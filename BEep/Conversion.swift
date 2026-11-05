import Citadel
import Foundation
import NIOCore

/// Converts a modded Jibo to 5x1: logs in over SSH and runs the PM script (BEach `PM/post-mod.sh`,
/// served at scripts.5x1.com/pm), streaming its output. A Jibo that was never set up (OOBE) gets
/// `PM/post-oobe-mod.sh` instead; on an old factory system its first run only updates the system.
///
/// PM runs detached on the robot with its output in a log file that BEep follows, so it finishes
/// even if the phone locks or BEep closes mid-install; connecting again only follows the log.
enum Conversion {
    // OOBE: PM's own OOBE state file, no credentials yet, or mode "oobe". No single quotes: it runs inside sh -c '...'.
    static let script = "if [ -f /var/jibo/5x1-pm-oobe-state.json ] || [ ! -s /var/jibo/credentials.json ] || grep -q oobe /var/jibo/mode.json; then echo \"This Jibo was never set up (OOBE): running the OOBE script.\" && mount -o remount,rw / && mount -o remount,rw /usr/local && curl -fsSL -k https://raw.githubusercontent.com/Jibo-Revival-Group/BEach/master/PM/post-oobe-mod.sh -o /run/5x1-pm.sh && sh /run/5x1-pm.sh; else jibo-mount --rw && curl -fsSL -k https://scripts.5x1.com/pm -o /run/5x1-pm.sh && sh /run/5x1-pm.sh; fi"

    enum Outcome: Equatable { case converted, updating, failed(String) }

    /// The shell command BEep runs on the robot. `pm` is the PM command (tests swap in a harmless one).
    static func command(pm: String = script) -> String {
        """
        L=/run/5x1-pm.log
        if [ ! -f /run/5x1-pm.started ]; then
          touch /run/5x1-pm.started
          sh -c 'trap "" HUP; (\(pm)); echo "5X1_PM_EXIT $?"; rm -f /run/5x1-pm.started' </dev/null >$L 2>&1 &
          sleep 1
        fi
        exec tail -n +1 -f $L
        """
    }

    /// What a line of PM output means, if anything.
    static func outcome(of line: String) -> Outcome? {
        if line.contains("run this script again to install BEam and BEnch") { return .updating }
        if line.contains("Rebooting now") { return .converted }
        if line.hasPrefix("5X1_PM_EXIT ") {
            let code = line.dropFirst("5X1_PM_EXIT ".count).trimmingCharacters(in: .whitespaces)
            return code == "0" ? .converted : .failed("The 5x1 script stopped with an error (exit \(code)). Its output is above.")
        }
        return nil
    }

    static func run(host: String, port: Int = 22, password: String, pm: String = script,
                    output: @escaping (String) -> Void) async -> Outcome {
        let client: SSHClient
        do {
            client = try await SSHClient.connect(host: host, port: port,
                authenticationMethod: .passwordBased(username: "root", password: password),
                hostKeyValidator: .acceptAnything(), // a freshly modded Jibo has a host key we can't know in advance
                reconnect: .never)
        } catch {
            return .failed("Couldn't log in to \(host) over SSH. Check the address and that Jibo has been modded (\(error)).")
        }
        defer { Task { try? await client.close() } }
        var pending = "", result: Outcome?
        do {
            for try await chunk in try await client.executeCommandStream(command(pm: pm)) {
                guard case .stdout(var buffer) = chunk, let text = buffer.readString(length: buffer.readableBytes) else { continue }
                pending += text
                while let end = pending.firstIndex(of: "\n") {
                    let line = String(pending[..<end]); pending = String(pending[pending.index(after: end)...])
                    output(line)
                    // After an OOBE system update, PM exits 0 but Jibo still needs a second run.
                    if let found = outcome(of: line), !(result == .updating && found == .converted) { result = found }
                    if case .failed = result { return result! }
                    if line.hasPrefix("5X1_PM_EXIT ") { return result! }
                }
            }
        } catch {
            // PM ends by rebooting Jibo, which drops the connection.
            if result == .converted || result == .updating { return result! }
            return .failed("Lost the connection to Jibo before the 5x1 script finished. Open this again to keep following it (\(error)).")
        }
        return result ?? .failed("The connection closed before the 5x1 script finished. Open this again to keep following it.")
    }
}
