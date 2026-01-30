import SwiftUI

struct ImageCropperView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    
    private let cropSize: CGFloat = 280
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let imageAreaHeight = geometry.size.height * 0.8
            let displaySize = calculateDisplaySize(screenWidth: screenWidth)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button("Cancel") {
                            onCancel()
                        }
                        .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text("Move and Scale")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button("Done") {
                            let cropped = performCrop(displaySize: displaySize, imageAreaHeight: imageAreaHeight)
                            onCrop(cropped)
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                    .padding(.top, 60)
                    .padding(.bottom, 16)
                    
                    Spacer()
                    
                    // Image cropping area
                    ZStack {
                        // The image - can be moved and scaled
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: displaySize.width * scale,
                                height: displaySize.height * scale
                            )
                            .offset(offset)
                        
                        // Circle border only (no dark overlay for simplicity)
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: cropSize, height: cropSize)
                    }
                    .frame(width: screenWidth, height: imageAreaHeight)
                    .clipped()
                    .contentShape(Rectangle())
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
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newScale = lastScale * value
                                scale = min(max(newScale, 0.5), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    
                    Spacer()
                    
                    // Instructions
                    Text("Pinch to zoom, drag to position")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.bottom, 40)
                }
            }
        }
    }
    
    private func calculateDisplaySize(screenWidth: CGFloat) -> CGSize {
        let availableWidth = screenWidth - 40
        let imageAspect = image.size.width / image.size.height
        
        if imageAspect > 1 {
            // Landscape
            return CGSize(width: availableWidth, height: availableWidth / imageAspect)
        } else {
            // Portrait or square
            let height = min(availableWidth / imageAspect, 500)
            return CGSize(width: height * imageAspect, height: height)
        }
    }
    
    private func performCrop(displaySize: CGSize, imageAreaHeight: CGFloat) -> UIImage {
        // Scaled display size
        let scaledWidth = displaySize.width * scale
        let scaledHeight = displaySize.height * scale
        
        // The ratio between actual image pixels and displayed pixels
        let pixelsPerPointX = image.size.width / scaledWidth
        let pixelsPerPointY = image.size.height / scaledHeight
        
        // When offset is POSITIVE, image moved RIGHT/DOWN
        // Circle shows more of LEFT/TOP, so crop center moves LEFT/UP
        let imageCenterX = image.size.width / 2
        let imageCenterY = image.size.height / 2
        
        let absoluteCropCenterX = imageCenterX - (offset.width * pixelsPerPointX)
        let absoluteCropCenterY = imageCenterY - (offset.height * pixelsPerPointY)
        
        // Crop size in pixels
        let cropSizeInPixels = cropSize * pixelsPerPointX
        
        // The crop rect (may extend outside image bounds)
        let cropX = absoluteCropCenterX - cropSizeInPixels / 2
        let cropY = absoluteCropCenterY - cropSizeInPixels / 2
        
        print("📐 Crop center: (\(absoluteCropCenterX), \(absoluteCropCenterY))")
        print("📐 Crop rect: (\(cropX), \(cropY), \(cropSizeInPixels), \(cropSizeInPixels))")
        print("📐 Image size: \(image.size)")
        print("📐 Offset: \(offset)")
        
        // Create output image with white background
        let outputSize = CGSize(width: 400, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        
        let finalImage = renderer.image { context in
            // Fill with white background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            
            // Calculate where to draw the image
            // Map from crop rect to output rect
            let scaleToOutput = outputSize.width / cropSizeInPixels
            
            // Where the image's (0,0) maps to in output coordinates
            let imageOriginInOutput = CGPoint(
                x: -cropX * scaleToOutput,
                y: -cropY * scaleToOutput
            )
            
            let imageDestRect = CGRect(
                x: imageOriginInOutput.x,
                y: imageOriginInOutput.y,
                width: image.size.width * scaleToOutput,
                height: image.size.height * scaleToOutput
            )
            
            // Draw the image
            image.draw(in: imageDestRect)
        }
        
        return finalImage
    }
}

#Preview {
    ImageCropperView(
        image: UIImage(systemName: "photo")!,
        onCrop: { _ in },
        onCancel: { }
    )
}
