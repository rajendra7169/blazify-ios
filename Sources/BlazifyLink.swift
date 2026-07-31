import Foundation

/// The deep links the Home Screen widget opens. Shared with the widget target
/// so both sides can't drift — a widget tapping a URL the app doesn't handle
/// would just open the app and do nothing.
enum BlazifyLink {
    static let scheme = "blazify"

    static var resume: URL { URL(string: "\(scheme)://resume")! }
    static var favourites: URL { URL(string: "\(scheme)://favourites")! }
    static var downloads: URL { URL(string: "\(scheme)://downloads")! }
    static var recognise: URL { URL(string: "\(scheme)://recognise")! }
}
