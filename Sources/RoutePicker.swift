import AVKit
import SwiftUI

/// The system AirPlay button. It has to be UIKit — the route sheet is drawn by
/// the system and there's no SwiftUI equivalent that lists the actual devices;
/// anything hand-rolled could only deep link into Settings.
struct RoutePicker: UIViewRepresentable {
    var tint: UIColor
    var activeTint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        // The button draws its own glyph at whatever size the view is, so the
        // frame around it is what controls the icon size.
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = activeTint
    }
}
