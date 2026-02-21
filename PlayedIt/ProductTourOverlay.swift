import SwiftUI

struct ProductTourOverlay: View {
    let anchors: [String: CGRect]
    let onDismiss: () -> Void
    
    @State private var currentStep = 0
    @State private var showContent = false
    
    private let steps: [TourStep] = [
        TourStep(
            message: "Here's your ranked list!",
            subtitle: "Every game you rank shows up here",
            anchorKey: "rankedList"
        ),
        TourStep(
            message: "Find your friends",
            subtitle: "Add friends by username and compare taste",
            anchorKey: "friendsTab"
        ),
        TourStep(
            message: "Check out settings",
            subtitle: "Import your Steam library and more",
            anchorKey: "settingsButton"
        ),
        TourStep(
            message: "Ready to rank?",
            subtitle: "Tap + to log your next game!",
            anchorKey: "plusButton"
        )
    ]
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let topInset = geometry.safeAreaInsets.top
            
            ZStack {
                // Dimmed background
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { }
                
                if currentStep < steps.count {
                    let step = steps[currentStep]
                    let target = targetPoint(for: step, width: width, height: height, topInset: topInset)
                    let tooltip = tooltipCenter(for: step, target: target, width: width, height: height)
                    let arrowFrom = arrowStartPoint(tooltip: tooltip, target: target)
                    
                    // Calculate arrow endpoint at circle edge
                    let circleRadius = highlightSize(for: step) / 2
                    let arrowEnd = arrowEndPoint(from: arrowFrom, to: target, circleRadius: circleRadius)
                    
                    // Curved arrow
                    CurvedArrowShape(from: arrowFrom, to: arrowEnd)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.1), value: showContent)
                    
                    // Arrowhead
                    ArrowHead(at: arrowEnd, controlFrom: arrowFrom)
                        .fill(Color.cardBackground)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.1), value: showContent)
                    
                    // Highlight ring
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 2.5)
                        .frame(width: highlightSize(for: step), height: highlightSize(for: step))
                        .position(target)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.2), value: showContent)
                    
                    // Tooltip card
                    tooltipCard(step: step)
                        .position(tooltip)
                        .opacity(showContent ? 1 : 0)
                        .scaleEffect(showContent ? 1 : 0.8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showContent)
                    
                    // Tap anywhere to advance
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            advanceStep()
                        }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showContent = true
            }
        }
    }
    
    // MARK: - Target from anchors
    
    private func targetPoint(for step: TourStep, width: CGFloat, height: CGFloat, topInset: CGFloat) -> CGPoint {
            switch step.anchorKey {
            case "plusButton":
                // + button is top-left toolbar item
                return CGPoint(x: 38, y: 82)
            case "settingsButton":
                // ... button is top-right toolbar item
                return CGPoint(x: width - 38, y: 84)
            case "friendsTab":
                // Friends is the middle tab (2nd of 3)
                return CGPoint(x: width / 2, y: height - 48)
            case "rankedList":
                // Point at the #1 rank number
                if let rect = anchors[step.anchorKey] {
                    return CGPoint(x: 48, y: rect.minY + 90)
                }
                return CGPoint(x: 48, y: height * 0.42)
            default:
                if let rect = anchors[step.anchorKey] {
                    return CGPoint(x: rect.midX, y: rect.midY)
                }
                return CGPoint(x: width / 2, y: height / 2)
            }
        }
    
    private func highlightSize(for step: TourStep) -> CGFloat {
        switch step.anchorKey {
        case "rankedList": return 50 // Circle around #1 rank
        case "plusButton", "settingsButton": return 44
        case "friendsTab": return 50
        default: return 44
        }
    }
    
    // MARK: - Tooltip positioning (opposite side of target)
    
    private func tooltipCenter(for step: TourStep, target: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        switch step.anchorKey {
        case "rankedList":
            // Show above the list
            return CGPoint(x: width / 2, y: target.y - 160)
        case "plusButton":
            // Below and to the right
            return CGPoint(x: width / 2, y: target.y + 120)
        case "friendsTab":
            // Above the tab bar
            return CGPoint(x: width / 2, y: target.y - 150)
        case "settingsButton":
            // Below and to the left
            return CGPoint(x: width / 2, y: target.y + 120)
        default:
            return CGPoint(x: width / 2, y: height / 2)
        }
    }
    
    // MARK: - Arrow start (edge of tooltip toward target)
    
    private func arrowStartPoint(tooltip: CGPoint, target: CGPoint) -> CGPoint {
        let dx = target.x - tooltip.x
        let dy = target.y - tooltip.y
        let length = sqrt(dx*dx + dy*dy)
        guard length > 0 else { return tooltip }
        
        // Use 60% of the card's half-height as offset so arrow starts from card edge
        let offset: CGFloat = 80
        return CGPoint(
            x: tooltip.x + (dx / length) * offset,
            y: tooltip.y + (dy / length) * offset
        )
    }
    
    // MARK: - Arrow end (stop at circle edge, not center)
        
    private func arrowEndPoint(from: CGPoint, to: CGPoint, circleRadius: CGFloat) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx*dx + dy*dy)
        guard length > 0, circleRadius > 0 else { return to }
        
        let stopOffset = circleRadius + 4 // 4pt gap outside the circle
        return CGPoint(
            x: to.x - (dx / length) * stopOffset,
            y: to.y - (dy / length) * stopOffset
        )
    }
    
    // MARK: - Tooltip Card
    
    private func tooltipCard(step: TourStep) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(step.message)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(step.subtitle)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.white : Color.white.opacity(0.4))
                        .frame(width: 7, height: 7)
                }
            }
            
            Button {
                advanceStep()
            } label: {
                Text(currentStep == steps.count - 1 ? "Got it!" : "Next")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primaryBlue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.cardBackground)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primaryBlue)
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
        .frame(maxWidth: 280)
    }
    
    private func advanceStep() {
        if currentStep < steps.count - 1 {
            showContent = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                currentStep += 1
                showContent = true
            }
        } else {
            onDismiss()
        }
    }
}

