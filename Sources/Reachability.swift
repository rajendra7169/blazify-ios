import Combine
import Foundation
import Network

/// Whether the device can reach the network at all. Home watches this so that,
/// with no connection, it shows the music actually saved on the device instead
/// of a feed that can never load.
final class Reachability: ObservableObject {
    static let shared = Reachability()

    @Published private(set) var isOnline = true
    /// False on cellular or a personal hotspot — "Auto" audio quality drops to
 /// the smaller stream there, as the Auto quality setting does.
    @Published private(set) var isUnmetered = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let unmetered = !path.isExpensive && !path.isConstrained
            Task { @MainActor in
                guard let self else { return }
                if self.isOnline != online { self.isOnline = online }
                if self.isUnmetered != unmetered { self.isUnmetered = unmetered }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.blazify.reachability"))
    }
}
