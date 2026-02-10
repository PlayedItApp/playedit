import SwiftUI

struct SpoilerTextView: View {
    let text: String
    let font: Font
    let color: Color
    
    @State private var revealedSpoilers: Set<Int> = []
    
    init(_ text: String, font: Font = .system(size: 15, design: .rounded), color: Color = .slate) {
        self.text = text
        self.font = font
        self.color = color
    }
    
    // Parse text into segments: plain text and spoiler blocks
    private var segments: [TextSegment] {
        var result: [TextSegment] = []
        var remaining = text
        var spoilerIndex = 0
        
        while let startRange = remaining.range(of: "||") {
            // Add plain text before the spoiler
            let before = String(remaining[remaining.startIndex..<startRange.lowerBound])
            if !before.isEmpty {
                result.append(.plain(before))
            }
            
            // Find the closing ||
            let afterStart = remaining[startRange.upperBound...]
            if let endRange = afterStart.range(of: "||") {
                let spoilerContent = String(afterStart[afterStart.startIndex..<endRange.lowerBound])
                if !spoilerContent.isEmpty {
                    result.append(.spoiler(spoilerContent, index: spoilerIndex))
                    spoilerIndex += 1
                }
                remaining = String(afterStart[endRange.upperBound...])
            } else {
                // No closing || found, treat rest as plain text
                remaining = String(remaining[startRange.lowerBound...])
                result.append(.plain(remaining))
                remaining = ""
            }
        }
        
        // Add any remaining plain text
        if !remaining.isEmpty {
            result.append(.plain(remaining))
        }
        
        return result
    }
    
    var body: some View {
        WrappingHStack(segments: segments, font: font, color: color, revealedSpoilers: $revealedSpoilers)
    }
}

// MARK: - Text Segment
private enum TextSegment {
    case plain(String)
    case spoiler(String, index: Int)
}

// MARK: - Wrapping HStack for inline spoilers
private struct WrappingHStack: View {
    let segments: [TextSegment]
    let font: Font
    let color: Color
    @Binding var revealedSpoilers: Set<Int>
    
    var body: some View {
        // For mixed content, use a vertical layout that flows naturally
        let parsedSegments = segments
        
        // Build the view
        VStack(alignment: .leading, spacing: 0) {
            buildText(from: parsedSegments)
        }
    }
    
    @ViewBuilder
    private func buildText(from segments: [TextSegment]) -> some View {
        // Check if there are any spoilers
        let hasSpoilers = segments.contains { segment in
            if case .spoiler = segment { return true }
            return false
        }
        
        if !hasSpoilers {
            // No spoilers, just render plain text
            let fullText = segments.map { segment in
                if case .plain(let text) = segment { return text }
                return ""
            }.joined()
            
            Text(fullText)
                .font(font)
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Has spoilers - use string interpolation for inline flow
            Text(segments.reduce(into: AttributedString()) { result, segment in
                switch segment {
                case .plain(let text):
                    var attr = AttributedString(text)
                    attr.font = font
                    attr.foregroundColor = color
                    result.append(attr)
                case .spoiler(let text, let index):
                    if revealedSpoilers.contains(index) {
                        var attr = AttributedString(text)
                        attr.font = font
                        attr.foregroundColor = color
                        result.append(attr)
                    } else {
                        let placeholder = String(repeating: "█", count: min(text.count, 20))
                        var attr = AttributedString(placeholder)
                        attr.font = font
                        attr.foregroundColor = Color.black.opacity(0.85)
                        result.append(attr)
                    }
                }
            })
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture {
                // Reveal all spoilers on tap
                for segment in segments {
                    if case .spoiler(_, let index) = segment {
                        _ = withAnimation(.easeOut(duration: 0.2)) {
                            revealedSpoilers.insert(index)
                        }
                    }
                }
            }
            
            // Hint if there are unrevealed spoilers
            let unrevealedCount = segments.filter { segment in
                if case .spoiler(_, let index) = segment {
                    return !revealedSpoilers.contains(index)
                }
                return false
            }.count
            
            if unrevealedCount > 0 {
                Text("Tap to reveal spoilers")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.grayText)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Spoiler Syntax Hint
struct SpoilerHint: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.slash")
                .font(.system(size: 10))
            Text("Use ||spoiler text|| to hide spoilers")
                .font(.system(size: 11, design: .rounded))
        }
        .foregroundColor(.grayText)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        SpoilerTextView("This game was great! ||The ending where the hero dies|| really got me.")
        SpoilerTextView("No spoilers in this one, just a regular comment.")
        SpoilerTextView("||Everything is a spoiler here||")
        SpoilerHint()
    }
    .padding()
}
