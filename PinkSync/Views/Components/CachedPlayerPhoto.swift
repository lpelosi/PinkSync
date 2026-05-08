import SwiftUI

struct CachedPlayerPhoto: View {
    let url: URL?
    var size: CGFloat = 32

    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) {
            guard !loaded, let url else { return }
            image = await PhotoCache.shared.image(for: url)
            loaded = true
        }
    }
}
