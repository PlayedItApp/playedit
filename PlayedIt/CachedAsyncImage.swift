import SwiftUI

struct CachedAsyncImage<Placeholder: View>: View {
    let urlString: String?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    private func cachedImage() -> UIImage? {
        guard let urlString, !urlString.isEmpty else { return nil }
        let key = urlString.utf8.reduce(into: UInt64(5381)) { result, byte in
            result = result &* 33 &+ UInt64(byte)
        }
        let cacheKey = "\(key).jpg"
        return ImageCache.shared.memoryCache.object(forKey: cacheKey as NSString)
    }
    
    init(
        url urlString: String?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urlString = urlString
        self.contentMode = contentMode
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image ?? cachedImage() {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: urlString) {
            guard let urlString, !urlString.isEmpty else {
                isLoading = false
                return
            }
            image = await ImageCache.shared.image(for: urlString)
            isLoading = false
        }
    }
}
