import SwiftUI

struct CachedPlayerPhoto: View {
    let url: URL?
    var size: CGFloat = 32

    @State private var image: UIImage?

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
            image = nil
            guard let url else { return }
            image = await PhotoCache.shared.image(for: url)
        }
    }
}
