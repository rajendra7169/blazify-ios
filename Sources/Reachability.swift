import Combine
import Foundation
import Network

/// Whether the device can reach the network at all. Home watches this so that,
/// with no connection, it shows the music actually saved on the device instead
/// of a feed that can never load.
final class Reachability: ObservableObject {
    static let shared = Reachability()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.blazify.reachability"))
    }
}
