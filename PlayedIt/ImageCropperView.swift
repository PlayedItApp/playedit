import SwiftUI

struct ImageCropperView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let cropSize: CGFloat = 280
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    Text("Move and scale")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    // Crop area
                    ZStack {
                        // The image (draggable and zoomable)
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cropSize * scale, height: cropSize * scale)
                            .offset(offset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                        constrainOffset()
                                    }
                            )
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastScale * value
                                        scale = min(max(newScale, 1.0), 4.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        constrainOffset()
                                    }
                            )
                        
                        // Dark overlay with circular cutout
                        CircleCutoutOverlay(cropSize: cropSize)
                            .allowsHitTesting(false)
                    }
                    .frame(width: cropSize, height: cropSize)
                    .clipShape(Rectangle())
                    
                    Spacer()
                    
                    // Buttons
                    HStack(spacing: 40) {
                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .frame(width: 100, height: 44)
                        }
                        
                        Button {
                            let croppedImage = cropImage()
                            onCrop(croppedImage)
                        } label: {
                            Text("Choose")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                                .frame(width: 100, height: 44)
                                .background(Color.white)
                                .cornerRadius(22)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private func constrainOffset() {
        let maxOffset = (cropSize * scale - cropSize) / 2
        
        withAnimation(.easeOut(duration: 0.2)) {
            offset.width = min(max(offset.width, -maxOffset), maxOffset)
            offset.height = min(max(offset.height, -maxOffset), maxOffset)
            lastOffset = offset
        }
    }
    
    private func cropImage() -> UIImage {
        let imageSize = image.size
        let cropRect: CGRect
        
        // Calculate the visible portion of the image
        let scaledImageSize = CGSize(
            width: cropSize * scale,
            height: cropSize * scale
        )
        
        // Center point of crop area in image coordinates
        let centerOffsetX = -offset.width / scaledImageSize.width
        let centerOffsetY = -offset.height / scaledImageSize.height
        
        // Size of crop area relative to scaled image
        let cropRatio = cropSize / scaledImageSize.width
        
        // Convert to image coordinates
        let cropX = (0.5 + centerOffsetX - cropRatio / 2) * imageSize.width
        let cropY = (0.5 + centerOffsetY - cropRatio / 2) * imageSize.height
        let cropWidth = cropRatio * imageSize.width
        let cropHeight = cropRatio * imageSize.height
        
        cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        // Ensure crop rect is within bounds
        let safeCropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))
        
        // Crop the image
        guard let cgImage = image.cgImage?.cropping(to: safeCropRect) else {
            return image
        }
        
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        
        // Resize to a reasonable size for upload (e.g., 400x400)
        let outputSize = CGSize(width: 400, height: 400)
        UIGraphicsBeginImageContextWithOptions(outputSize, false, 1.0)
        croppedImage.draw(in: CGRect(origin: .zero, size: outputSize))
        let finalImage = UIGraphicsGetImageFromCurrentImageContext() ?? croppedImage
        UIGraphicsEndImageContext()
        
        return finalImage
    }
}

// MARK: - Circle Cutout Overlay
struct CircleCutoutOverlay: View {
    let cropSize: CGFloat
    
    var body: some View {
        Canvas { context, size in
            // Fill entire area with semi-transparent black
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.black.opacity(0.6))
            )
            
            // Cut out a circle in the center
            let circleRect = CGRect(
                x: (size.width - cropSize) / 2,
                y: (size.height - cropSize) / 2,
                width: cropSize,
                height: cropSize
            )
            context.blendMode = .destinationOut
            context.fill(
                Path(ellipseIn: circleRect),
                with: .color(.white)
            )
        }
        .frame(width: cropSize, height: cropSize)
    }
}

#Preview {
    ImageCropperView(
        image: UIImage(systemName: "person.fill")!,
        onCrop: { _ in },
        onCancel: { }
    )
}
