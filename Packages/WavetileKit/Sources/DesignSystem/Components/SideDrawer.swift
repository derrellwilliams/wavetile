import SwiftUI

/// Twitter-style reveal drawer: the main content slides aside to uncover `drawer` underneath.
///
/// - `edge` is the side the drawer lives on: `.leading` slides content right (Twitter/X),
///   `.trailing` slides it left.
/// - Tap or drag the content to close; swipe in from `edge` to open while `edgeSwipeEnabled`.
///   For `.leading`, enable it only on root screens so it never fights the system back gesture.
/// - The content gets rounded corners and dims as it slides; feel is tuned via `Theme.motion`.
/// - With VoiceOver, the hidden layer is removed from the accessibility tree, and the
///   two-finger "escape" gesture closes the drawer.
public struct SideDrawer<Content: View, Drawer: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding private var isOpen: Bool
    private let edge: HorizontalEdge
    private let edgeSwipeEnabled: Bool
    private let content: Content
    private let drawer: Drawer

    /// Live finger translation while dragging. Plain state (not @GestureState) so the release can
    /// reset it in the same animation as the open/close change: one spring from the on-screen value.
    @State private var dragOffset: CGFloat = 0

    public init(
        isOpen: Binding<Bool>,
        edge: HorizontalEdge = .leading,
        edgeSwipeEnabled: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder drawer: () -> Drawer
    ) {
        _isOpen = isOpen
        self.edge = edge
        self.edgeSwipeEnabled = edgeSwipeEnabled
        self.content = content()
        self.drawer = drawer()
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = drawerWidth(in: proxy.size.width)
            let revealed = revealedAmount(dragOffset, width: width)
            let offset = direction * revealed
            let progress = revealed / width

            ZStack(alignment: edge == .leading ? .leading : .trailing) {
                // Only drawn while showing: a closed drawer under every screen would still reach
                // the accessibility tree (UIKit-backed lists ignore accessibilityHidden) and cost a render.
                if isOpen || revealed > 0 {
                    drawer
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        // Subtle parallax: the drawer drifts in slower than the content.
                        .offset(x: reduceMotion ? 0 : -direction * (1 - progress) * width * 0.25)
                        .opacity(0.4 + 0.6 * progress)
                        .accessibilityHidden(!isOpen)
                }

                // Shapes ignore the safe area so the clip covers the status bar and tab bar regions too.
                let card = RoundedRectangle(cornerRadius: theme.radius.sheet * progress, style: .continuous)
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask { card.ignoresSafeArea() }
                    .overlay {
                        card
                            .fill(.black.opacity(0.45 * progress))
                            .ignoresSafeArea()
                            .allowsHitTesting(isOpen)
                            .onTapGesture { setOpen(false) }
                            .accessibilityHidden(true)
                    }
                    // No blur radius while closed: a shadow on the whole tab view costs an extra
                    // render pass on every scrolling screen.
                    .shadow(color: .black.opacity(0.5 * progress), radius: progress > 0 ? 24 : 0)
                    .offset(x: offset)
                    .accessibilityHidden(isOpen)
                    .gesture(dragGesture(width: width), isEnabled: isOpen)
                    .overlay(alignment: edge == .leading ? .leading : .trailing) {
                        // Edge strip for swipe-to-open.
                        if !isOpen && edgeSwipeEnabled {
                            Color.clear
                                .frame(width: 20)
                                .contentShape(.rect)
                                .gesture(dragGesture(width: width))
                        }
                    }
            }
            .background(theme.palette.background.ignoresSafeArea())
            .animation(theme.motion.resolve(theme.motion.smooth, reduceMotion: reduceMotion), value: isOpen)
        }
        .accessibilityAction(.escape) { setOpen(false) }
        .sensoryFeedback(.impact(weight: .light), trigger: isOpen)
    }

    /// How far the drawer is revealed for a given drag, rubber-banding past fully open/closed.
    private func revealedAmount(_ drag: CGFloat, width: CGFloat) -> CGFloat {
        let raw = (isOpen ? width : 0) + direction * drag
        if raw > width { return width + Motion.rubberBand(raw - width, dimension: width) }
        if raw < 0 { return -Motion.rubberBand(-raw, dimension: width) }
        return raw
    }

    /// +1 when content moves right to reveal a leading drawer, -1 for trailing.
    private var direction: CGFloat { edge == .leading ? 1 : -1 }

    /// Wider at accessibility text sizes so long words in the drawer don't break.
    private func drawerWidth(in total: CGFloat) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? total * 0.92 : min(340, total * 0.84)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // 1:1 tracking: no animation while the finger is down.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragOffset = value.translation.width }
            }
            .onEnded { value in
                // Momentum projection: choose open/closed from where the flick is *going*.
                let resting: CGFloat = isOpen ? width : 0
                let projected = resting + direction * value.predictedEndTranslation.width
                let open = projected > width / 2

                // Velocity handoff: the spring starts at the finger's speed (relative to distance left).
                let current = revealedAmount(dragOffset, width: width)
                let remaining = (open ? width : 0) - current
                let velocity = direction * value.velocity.width
                let relative = abs(remaining) > 1 ? velocity / remaining : 0

                withAnimation(theme.motion.resolve(theme.motion.momentum(initialVelocity: relative), reduceMotion: reduceMotion)) {
                    isOpen = open
                    dragOffset = 0
                }
            }
    }

    /// Taps and the button: no gesture momentum, so a critically damped spring (no overshoot).
    private func setOpen(_ open: Bool) {
        withAnimation(theme.motion.resolve(theme.motion.smooth, reduceMotion: reduceMotion)) {
            isOpen = open
            dragOffset = 0
        }
    }
}

#Preview {
    @Previewable @State var isOpen = true
    SideDrawer(isOpen: $isOpen) {
        NavigationStack {
            Color.gray.opacity(0.2)
                .navigationTitle("Content")
                .toolbar { Button("Menu", glyph: .settings) { isOpen.toggle() } }
        }
    } drawer: {
        List { Text("Settings") }
    }
}