// MARK: - Tour Step

struct TourStep {
    let message: String
    let subtitle: String
    let anchorKey: String
}

// MARK: - Curved Arrow Shape

struct CurvedArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dist = sqrt(dx*dx + dy*dy)
        let curveAmount: CGFloat = dist * 0.3
        
        let perpX = -dy / max(dist, 1) * curveAmount
        let perpY = dx / max(dist, 1) * curveAmount
        
        let control = CGPoint(
            x: (from.x + to.x) / 2 + perpX,
            y: (from.y + to.y) / 2 + perpY
        )
        
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
        
        return path
    }
}

// MARK: - Arrow Head

struct ArrowHead: Shape {
    let at: CGPoint
    let controlFrom: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Recalculate the control point to get tangent direction
        let dx = at.x - controlFrom.x
        let dy = at.y - controlFrom.y
        let dist = sqrt(dx*dx + dy*dy)
        let curveAmount: CGFloat = dist * 0.3
        let perpX = -dy / max(dist, 1) * curveAmount
        let perpY = dx / max(dist, 1) * curveAmount
        let control = CGPoint(
            x: (controlFrom.x + at.x) / 2 + perpX,
            y: (controlFrom.y + at.y) / 2 + perpY
        )
        
        // Tangent at t=1 of quadratic bezier: direction from control to endpoint
        let tangentX = at.x - control.x
        let tangentY = at.y - control.y
        let tangentLen = sqrt(tangentX*tangentX + tangentY*tangentY)
        
        guard tangentLen > 0 else { return path }
        
        let unitX = tangentX / tangentLen
        let unitY = tangentY / tangentLen
        let pX = -unitY
        let pY = unitX
        
        let size: CGFloat = 10
        
        path.move(to: at)
        path.addLine(to: CGPoint(
            x: at.x - unitX * size + pX * size * 0.6,
            y: at.y - unitY * size + pY * size * 0.6
        ))
        path.addLine(to: CGPoint(
            x: at.x - unitX * size - pX * size * 0.6,
            y: at.y - unitY * size - pY * size * 0.6
        ))
        path.closeSubpath()
        
        return path
    }
}

#Preview {
    ZStack {
        Color.gray
        ProductTourOverlay(anchors: [:], onDismiss: {})
    }
}
