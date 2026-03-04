import SwiftUI

struct FeedSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                SkeletonGroupedCard()
                SkeletonSingleCard()
                SkeletonGroupedCard()
                SkeletonSingleCard()
                SkeletonGroupedCard()
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct SkeletonSingleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SkeletonBox(width: 50, height: 67, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBox(width: 120, height: 12, cornerRadius: 4)
                    SkeletonBox(width: 180, height: 16, cornerRadius: 4)
                    SkeletonBox(width: 80, height: 12, cornerRadius: 4)
                }
                Spacer()
                SkeletonBox(width: 28, height: 28, cornerRadius: 14)
            }
            .padding(12)
            Divider().padding(.horizontal, 12)
            HStack(spacing: 24) {
                SkeletonBox(width: 40, height: 18, cornerRadius: 4)
                SkeletonBox(width: 40, height: 18, cornerRadius: 4)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct SkeletonGroupedCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SkeletonBox(width: 36, height: 36, cornerRadius: 18)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBox(width: 160, height: 14, cornerRadius: 4)
                    SkeletonBox(width: 80, height: 11, cornerRadius: 4)
                }
                Spacer()
            }
            .padding(12)
            
            HStack(spacing: 8) {
                SkeletonBox(width: nil, height: 60, cornerRadius: 6)
                SkeletonBox(width: nil, height: 60, cornerRadius: 6)
                SkeletonBox(width: nil, height: 60, cornerRadius: 6)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            
            Divider().padding(.horizontal, 12)
            
            HStack(spacing: 24) {
                SkeletonBox(width: 40, height: 18, cornerRadius: 4)
                SkeletonBox(width: 40, height: 18, cornerRadius: 4)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider().padding(.horizontal, 12)
            
            SkeletonBox(width: 120, height: 14, cornerRadius: 4)
                .padding(12)
        }
        .background(Color.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct SkeletonBox: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.adaptiveSilver.opacity(0.3))
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    Color.white.opacity(0.4)
                        .frame(width: 60)
                        .blur(radius: 8)
                        .offset(x: shimmer ? geo.size.width + 60 : -60)
                }
                .clipped()
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
    }
}
