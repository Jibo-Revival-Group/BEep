import Foundation
import Network
import WidgetKit

/// Finds Jibos on the Wi-Fi and remembers them. Jibo's avahi advertises SSH under the robot's
/// name, so browse that and keep only hosts whose BEacon answers /api/status.
@MainActor
final class RobotFinder: ObservableObject {
    @Published var robots: [Robot] = RobotFinder.load() {
        didSet { Shared.robots = robots }
    }
    private var browser: NWBrowser?

    init() {
        // Robots saved before 1.2 are only in the app's own storage; copy them to the App Group
        // on every launch so the widget (and its Jibo picker) can see them.
        Shared.robots = robots
        WidgetCenter.shared.reloadAllTimelines()
    }

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_ssh._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                Task { @MainActor in _ = await self?.check("\(name).local") }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func restart() {
        browser?.cancel()
        browser = nil
        start()
        for robot in robots { Task { _ = await check(robot.host) } }
    }

    /// Asks BEacon at `host` who it is; saves the robot under its IP so the page works even
    /// where .local names don't resolve. A known robot with a new IP is updated in place.
    func check(_ host: String) async -> Robot? {
        guard let url = URL(string: "http://\(host):8123/api/status"),
              let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 5)),
              let status = try? JSONDecoder().decode(Status.self, from: data),
              status.name == "BEacon" else { return nil }
        var robot = Robot(name: status.hostname ?? host,
                          host: status.addresses?.first(where: { $0.address.contains(".") })?.address ?? host)
        if let index = robots.firstIndex(where: { $0.name == robot.name }) {
            robot.remote = robots[index].remote
            if robots[index] != robot { robots[index] = robot }
        } else {
            robots.append(robot)
        }
        return robot
    }

    nonisolated static func load() -> [Robot] { Shared.robots }

    /// Saves a robot's remote address after checking BEacon answers there; "" removes it.
    func setRemote(_ address: String, for robot: Robot) async -> String? {
        let address = address.trimmingCharacters(in: .whitespaces)
        var updated = robot
        updated.remote = address.isEmpty ? nil : (address.contains("://") ? address : "https://" + address)
        if let url = updated.remoteURL {
            guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: URL(string: "api/status", relativeTo: url)!, timeoutInterval: 10)),
                  (try? JSONDecoder().decode(Status.self, from: data))?.name == "BEacon" else {
                return "No BEacon answered at \(url.absoluteString)."
            }
        } else if updated.remote != nil {
            return "That isn't a web address."
        }
        if let index = robots.firstIndex(where: { $0.name == robot.name }) { robots[index] = updated }
        return nil
    }
}

private struct Status: Decodable {
    struct Address: Decodable { let address: String }
    let name: String
    let hostname: String?
    let addresses: [Address]?
}
