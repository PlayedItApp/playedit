import SwiftUI

struct GameDescriptionView: View {
    let text: String
    @State private var isExpanded = false
    @State private var isTruncated = false
    
    private var formattedText: AttributedString {
        let isHTML = text.contains("<") && text.contains(">")
        
        if isHTML {
            // Convert HTML to plain text with formatting
            guard let data = text.data(using: .utf8),
                  let nsAttr = try? NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                  ) else {
                return AttributedString(strippedText)
            }
            
            // Convert to AttributedString and re-apply our styling
            var result = AttributedString(nsAttr)
            result.foregroundColor = Color.adaptiveGray
            result.font = .system(size: 14, design: .rounded)
            
            // Preserve bold/italic from HTML
            for run in result.runs {
                if let uiFont = run.uiKit.font {
                    let traits = uiFont.fontDescriptor.symbolicTraits
                    if traits.contains(.traitBold) && traits.contains(.traitItalic) {
                        result[run.range].font = .system(size: 14, weight: .bold, design: .rounded).italic()
                    } else if traits.contains(.traitBold) {
                        result[run.range].font = .system(size: 14, weight: .bold, design: .rounded)
                    } else if traits.contains(.traitItalic) {
                        result[run.range].font = .system(size: 14, design: .rounded).italic()
                    }
                }
            }
            
            return result
        } else {
            // Try markdown, fallback to plain text
            if let md = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                var result = md
                result.foregroundColor = Color.adaptiveGray
                result.font = .system(size: 14, design: .rounded)
                return result
            }
            return AttributedString(text)
        }
    }
    
    private var strippedText: String {
        var result = text
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(strippedText)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(Color.adaptiveGray)
            .lineLimit(isExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
            
            if isTruncated {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "More")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.primaryBlue)
                }
            }
        }
        .onAppear {
            debugLog("📝 Description length: \(strippedText.count), text: \(strippedText.prefix(50))")
            isTruncated = strippedText.count > 100
        }
    }
}
