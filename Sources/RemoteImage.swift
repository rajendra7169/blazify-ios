import SwiftUI
import UIKit

/// In-memory image cache so home/library rails don't re-fetch — and flicker or
/// fail — every time a card scrolls out and back into a Lazy stack. (AsyncImage
/// caches nothing and cancels its load on reuse, which is why New-releases art
/// sometimes never appeared.)
enum ImageCache {
    static let store: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 300
        return c
    }()
}

/// Drop-in replacement for AsyncImage that caches decoded images and survives reuse.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = ImageCache.store.object(forKey: url as NSURL) {
            image = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let ui = UIImage(data: data) else { return }
        ImageCache.store.setObject(ui, forKey: url as NSURL)
        image = ui
    }
}
