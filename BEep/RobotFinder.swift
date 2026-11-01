import Foundation
import Network

struct Robot: Identifiable, Hashable, Codable {
    var name: String
    var host: String
    var id: String { name }
    var url: URL { URL(string: "http://\(host):8123/")! }
}

/// Finds Jibos on the Wi-Fi and remembers them. Jibo's avahi advertises SSH under the robot's
/// name, so browse that and keep only hosts whose BEacon answers /api/status.
@MainActor
final class RobotFinder: ObservableObject {
    @Published var robots: [Robot] = RobotFinder.load() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(robots), forKey: "robots") }
    }
    private var browser: NWBrowser?

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
        let robot = Robot(name: status.hostname ?? host,
                          host: status.addresses?.first(where: { $0.address.contains(".") })?.address ?? host)
        if let index = robots.firstIndex(where: { $0.name == robot.name }) {
            if robots[index] != robot { robots[index] = robot }
        } else {
            robots.append(robot)
        }
        return robot
    }

    nonisolated static func load() -> [Robot] {
        guard let data = UserDefaults.standard.data(forKey: "robots") else { return [] }
        return (try? JSONDecoder().decode([Robot].self, from: data)) ?? []
    }
}

private struct Status: Decodable {
    struct Address: Decodable { let address: String }
    let name: String
    let hostname: String?
    let addresses: [Address]?
}
