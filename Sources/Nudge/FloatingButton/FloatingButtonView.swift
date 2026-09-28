import Observation
import SwiftUI

enum FloatingButtonStyle: String, CaseIterable {
    /// A small tab against the edge: dot + count.
    case tab
    /// A small round button just off the edge.
    case dot
    /// A thin bar on the edge that expands into the tab on hover.
    case handle
    /// A round accent-colored button with an icon and a count badge.
    case bubble

    var title: String {
        switch self {
        case .tab: "Edge tab"
        case .dot: "Dot"
        case .handle: "Slim handle"
        case .bubble: "Bubble"
        }
    }
}

@MainActor
@Observable
final class FloatingButtonState {
    var style: FloatingButtonStyle = .tab
    var count = 0
    var attention = false
    var showsCount = true
    var edge: ScreenEdge = .right
    var isHovered = false
    var isDragging = false
    /// Incremented to play the nudge animation.
    var nudgeCount = 0

    /// Room around the button for its soft shadow (not on the screen-edge side).
    static let shadowInset: CGFloat = 8

    var isActive: Bool { isHovered || isDragging }
    private var showsNumber: Bool { showsCount && count > 0 }

    /// The visible button's size for the current style and hover state.
    var buttonSize: NSSize {
        switch style {
        case .tab:
            return tabSize(grown: isActive)
        case .handle:
            return isActive ? tabSize(grown: false) : NSSize(width: 5, height: 48)
        case .dot:
            return NSSize(width: 26, height: 26)
        case .bubble:
            return NSSize(width: 34, height: 34)
        }
    }

    /// Gap between the button and the screen edge.
    var edgeGap: CGFloat {
        switch style {
        case .tab, .handle: 0
        case .dot, .bubble: 4
        }
    }

    var windowSize: NSSize {
        let button = buttonSize
        // The bubble's badge can stick out past the circle.
        let badge: CGFloat = style == .bubble && showsNumber ? 6 : 0
        return NSSize(
            width: button.width + edgeGap + Self.shadowInset + badge,
            height: button.height + Self.shadowInset * 2 + badge
        )
    }

    private func tabSize(grown: Bool) -> NSSize {
        let digits = CGFloat(String(count).count)
        var width: CGFloat = showsNumber ? 38 + digits * 8 : 30
        if showsNumber && attention { width += 10 } // the red badge's padding
        return NSSize(width: width + (grown ? 4 : 0), height: 36)
    }
}

/// The floating button, drawn in the chosen style. Uses an adaptive (light/dark) material
/// and a soft shadow rather than a hard window outline.
struct FloatingButtonView: View {
    let state: FloatingButtonState

    var body: some View {
        let awayFromEdge: CGFloat = state.edge == .right ? -1 : 1
        content
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            // Nudge: a small bounce away from the screen edge, within the shadow margin.
            .keyframeAnimator(initialValue: CGFloat(0), trigger: state.nudgeCount) { view, distance in
                view.offset(x: awayFromEdge * distance)
            } keyframes: { _ in
                SpringKeyframe(8, duration: 0.14)
                SpringKeyframe(0, duration: 0.2)
                SpringKeyframe(5, duration: 0.12)
                SpringKeyframe(0, duration: 0.3)
            }
            .opacity(state.isActive || state.style == .bubble ? 1 : 0.85)
            .padding(state.edge == .right ? .trailing : .leading, state.edgeGap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: state.edge == .right ? .trailing : .leading)
            .animation(.easeOut(duration: 0.15), value: state.isActive)
            .animation(.easeOut(duration: 0.2), value: state.count)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch state.style {
        case .tab:
            tab
        case .handle:
            if state.isActive {
                tab
            } else {
                Capsule()
                    .fill(state.attention ? Theme.red : Color.primary.opacity(0.35))
                    .frame(width: 5, height: 48)
            }
        case .dot:
            dot
        case .bubble:
            bubble
        }
    }

    private var tab: some View {
        let shape = edgeShape
        return HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
            if state.showsCount && state.count > 0 {
                if state.attention {
                    // White on solid red reads clearly in both light and dark mode.
                    Text("\(state.count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.attentionFill))
                } else {
                    Text("\(state.count)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .frame(width: state.buttonSize.width, height: state.buttonSize.height)
        .background(VisualEffectBackground(material: .popover).clipShape(shape))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var dot: some View {
        ZStack {
            if state.showsCount && state.count > 0 {
                countText
            } else {
                Circle().fill(dotColor).frame(width: 7, height: 7)
            }
        }
        .frame(width: 26, height: 26)
        .background(VisualEffectBackground(material: .popover).clipShape(Circle()))
        .overlay(Circle().strokeBorder(state.attention ? Theme.red : Color.primary.opacity(0.1), lineWidth: state.attention ? 1.5 : 0.5))
    }

    private var bubble: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(state.attention ? Theme.red : Theme.accent)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "checklist")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )
            if state.showsCount && state.count > 0 {
                Text("\(state.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Color(white: 0.2)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                    .offset(x: 6, y: -6)
            }
        }
    }

    private var countText: some View {
        Text("\(state.count)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(state.attention ? Theme.red : Color.primary)
    }

    /// Rounded only on the side facing away from the screen edge.
    private var edgeShape: UnevenRoundedRectangle {
        let r: CGFloat = 11
        return state.edge == .right
            ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, style: .continuous)
            : UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    private var dotColor: Color {
        if state.attention { return Theme.attentionFill }
        return state.count > 0 ? Theme.accent : .secondary
    }

    private var accessibilityText: String {
        var text = "Nudge, \(state.count) task\(state.count == 1 ? "" : "s") today"
        if state.attention { text += ", something is overdue" }
        return text
    }
}
