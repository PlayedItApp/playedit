import SwiftUI

// MARK: - Preference Keys for Tour Anchors

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - View Modifier to report position

extension View {
    func tourAnchor(_ name: String) -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TourAnchorKey.self,
                    value: [name: geometry.frame(in: .global)]
                )
            }
        )
    }
}
